# AI Usage Monitor - Agent Guidelines

## Build / Test Commands

```bash
swift build
swift test
swift test --filter <testName>
swift run AIUsageMonitor
./Scripts/build_dmg.sh
```

## Project Overview

Native macOS menu bar app (Swift 5.10, macOS 14+) monitoring API quota for AI providers. Polls every 60s via direct APIs, reuses local auth (~/.claude, ~/.codex, ~/.gemini). See Modules/ directory for detailed guidelines.

## Module Structure

**Modules/Domain.md** - Core types (ProviderID, ProviderErrorState, UsageWindow, ProviderUsageResult, UsageSnapshot)
**Modules/Providers.md** - Provider clients implementing ProviderClient protocol
**Modules/Core.md** - UsageStore (actor), AuthStore (persistence), utilities
**Modules/UI.md** - SwiftUI views with MenuBarViewModel (MVVM pattern)
**Modules/Testing.md** - XCTest tests, stub client pattern

## Quick Reference

### Provider Client Pattern
```swift
struct XxxClient: ProviderClient {
    let providerID: ProviderID = .xxx
    func fetchUsage(now: Date) async -> ProviderUsageResult {
        do {
            let usage = try await Self.fetchUsage()
            return ProviderUsageResult(provider: .xxx, ..., errorState: nil, isStale: false)
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(provider: .xxx, ..., errorState: error, isStale: false)
        } catch {
            return ProviderUsageResult(provider: .xxx, ..., errorState: .networkError(...), isStale: false)
        }
    }
}
```

### Error Handling
- Use ProviderErrorState: authNeeded, tokenExpired (401/403), endpointError, parseError, networkError
- Provider clients never throw to callers; wrap in ProviderUsageResult
- Stale results: UsageStore caches lastGood, returns with isStale=true on failure

### Async/Concurrency
- Providers: async/await with URLSession
- State: actor UsageStore for thread-safety
- UI: @MainActor with @Observable
- Parallel: withTaskGroup for concurrent provider fetching

### Date Parsing
- ISO8601: ISO8601DateFormatter with .withInternetDateTime, .withFractionalSeconds
- Fallback: .withInternetDateTime (no fractional seconds)
- Unix: Date(timeIntervalSince1970: seconds/1000.0)

### Authentication Priorities
1. Stored in AuthStore (UserDefaults/Keychain)
2. Environment variables
3. Local auth files (~/.claude, ~/.codex, ~/.gemini)
- Always trim: .trimmingCharacters(in: .whitespacesAndNewlines)
- Return nil on empty/missing

### Testing Pattern
```swift
private struct StubClient: ProviderClient {
    let providerID: ProviderID
    let response: ProviderUsageResult
    func fetchUsage(now: Date) async -> ProviderUsageResult { self.response }
}
let store = UsageStore(clients: [StubClient(...)])
```

### Adding New Provider
1. Add case to ProviderID enum (Domain.swift)
2. Create XxxClient conforming to ProviderClient (pattern above)
3. Implement fetchUsage with private nested response types
4. Add to UsageStore.clients (AIUsageMonitorApp.swift)
5. Add UI in ProviderRow (MenuBarView.swift)

### Security
- Never log tokens/keys; use Redaction.sanitize() for bearer tokens
- Keychain only via explicit opt-in (Claude)
- Validate: check exists and not empty before use

### Environment Variables
- Claude: CLAUDE_ACCESS_TOKEN
- Codex: CODEX_HOME (custom path)
- Z.AI: ZAI_API_KEY, ZAI_KEY, ZHIPU_API_KEY, ZHIPUAI_API_KEY
- Access: ProcessInfo.processInfo.environment

### Debug (#if DEBUG)
- Add static decodeUsageResponse() methods for testing
- Keep internal, for manual data parsing only

### SwiftUI Conventions
- @Bindable with @Observable view models
- @MainActor for all ViewModel mutations
- ForEach(ProviderID.allCases, id: \.self) for iteration
- SecureField for credential inputs
- .controlSize(.small), .frame(width: 340), .padding(12)
- Conditional views: if model.show*Editor

### File Paths
- Home: FileManager.default.homeDirectoryForCurrentUser
- Build via LocalPaths enum static methods
- URL.appendingPathComponent() for path construction