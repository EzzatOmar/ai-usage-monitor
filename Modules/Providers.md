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
- Uses OAuth token from ~/.claude, env vars, or pasted setup token
- Keychain integration optional (user opt-in)
- Multiple credential sources tried in sequence
- Special handling for setup-token 401 rejection

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