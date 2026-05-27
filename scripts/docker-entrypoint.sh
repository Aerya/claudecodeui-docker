#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[cloudcli-agentpack] %s\n' "$*"; }
warn() { printf '[cloudcli-agentpack][WARN] %s\n' "$*" >&2; }

mkdir -p \
  /root/.cloudcli \
  /root/.claude \
  /root/.codex \
  /root/.gemini \
  /root/.agentmemory \
  "${WORKSPACES_ROOT:-/workspace}"

sync_dir_once() {
  local src="$1"
  local dst="$2"
  if [ -d "$src" ]; then
    mkdir -p "$dst"
    # Copy only missing files; keep user changes in bind-mounted volumes.
    cp -an "$src"/. "$dst"/ 2>/dev/null || true
  fi
}

sync_dir_once "${AGENT_DEFAULTS_ROOT:-/opt/agent-defaults/root}/.claude" /root/.claude
sync_dir_once "${AGENT_DEFAULTS_ROOT:-/opt/agent-defaults/root}/.codex" /root/.codex
sync_dir_once "${AGENT_DEFAULTS_ROOT:-/opt/agent-defaults/root}/.gemini" /root/.gemini

# RTK init: idempotent and non-fatal.
if [ "${RTK_ENABLE:-true}" = "true" ] && command -v rtk >/dev/null 2>&1; then
  log "initializing RTK for Claude/Codex if needed"
  rtk init -g --auto-patch >/tmp/rtk-claude.log 2>&1 || warn "RTK Claude init failed; see /tmp/rtk-claude.log"
  rtk init -g --codex >/tmp/rtk-codex.log 2>&1 || warn "RTK Codex init failed; see /tmp/rtk-codex.log"
fi

# Start agentmemory local server.
if [ "${AGENTMEMORY_ENABLE:-true}" = "true" ] && command -v agentmemory >/dev/null 2>&1; then
  export AGENTMEMORY_URL="${AGENTMEMORY_URL:-http://127.0.0.1:3111}"
  if ! pgrep -f "agentmemory" >/dev/null 2>&1; then
    log "starting agentmemory"
    agentmemory > /root/.agentmemory/agentmemory.log 2>&1 &
  fi
  for i in $(seq 1 45); do
    if curl -fsS http://127.0.0.1:3111/agentmemory/health >/dev/null 2>&1; then
      log "agentmemory is ready"
      break
    fi
    sleep 1
  done
  agentmemory connect claude-code --with-hooks >/tmp/agentmemory-claude.log 2>&1 || warn "agentmemory Claude wiring failed; see /tmp/agentmemory-claude.log"
  agentmemory connect codex --with-hooks >/tmp/agentmemory-codex.log 2>&1 || warn "agentmemory Codex wiring failed; see /tmp/agentmemory-codex.log"
fi

# Claude Code plugins: cannot be made fully reliable at Docker build time when /root/.claude is bind-mounted.
# This bootstrap runs once per persistent volume and does not require remembering slash commands.
if [ "${CLAUDE_PLUGINS_BOOTSTRAP:-true}" = "true" ] && command -v claude >/dev/null 2>&1; then
  marker=/root/.claude/.agentpack-claude-plugins-v1
  if [ ! -f "$marker" ]; then
    log "bootstrapping Claude Code plugins, best effort"
    set +e
    timeout 120 claude plugin marketplace add pchalasani/claude-code-tools >/tmp/plugin-safety-hooks.market.log 2>&1
    timeout 120 claude plugin install safety-hooks@pchalasani-claude-code-tools --scope user >/tmp/plugin-safety-hooks.install.log 2>&1

    timeout 120 claude plugin marketplace add feiskyer/claude-code-settings >/tmp/plugin-autonomous.market.log 2>&1
    timeout 120 claude plugin install autonomous-skill@feiskyer-claude-code-settings --scope user >/tmp/plugin-autonomous.install.log 2>&1

    timeout 120 claude plugin marketplace add ruvnet/ruflo >/tmp/plugin-ruflo.market.log 2>&1
    timeout 120 claude plugin install claude-flow@ruvnet-ruflo --scope user >/tmp/plugin-ruflo.install.log 2>&1

    timeout 120 claude plugin marketplace add affaan-m/everything-claude-code >/tmp/plugin-ecc.market.log 2>&1
    timeout 120 claude plugin install everything-claude-code@everything-claude-code --scope user >/tmp/plugin-ecc.install.log 2>&1
    timeout 120 claude plugin install ecc@ecc --scope user >/tmp/plugin-ecc2.install.log 2>&1

    timeout 120 claude plugin marketplace add jarrodwatts/claude-hud >/tmp/plugin-hud.market.log 2>&1
    timeout 120 claude plugin install claude-hud --scope user >/tmp/plugin-hud.install.log 2>&1

    timeout 120 claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill >/tmp/plugin-uipro.market.log 2>&1
    timeout 120 claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill --scope user >/tmp/plugin-uipro.install.log 2>&1
    set -e
    date -u > "$marker"
  fi
fi

# MCP registration for Claude Code.
if command -v claude >/dev/null 2>&1; then
  if [ "${CONTEXT7_MCP_ENABLE:-true}" = "true" ]; then
    if [ -n "${CONTEXT7_API_KEY:-}" ]; then
      claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key "$CONTEXT7_API_KEY" >/tmp/claude-mcp-context7.log 2>&1 || true
    else
      claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp >/tmp/claude-mcp-context7.log 2>&1 || true
    fi
  fi

  if [ "${PLAYWRIGHT_MCP_ENABLE:-true}" = "true" ]; then
    claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest >/tmp/claude-mcp-playwright.log 2>&1 || true
  fi

  if [ "${GITHUB_MCP_ENABLE:-true}" = "true" ] && [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    claude mcp add --scope user github -- github-mcp-server stdio >/tmp/claude-mcp-github.log 2>&1 || true
  fi
fi

# MCP registration for Codex. Use command-based config so secrets can be inherited from env at runtime.
if command -v codex >/dev/null 2>&1; then
  if [ "${CODEX_AUTO_LOGIN:-true}" = "true" ] && [ -n "${OPENAI_API_KEY:-}" ] && ! codex login status >/dev/null 2>&1; then
    log "logging Codex with OPENAI_API_KEY"
    printenv OPENAI_API_KEY | codex login --with-api-key >/tmp/codex-login.log 2>&1 || warn "Codex login failed; see /tmp/codex-login.log"
  fi

  if [ "${CONTEXT7_MCP_ENABLE:-true}" = "true" ]; then
    codex mcp add context7 -- npx -y @upstash/context7-mcp >/tmp/codex-mcp-context7.log 2>&1 || true
  fi
  if [ "${PLAYWRIGHT_MCP_ENABLE:-true}" = "true" ]; then
    codex mcp add playwright -- npx -y @playwright/mcp@latest >/tmp/codex-mcp-playwright.log 2>&1 || true
  fi
  if [ "${GITHUB_MCP_ENABLE:-true}" = "true" ] && [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    codex mcp add github -- github-mcp-server stdio >/tmp/codex-mcp-github.log 2>&1 || true
  fi
  if [ "${AGENTMEMORY_ENABLE:-true}" = "true" ]; then
    codex mcp add agentmemory -- npx -y @agentmemory/mcp >/tmp/codex-mcp-agentmemory.log 2>&1 || true
  fi
fi

log "starting CloudCLI on ${HOST:-0.0.0.0}:${SERVER_PORT:-3001}"
exec cloudcli start --host "${HOST:-0.0.0.0}" --port "${SERVER_PORT:-3001}"
