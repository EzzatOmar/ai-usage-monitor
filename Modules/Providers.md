# Providers Module - Agent Guidelines

## Overview
Provider clients implement `ProviderClient` protocol to fetch usage data from external APIs. Each provider is a struct conforming to the protocol.

## Protocol: ProviderClient
```swift
protocol ProviderClient: Sendable {
    var providerID: ProviderID { get }
    func fetchUsage(now: Date) async -> ProviderUsageResult
}
```

## Implementation Pattern

### Required Methods
1. `fetchUsage(now:)` - Async, returns ProviderUsageResult
   - Never throws; wrap all errors in ProviderUsageResult.errorState
   - Check auth at start, return ProviderErrorState.authNeeded if missing
   - Return ProviderUsageResult with:
     - provider set to self.providerID
     - primaryWindow and secondaryWindow from API
     - accountLabel if available
     - lastUpdated set to now parameter
     - errorState nil on success, ProviderErrorState on failure
     - isStale = false

### Private Nested Types
- API response structs conforming to Codable
- Use `CodingKeys` enum for snake_case to camelCase mapping
- Keep all response types private and nested within provider client

### Auth Credential Loading
- Private static method `loadAPIKey()` / `loadCredentials()`
- Priority order: stored in AuthStore -> environment variables -> local auth files
- Trim whitespace: `trimmingCharacters(in: .whitespacesAndNewlines)`
- Return nil or throw ProviderErrorState.authNeeded

### Network Requests
- Use `try await URLSession.shared.data(for: request)`
- Build URLRequest with proper headers: Authorization, Accept, Content-Type, User-Agent
- HTTP status handling:
  - 200-299: decode response
  - 401/403: throw ProviderErrorState.tokenExpired
  - Others: throw ProviderErrorState.endpointError with status/message
- Catch and wrap errors in ProviderUsageResult

### Date Parsing
- ISO8601: `ISO8601DateFormatter` with `.withInternetDateTime, .withFractionalSeconds`
- Fallback without fractional seconds
- Unix timestamps (ms): `Date(timeIntervalSince1970: milliseconds / 1000.0)`

### Debug Extensions (#if DEBUG)
- Add static method `decodeUsageResponse(_ data: Data) throws -> ...` for testing
- Return raw usage values (utilization, percentages) for debugging
- Keep internal, only for #if DEBUG

## Error Handling Strategy
```swift
do {
    // ... fetch and parse
    return ProviderUsageResult(provider: .xxx, ..., errorState: nil, isStale: false)
} catch let error as ProviderErrorState {
    return ProviderUsageResult(provider: .xxx, ..., errorState: error, isStale: false)
} catch {
    return ProviderUsageResult(provider: .xxx, ..., errorState: .networkError(error.localizedDescription), isStale: false)
}
```

## Adding New Provider
1. Create `XxxClient: ProviderClient` struct
2. Set `let providerID: ProviderID = .xxx`
3. Implement `fetchUsage(now:)` following pattern
4. Add private nested types for API responses
5. Implement auth loading method(s)
6. Implement network request method(s)
7. Add to UsageStore.clients array in AIUsageMonitorApp.swift
8. Add to ForEach loop in MenuBarView.swift

## Provider-Specific Notes

### ClaudeClient
- Uses OAuth token from `CLAUDE_CODE_OAUTH_TOKEN`, legacy `CLAUDE_ACCESS_TOKEN`,
  credential files, or the macOS keychain
- Keychain integration optional (user opt-in)
- Multiple credential sources tried in sequence
- Keychain authentication UI is allowed only after the explicit UI action
- Keychain credentials are cached in memory until expiry or HTTP 401/403
- Expired credentials require `claude auth login`; the app does not launch Claude
  or make an inference request to force a refresh

### CodexClient
- Token refresh logic (8-day expiry threshold)
- Reads ~/.codex/auth.json and config.toml
- Custom base URL support via config
- Plan type, primary擔primary/secondary windows

### ZAIClient
- Multiple env var names supported
- Two endpoints: quota/limit and weekly usage
- Weekly usage is async secondary call
- Primary/secondary windows identified by type string

### GemniClient
- Uses ~/.gemini/settings.json and oauth_creds.json
- OAuth token refresh if needed

### CerebrasClient
- API key only (stored, env, or pasted)
- Single usage endpoint

### QwenCloudClient

#### Blocked: Token Plan Individual quota

QwenCloud Token Plan Individual monitoring is blocked until QwenCloud provides
an API-key-authenticated usage endpoint.

- `sk-sp-*` keys work with the Token Plan model endpoint and can be validated
  without inference through `GET /compatible-mode/v1/models`.
- The model endpoint exposes no quota fields or quota/rate-limit headers.
- Tested `/usage`, `/quota`, dashboard usage, and personal usage candidates
  return HTTP 404.
- The console's internal
  `zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage` gateway returns
  `ConsoleNeedLogin` when authenticated with the API key as Bearer,
  `X-DashScope-API-Key`, `api_key`, or `sec_token`.
- Qwen Code records token counts from inference response `usage` fields into
  local history. It does not fetch 5-hour or 7-day subscription percentages;
  it only recognizes quota exhaustion after receiving a provider 429.
- Local token counts cannot reliably reconstruct Credits because consumption
  varies by model, cache usage, thinking, and tool calls.

Do not restore WebKit sign-in, scrape the console, or make a paid inference
request to estimate quota. Revisit this provider when QwenCloud documents or
ships a read-only API-key endpoint returning current 5-hour and 7-day usage and
reset timestamps.

### CursorClient

- Supports signed-in Cursor accounts without an Admin API key.
- `CursorSessionReader` reads `cursorAuth/accessToken` from Cursor or Cursor
  Nightly's local `state.vscdb` in read-only mode. Cursor Agent `auth.json`
  files and `CURSOR_SESSION_TOKEN` are fallbacks.
- Decodes the session JWT's `sub` claim and constructs the dashboard's
  `WorkosCursorSessionToken=<user>%3A%3A<jwt>` cookie in memory.
- Calls the read-only
  `POST https://cursor.com/api/dashboard/get-current-period-usage` dashboard
  action, with `GET https://cursor.com/api/usage-summary` as a fallback.
- Displays the monthly metered API pool as primary and Auto/Composer as
  secondary, using the server's billing-cycle end as the reset time.
- The token is never persisted by AI Usage Monitor, refreshed, or logged, and
  no inference endpoint is called.
- These dashboard endpoints are undocumented and isolated in
  `CursorDashboardTransport` so schema or route changes can be replaced.
