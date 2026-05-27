# claudecodeui-docker

Image Docker GHCR personnelle pour CloudCLI / Claude Code UI, basée sur l'upstream :

- https://github.com/siteboon/claudecodeui

Objectifs :

- builder automatiquement une image `ghcr.io/aerya/claudecodeui-docker:latest` ;
- intégrer Claude Code, Codex et Gemini CLI dans l'image ;
- ajouter une traduction française via overlay ;
- lancer ensuite le tout avec Docker Compose / Dockge, sans build local sur le serveur.

## Authentification des agents

Variables possibles dans `.env` :

```env
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
```
Ca se configure aussi depuis le terminal intégré selon les CLIs.

## Notes licence

L'upstream CloudCLI / Claude Code UI est sous licence AGPL-3.0-or-later.