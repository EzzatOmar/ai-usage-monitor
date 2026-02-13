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

- ~~App runs as menu bar utility.~~ ✓ Completed
- ~~Polling runs every 60s.~~ ✓ Completed
- ~~Each provider shows quota/reset or explicit per-provider error.~~ ✓ Completed
- ~~No primary dependency on interactive CLI screen scraping.~~ ✓ Completed - uses direct APIs
- ~~DMG build path documented and reproducible.~~ ✓ Completed

## 9) Implementation Status (as of commit 347a59c)

All MVP features from Phase 1-6 are complete and operational:

### Completed Phases
- **Phase 1**: Scaffolded macOS SwiftPM app project + package setup ✓
- **Phase 2**: Implemented API clients for all providers with unit tests ✓
- **Phase 3**: Built polling store + compact SwiftUI menu bar UI ✓
- **Phase 4**: Integrated status icon and error handling ✓
- **Phase 5**: Added build/install docs + DMG packaging script ✓
- **Phase 6**: End-to-end local verification completed ✓

### Additional Enhancements
- **Claude auth**: Multi-source credential discovery with keychain opt-in
  - Reads from: keychain (opt-in), credential files, `CLAUDE_ACCESS_TOKEN`, or pasted setup-token
  - Graceful fallback through sources if one fails
  - UI shows detailed error messages (HTTP status + body snippet)
- **Z.AI auth & quota**: Full implementation
  - Inline key editor to paste API key
  - Fetches quota limits from `/api/monitor/usage/quota/limit`
  - Fetches weekly usage from `/api/monitor/usage/model-usage`
  - Env variable fallbacks: `ZAI_API_KEY`, `ZAI_KEY`, `ZHIPU_API_KEY`, `ZHIPUAI_API_KEY`

### Current State
App is fully functional as a menu bar utility:
- Polls every 60s across all providers concurrently
- Shows Claude, Codex, Gemini, Z.AI, and Cerebras usage data
- Handles auth errors gracefully with inline "fix" buttons
- Persisted auth via UserDefaults (no keychain required)
- Error messages now show specific failure details (HTTP codes, API responses)
- All tests passing (`swift test`)

## 10) Recent Fixes & Enhancements (commits 347a59c..f89140e)

### Bug Fixes
- **Claude utilization parsing**: API returns percentage (5.0 = 5%), not decimal (0.05). Fixed multiplier.
- **Z.AI quota parsing**: Now uses `percentage` field directly from API instead of calculating from `currentValue/usage`.
- **Claude error messages**: Shows "Run 'claude' in terminal to refresh token" when keychain token expires.

### UI Improvements
- **Weekly usage display**: Secondary window (weekly limits) now shown for Codex and other providers.
- **Quit button**: Added to menu bar for easy app termination.
- **Simplified Claude auth**: Removed setup token input - keychain only with single "Allow keychain" button.

### Provider Updates
- **Cerebras**: Added as new provider with API key authentication and rate limit header parsing.

### Auth Improvements
- **Claude keychain**: Now reads full credentials including `expiresAt`, `refreshToken`, `rateLimitTier` for better error handling.
- **Z.AI**: API key stored in UserDefaults, fetched from environment variables as fallback.
