# syntax=docker/dockerfile:1.7

FROM golang:latest AS github-mcp-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src/github-mcp-server
RUN git clone --depth 1 https://github.com/github/github-mcp-server.git .
RUN go build -o /out/github-mcp-server ./cmd/github-mcp-server

FROM node:22-bookworm

ARG CLOUDCLI_VERSION
ARG UPSTREAM_SHA
ARG BUILD_DATE

LABEL org.opencontainers.image.title="CloudCLI Docker"
LABEL org.opencontainers.image.description="Self-hosted CloudCLI web UI with Claude Code, Codex, Gemini, MCP servers and agent skills"
LABEL org.opencontainers.image.source="https://github.com/siteboon/claudecodeui"
LABEL org.opencontainers.image.version="${CLOUDCLI_VERSION}"
LABEL org.opencontainers.image.revision="${UPSTREAM_SHA}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"

ENV DEBIAN_FRONTEND=noninteractive
ENV HUSKY=0
ENV HOST=0.0.0.0
ENV SERVER_PORT=3001
ENV DATABASE_PATH=/root/.cloudcli/auth.db
ENV WORKSPACES_ROOT=/workspace
ENV AGENT_DEFAULTS_ROOT=/opt/agent-defaults/root
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    procps \
    ripgrep \
    fd-find \
    sqlite3 \
    python3 \
    python3-pip \
    python3-setuptools \
    build-essential \
    make \
    g++ \
    zip \
    unzip \
    tree \
    vim-tiny \
    tini \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/claudecodeui
