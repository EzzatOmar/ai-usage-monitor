# Core Module - Agent Guidelines

## Overview
Core application logic including state management, polling, and persistence. Main components: UsageStore and AuthStore.

## UsageStore (actor)

### Purpose
Thread-safe polling engine that coordinates provider clients and publishes updates.

### Key Properties
- `clients: [any ProviderClient]` - All registered provider clients
- `pollIntervalSeconds: UInt64` - Default 60 seconds
- `snapshot: UsageSnapshot` - Current application state
- `lastGood: [ProviderID: ProviderUsageResult]` - Cache of last successful results
- `continuations: [UUID: AsyncStream.Continuation]` - Active subscribers

### Public API
- `init(clients:pollIntervalSeconds:)` - Initialize with clients and interval
- `start()`, `stop()` - Control poll loop
- `refreshNow()` - Immediate refresh from UI
- `updates() -> AsyncStream<UsageSnapshot>` - Subscribe to state changes

### Implementation Details

#### Polling Loop
1. Calls `refresh()` immediately on start
2. Sleeps for `pollIntervalSeconds * 1_000_000_000` nanoseconds
3. Repeats until cancelled

#### Parallel Fetching
```swift
await withTaskGroup(of: ProviderUsageResult.self) { group in
    for client in self.clients {
        group.addTask { await client.fetchUsage(now: now) }
    }
    for await result in group {
        fetched.append(result)
    }
}
```

#### Stale Result Handling
- If fetch succeeds: update `lastGood[provider]` and mark `isStale = false`
- If fetch fails: use `lastGood[provider]` with `isStale = true` and new errorState
- Falls back to current result if no cached

#### Publishing
- Updates continuations for all subscribers
- Calls `continuation.yield(snapshot)` on each state change

## AuthStore (enum)

### Purpose
Persistence layer for authentication credentials using UserDefaults and Keychain.

### UserDefaults Keys
- `aiUsageMonitor.zaiApiKey`
- `aiUsageMonitor.claudeSetupToken`
- `aiUsageMonitor.claudeUseKeychain` (Bool)
- `aiUsageMonitor.cerebrasApiKey`

### API Pattern
Each credential has three methods:
```swift
static func load<Credential>() -> Credential?  // nil if missing/empty
static func save<Credential>(_ value: Credential) -> Bool
static func clear<Credential>()
```

### Implementation Details
- Always trim: `trimmingCharacters(in: .whitespacesAndNewlines)`
- Return nil on empty/missing values
- Keychain access only after explicit opt-in via `isClaudeKeychainEnabled()`

### Keychain Integration (Claude)
- Check `isClaudeKeychainEnabled()` before reading
- Service: "Claude Code-credentials"
- Query with kSecClassGenericPassword and kSecReturnData
- Parse JSON for accessToken (nested in claudeAiOauth or direct)

## Infrastructure Utilities

### LocalPaths (enum)
Static path resolution methods:
- `codexAuthPath()` and `codexConfigPath()` - Respects CODEX_HOME env var
- `claudeCredentialsPath()`, `geminiSettingsPath()`, `geminiOAuthPath()`
- Uses `FileManager.default.homeDirectoryForCurrentUser`

### JSONFile (enum)
- `readDictionary(at:) -> [String: Any]` - Reads JSON data as dictionary
- Throws CocoaError on failure

### Redaction (enum)
- `sanitize(_ text: String)` - Redacts Bearer tokens from logs
- Regex pattern: `(?i)(bearer\s+)[a-z0-9\-\._~\+\/]+=*`

### RelativeTimeFormatter (enum)
Static formatters:
- `resetText(_ date: Date?) -> String` - "Resets in Xh Ym" or "Resets soon"
- `lastUpdatedText(_ date: Date?) -> String` - "Xh Ym ago" or "Never"
- Uses DateComponentsFormatter with .abbreviated style

## Concurrency Patterns

### Actor Isolation
- UsageStore is an actor, all mutable state isolated
- Methods can be called from outside with await
- Internal mutable state accessed without await

### AsyncStream Pattern
```swift
private var continuations: [UUID: AsyncStream<UsageSnapshot>.Continuation] = [:]

func updates() -> AsyncStream<UsageSnapshot> {
    AsyncStream { continuation in
        let id = UUID()
        self.continuations[id] = continuation
        continuation.yield(self.snapshot)
        continuation.onTermination = { _ in
            Task { await self?.removeContinuation(id: id) }
        }
    }
}
```

### Task Lifecycle
- Poll task stored in weak reference
- Cancelled on deinit or explicit stop()
- Use `Task.isCancelled` in loops