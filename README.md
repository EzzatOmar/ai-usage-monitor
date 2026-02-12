# AI Usage Monitor

Native macOS menu bar app that monitors quota usage for Claude Code, Codex CLI, and Gemini CLI, and tracks Z.AI auth status.

## What it does

- Runs as a `MenuBarExtra` app with a compact SwiftUI panel.
- Polls every 60 seconds.
- Uses direct provider APIs as the primary path (no interactive CLI scraping).
- Shows remaining quota %, reset timing, and provider-specific error badges.
- Reuses local auth context from `~/.claude`, `~/.codex`, and `~/.gemini` where available.
- Supports Claude setup-token fallback by invoking `claude setup-token` when `.claude/.credentials.json` is missing or unusable.
- Includes Z.AI provider support via `ZAI_API_KEY` environment variable.

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
- Z.AI currently reports auth presence (`ZAI_API_KEY`) but does not display quota windows yet because a stable usage endpoint is not documented in the provider docs.