COPY upstream/ ./
RUN npm ci
RUN npm run build \
  && mkdir -p /tmp/cloudcli-pack \
  && npm pack --pack-destination /tmp/cloudcli-pack \
  && npm install -g /tmp/cloudcli-pack/*.tgz

RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @openai/codex@latest \
    @google/gemini-cli@latest \
    @agentmemory/agentmemory@latest \
    @agentmemory/mcp@latest \
    ctx7@latest \
    @upstash/context7-mcp@latest \
    @playwright/mcp@latest \
    skills@latest \
    uipro-cli@latest \
    claude-flow@alpha \
    ruv-swarm@latest \
  && npm cache clean --force

COPY --from=github-mcp-builder /out/github-mcp-server /usr/local/bin/github-mcp-server

# Browser runtime for Playwright MCP. This makes the image larger, but avoids first-run downloads.
RUN npx -y playwright@latest install --with-deps chromium

# RTK: CLI proxy for token-efficient command output.
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
  | RTK_INSTALL_DIR=/usr/local/bin sh \
  && rtk --version || true

# agentmemory needs the iii runtime. Upstream currently documents iii v0.11.2 for Linux x64.
RUN curl -fsSL https://github.com/iii-hq/iii/releases/download/iii/v0.11.2/iii-x86_64-unknown-linux-gnu.tar.gz \
  | tar -xz -C /usr/local/bin \
  && chmod +x /usr/local/bin/iii \
  && iii --version || true

RUN mkdir -p \
    /workspace \
    /root/.cloudcli \
    /root/.claude \
    /root/.codex \
    /root/.gemini \
    /root/.agentmemory \
    /opt/agent-defaults/root/.claude/skills \
    /opt/agent-defaults/root/.codex/skills \
    /opt/agent-defaults/root/.gemini

# Install Open Agent Skills into a staging HOME at build time. The runtime entrypoint syncs them into /root,
# because bind-mounting /root/.claude or /root/.codex would otherwise hide build-time files.
RUN HOME=/opt/agent-defaults/root bash -lc '\
  set -eux; \
  install_skill() { \
    repo="$1"; skill="$2"; \
    npx -y skills@latest add "$repo" -g -a claude-code -a codex --skill "$skill" --copy --yes; \
  }; \
  install_skill https://github.com/anthropics/skills frontend-design; \
  install_skill https://github.com/xixu-me/skills develop-userscripts; \
  install_skill https://github.com/xixu-me/skills github-actions-docs; \
  install_skill https://github.com/cloudflare/skills cloudflare; \
  install_skill https://github.com/sickn33/antigravity-awesome-skills docker-expert; \
  install_skill https://github.com/supercent-io/skills-template deployment-automation; \
  install_skill https://github.com/vercel-labs/skills find-skills; \
  install_skill https://github.com/roin-orca/skills simple; \
  install_skill https://github.com/supercent-io/skills-template ui-component-patterns; \
'

# UI/UX Pro Max: use its CLI/repo layout when the generic skills CLI cannot discover it reliably.
RUN HOME=/opt/agent-defaults/root bash -lc '\
  set -eux; \
  tmp="$(mktemp -d)"; \
  git clone --depth 1 https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git "$tmp/uipro"; \
  mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills"; \
  if [ -d "$tmp/uipro/.claude/skills/ui-ux-pro-max" ]; then \
    cp -a "$tmp/uipro/.claude/skills/ui-ux-pro-max" "$HOME/.claude/skills/ui-ux-pro-max"; \
    cp -a "$tmp/uipro/.claude/skills/ui-ux-pro-max" "$HOME/.codex/skills/ui-ux-pro-max"; \
  elif [ -d "$tmp/uipro/src/ui-ux-pro-max" ]; then \
    cp -a "$tmp/uipro/src/ui-ux-pro-max" "$HOME/.claude/skills/ui-ux-pro-max"; \
    cp -a "$tmp/uipro/src/ui-ux-pro-max" "$HOME/.codex/skills/ui-ux-pro-max"; \
  fi; \
  rm -rf "$tmp"; \
'

# Extra portable fallback skills for MCPMarket entries that do not expose a stable npx install command.
RUN <<'BASH'
set -eux

for agent in .claude .codex; do
  base="/opt/agent-defaults/root/$agent/skills"
  mkdir -p "$base/security-review" "$base/coding-standards-best-practices" "$base/performance-benchmark"

  cat > "$base/security-review/SKILL.md" <<'SKILL'
---
name: security-review
description: Use for security audits, hardening, secrets checks, auth/API validation, Docker/CI security review, XSS/CSRF/SQL injection checks, and pre-production reviews.
---
Perform a practical security review. Check for secrets, unsafe auth/session handling, injection risks, path traversal, unsafe shell execution, insecure Docker/CI patterns, overbroad permissions, missing validation, and unsafe defaults. Prefer concrete fixes with file paths and minimal changes. For code changes, avoid destructive operations and explain risk level.
SKILL

  cat > "$base/coding-standards-best-practices/SKILL.md" <<'SKILL'
---
name: coding-standards-best-practices
description: Use when designing, refactoring, or reviewing TypeScript, JavaScript, React, Node, Python, Docker, and CI code for maintainability, clarity, architecture, naming, and best practices.
---
Apply pragmatic coding standards: small cohesive modules, explicit names, strict types where available, clear error handling, testable boundaries, simple APIs, accessible UI, minimal dependencies, and no speculative abstraction. Prefer KISS/YAGNI over cleverness. When editing, keep diffs narrow and consistent with the existing project style.
SKILL

  cat > "$base/performance-benchmark/SKILL.md" <<'SKILL'
---
name: performance-benchmark
description: Use for measuring performance, setting baselines, comparing before/after changes, checking build/test latency, API latency, frontend Web Vitals, Docker image size, and regression risk.
---
Create or run lightweight benchmarks before claiming performance improvement. Prefer reproducible commands, clear before/after metrics, and saved baselines when useful. Look at build time, startup time, bundle size, Docker image size, API p50/p95/p99 latency, memory use, and frontend Core Web Vitals depending on the project. Separate measured facts from assumptions.
SKILL
done
BASH

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /workspace
EXPOSE 3001
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
