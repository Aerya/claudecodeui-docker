# claudecodeui-docker

Image Docker GHCR personnelle pour CloudCLI / Claude Code UI, basée sur l'upstream :

- https://github.com/siteboon/claudecodeui

Objectifs :

- builder automatiquement une image `ghcr.io/aerya/claudecodeui-docker:latest`,
- intégrer Claude Code, Codex et Gemini CLI dans l'image,
- ajouter une traduction française via overlay,
- mises à jour automatiques depuis l'upstream tous les jours à 4h30 UTC.

Vous pouvez faire sans .env ni clés API dans les variables, tout peut se configurer dans la WebUI, je n'ai rien modifié.
J'ai ajouté un petit hint pour OpenAI qui a de temps en temps du mal à se connecter (et comme je suis en IP:port, je ne peux pas m'authentifier depuis la WebUI).

## Authentification des agents

Variables possibles dans `.env` :

```env
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
```
Ca se configure aussi depuis le terminal intégré selon les CLIs.


### CLIs agents

- `cloudcli` depuis `siteboon/claudecodeui`
- `claude` via `@anthropic-ai/claude-code`
- `codex` via `@openai/codex`
- `gemini` via `@google/gemini-cli`

### Outils / MCP

- `rtk`
- `agentmemory`
- `iii`
- `ctx7`
- `@upstash/context7-mcp`
- `@playwright/mcp`
- Chromium Playwright
- `github-mcp-server`, compilé depuis `github/github-mcp-server`
- `claude-flow@alpha`
- `ruv-swarm`
- `supermemory` MCP (https://app.supermemory.ai) — installé via `npx -y install-mcp@latest https://mcp.supermemory.ai/mcp --client claude`

### Skills installées au build dans `/opt/agent-defaults/root`

Copiées automatiquement au démarrage vers `/root/.claude` et `/root/.codex` :
- `frontend-design`
- `develop-userscripts`
- `github-actions-docs`
- `cloudflare`
- `docker-expert`
- `deployment-automation`
- `find-skills`
- `simple`
- `ui-component-patterns`
- `ui-ux-pro-max`
- `security-review`
- `coding-standards-best-practices`
- `performance-benchmark`

## Claude plugins

- `safety-hooks`
- `autonomous-skill`
- `claude-flow`
- `everything-claude-code` / `ecc`
- `claude-hud`
- `ui-ux-pro-max`
- `compound-engineering` (https://github.com/EveryInc/compound-engineering-plugin)

## Notes licence

L'upstream CloudCLI / Claude Code UI est sous licence AGPL-3.0-or-later.