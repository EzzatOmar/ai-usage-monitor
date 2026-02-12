# AI Usage Monitor

Native macOS menu bar app that monitors quota usage for Claude Code, Codex CLI, and Gemini CLI, and tracks Z.AI auth status.

## What it does

- Runs as a `MenuBarExtra` app with a compact SwiftUI panel.
- Polls every 60 seconds.
- Uses direct provider APIs as the primary path (no interactive CLI scraping).
- Shows remaining quota %, reset timing, and provider-specific error badges.
- Reuses local auth context from `~/.claude`, `~/.codex`, and `~/.gemini` where available.
- Supports Claude auth from local Claude credential files, `CLAUDE_ACCESS_TOKEN`, or a pasted setup-token.
- Includes Z.AI provider support via a pasted API key or env keys (`ZAI_API_KEY`, `ZAI_KEY`, `ZHIPU_API_KEY`, `ZHIPUAI_API_KEY`).

## Build

```bash
swift build
```

## Run

```bash
swift run AIUsageMonitor
```

## Tests

```bash
swift test
```

## DMG packaging

```bash
./Scripts/build_dmg.sh
```

This produces `dist/AIUsageMonitor.dmg`.

## Notes

- Endpoints used are not all public/stable and may evolve.
- When local credentials are missing or expired, the app reports `Auth needed` or `Token expired` without launching intrusive auth flows.
- When Claude shows `Auth needed`, click `Paste token`, run `claude setup-token` in Terminal, and paste the token.
- Claude also offers an optional `Allow keychain` action in the UI; keychain is off by default and only used after explicit opt-in.
- When Z.AI shows `Auth needed`, click `Set key` and paste your API key.
- Z.AI uses quota/usage monitor endpoints on `api.z.ai` to show usage when key auth is valid.
- Research details from CC-Cli-Quota are documented in `docs/CC_CLI_QUOTA_RESEARCH.md`.
