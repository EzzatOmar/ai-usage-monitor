# CC-Cli-Quota Research Notes

Source reviewed: `https://github.com/FlameZerg/CC-Cli-Quota`

## Goal

Understand how the VS Code extension handles Claude and Z.AI auth/usage so we can align the macOS app behavior.

## Claude findings

- The extension script discovers credentials in this order:
  1. macOS Keychain service `Claude Code-credentials`
  2. credential files:
     - `~/.claude/.credentials.json`
     - `~/.claude/credentials.json`
     - `~/.config/claude/credentials.json`
  3. `CLAUDE_ACCESS_TOKEN` environment variable
- Usage endpoint is `GET https://api.anthropic.com/api/oauth/usage`.
- Required headers include:
  - `Authorization: Bearer <token>`
  - `anthropic-beta: oauth-2025-04-20`

### Key references

- `.research/CC-Cli-Quota/cclimits.py:221`
- `.research/CC-Cli-Quota/cclimits.py:261`

## Z.AI findings

- Credential sources are env vars: `ZAI_API_KEY`, `ZAI_KEY`, `ZHIPU_API_KEY`, `ZHIPUAI_API_KEY`.
- Quota endpoint:
  - `GET https://api.z.ai/api/monitor/usage/quota/limit`
  - `Authorization` header is raw API key (not Bearer)
- Weekly usage endpoint:
  - `GET https://api.z.ai/api/monitor/usage/model-usage?startTime=...&endTime=...`
- Fallback auth probe if quota APIs fail:
  - `GET https://chat.z.ai/api/v1/auths/` with Bearer token

### Key references

- `.research/CC-Cli-Quota/cclimits.py:797`
- `.research/CC-Cli-Quota/cclimits.py:806`

## VS Code UX pattern

- Extension provides quick settings to paste and persist Z.AI API key.
- It injects configured key into the Python process environment when refreshing status.

### Key references

- `.research/CC-Cli-Quota/extension.js:97`
- `.research/CC-Cli-Quota/extension.js:229`

## Applied updates in this Swift app

- Claude credential discovery now checks:
  - pasted setup-token in app settings,
  - multiple local credential files,
  - `CLAUDE_ACCESS_TOKEN`.
- Added a Claude helper action in the menu row (`Paste token`) with inline guidance to run `claude setup-token`.
- Z.AI now supports:
  - pasted API key in app settings,
  - env fallback aliases,
  - quota + weekly usage API mapping into provider windows,
  - inline menu action (`Set key`) to configure key.
