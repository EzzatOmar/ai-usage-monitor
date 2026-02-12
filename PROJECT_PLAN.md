# AI Usage Monitor - Project Plan

## 1) Task Definition

Build a native macOS app (Apple Silicon first) named **AI Usage Monitor** that:

- runs as a menu bar app with a tiny native SwiftUI window,
- polls every 60 seconds,
- shows usage status for:
  - Claude Code,
  - Codex CLI,
  - Gemini CLI,
- displays remaining quota and reset timing, with provider-specific error states,
- uses existing local auth context where possible,
- avoids invasive auth UX.

Hard constraint from current direction:

- **Do not depend on interactive CLI scraping (`/usage`, `/status`, `/stats`) as the primary data path.**
- **Use API calls directly (with locally available OAuth/token material) and parse API responses.**

## 2) What I Learned (Web + codexbar research)

### Official docs insights

- Claude Code docs expose `/usage` and `/stats` in CLI, but that does not give a documented public REST endpoint for CLI subscription quota in docs.
- Codex docs/pricing confirm the 5-hour + weekly usage windows, matching your requested UX.
- Gemini docs + Google Cloud quotas document request limits; Gemini CLI public source shows a direct quota API call path.

### codexbar implementation insights

I cloned `https://github.com/steipete/codexbar` and inspected provider implementations.

Key findings:

- **Gemini:** uses direct API calls (not only CLI UI parsing).
  - Quota endpoint: `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`
  - Also calls `loadCodeAssist` to infer tier/project context.
  - Uses OAuth creds + refresh flow from local Gemini auth state.
  - Reference: `/.research/codexbar/Sources/CodexBarCore/Providers/Gemini/GeminiStatusProbe.swift`

- **Codex:** supports OAuth API fetch strategy in addition to CLI strategy.
  - Usage endpoint path resolved to ChatGPT backend (`/wham/usage` or `/api/codex/usage` depending base URL).
  - Uses bearer token from local Codex auth store and can refresh via OpenAI OAuth token endpoint.
  - References:
    - `/.research/codexbar/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift`
    - `/.research/codexbar/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexTokenRefresher.swift`
    - `/.research/codexbar/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift`

- **Claude:** includes OAuth API usage fetch strategy.
  - Endpoint: `GET https://api.anthropic.com/api/oauth/usage`
  - Requires bearer token and `anthropic-beta` header.
  - codexbar also has CLI and web strategies, but OAuth API path is available.
  - References:
    - `/.research/codexbar/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift`
    - `/.research/codexbar/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift`

## 3) Updated Technical Approach (API-first)

### Provider adapters

Implement one adapter per provider with a common output model:

- `ProviderUsageResult`
  - `provider`
  - `primaryWindow` (used/remaining/reset)
  - `secondaryWindow` (optional, weekly)
  - `accountLabel` (optional)
  - `lastUpdated`
  - `errorState` (auth missing, token expired, endpoint error, parse error)

### Codex adapter (API)

- Read local Codex auth material from `~/.codex/auth.json`.
- Refresh token when needed via OpenAI OAuth token endpoint.
- Call Codex usage endpoint with bearer auth.
- Map primary window to 5h and secondary to weekly.

### Claude adapter (API)

- Read available OAuth token source (non-invasive local source only).
- Call `https://api.anthropic.com/api/oauth/usage` with required beta header.
- Parse 5h and 7d windows from OAuth usage response.
- If refresh/token source unavailable, report `Auth needed` without prompting invasive flows.

### Gemini adapter (API)

- Read OAuth creds from local Gemini auth store.
- Refresh token if expired.
- Call `loadCodeAssist` (for project/tier context if needed).
- Call `retrieveUserQuota` every cycle.
- Map quota buckets to display windows/reset times.

## 4) App Architecture

- SwiftUI menu bar app (`MenuBarExtra`) + compact detail window.
- `UsageStore` actor:
  - timer-based 60s poll,
  - async concurrent fetch across providers,
  - stale-data protection + last-good snapshot.
- `ProviderClient` protocol + 3 concrete clients.
- `SecureRedactionLogger`:
  - logs errors and status,
  - never logs raw tokens.

## 5) UX Plan

- Menu bar label: aggregate health (e.g., minimum remaining percent or warning state).
- Tiny window sections:
  - Claude, Codex, Gemini rows,
  - remaining %, reset text, last update,
  - inline error badges (`Auth needed`, `API error`).
- Manual `Refresh now` action.
- No alerts/notifications (per requirement).

## 6) Risks and Mitigations

- **Undocumented/private endpoints may change:** isolate by provider and keep parser resilient.
- **Token refresh edge cases:** explicit auth-state machine + clear error messaging.
- **Different units (percent vs tokens):** normalize to percent + reset, expose raw fields if available.
- **No available local token for a provider:** show `Auth needed` without intrusive setup.

## 7) Delivery Phases

1. Scaffold macOS app project and shared models.
2. Implement API clients (Gemini -> Codex -> Claude) with unit tests.
3. Build polling store + tiny SwiftUI window.
4. Integrate status icon and error handling.
5. Build/install instructions + DMG packaging script.
6. End-to-end local verification on this machine.

## 8) Definition of Done

- App runs as menu bar utility.
- Polling runs every 60s.
- Each provider shows quota/reset or explicit per-provider error.
- No primary dependency on interactive CLI screen scraping.
- DMG build path documented and reproducible.
