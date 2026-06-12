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
ANTHROPIC_AUTH_TOKEN=
CLAUDE_CODE_OAUTH_TOKEN=
OPENAI_API_KEY=
GEMINI_API_KEY=
```
Ca se configure aussi depuis le terminal intégré selon les CLIs. Pour utiliser un abonnement Claude, laisser `ANTHROPIC_API_KEY` vide puis exécuter `claude auth login` dans le terminal intégré. Le dossier `/root/.claude` est persistant.

Le bouton de connexion Claude de l'upstream est patché au build pour exécuter `claude auth login`. La commande upstream `claude --dangerously-skip-permissions /login` est incompatible avec le processus `root` du conteneur.

Le bootstrap automatique des plugins Claude est désactivé par défaut afin de ne pas bloquer le démarrage ni perturber le diagnostic d'authentification. Pour l'activer :

```env
CLAUDE_PLUGINS_BOOTSTRAP=true
```


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
- `agent-reach` (https://github.com/Panniantong/Agent-Reach), installé dans un venv dédié et exposé dans le `PATH`

### Skills installées au build dans `/opt/agent-defaults/root`

Copiées automatiquement au démarrage vers `/root/.claude`, `/root/.codex` et `/root/.agents` :
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
- `agent-reach` (https://github.com/Panniantong/Agent-Reach)
- `Understand-Anything` (https://github.com/Lum1104/Understand-Anything)
- `mattpocock/skills` (https://github.com/mattpocock/skills)

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

## Revue continue des pull requests

Le service optionnel `pr-review-service` surveille les pull requests internes et
non brouillonnes de `Tracker-Dashboard/tracker-dashboard`. Il lance une revue lors
d'un nouveau SHA, puis une nouvelle intervention si un controle obligatoire
echoue. Les forks sont ignores et la fusion reste soumise aux protections GitHub.

Prerequis :

- Codex connecte avec ChatGPT dans le volume persistant `/root/.codex` ;
- un fine-grained PAT limite au depot cible avec `Contents: Read and write`,
  `Pull requests: Read and write`, `Actions: Read` et `Metadata: Read` ;
- le contexte prive monte dans `/workspace/private-context` ;
- `PR_MONITOR_ENABLED=true` dans `.env`.

Demarrage et suivi :

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose logs -f pr-review-service
```

Le service interroge GitHub toutes les cinq minutes par defaut. Il limite chaque
execution a 45 minutes et chaque etat en erreur a trois tentatives. Son historique
reste prive dans `/home/aerya/docker/claudecodeui/pr-monitor`.
