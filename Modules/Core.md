# Core Module - Agent Guidelines

## Overview
Core application logic including state management, polling, and persistence. Main components: UsageStore and AuthStore.

## UsageStore (actor)

### Purpose
Thread-safe polling engine that coordinates provider clients and publishes updates.

### Key Properties
- `clients: [any ProviderClient]` - Static single-account provider clients
- `dynamicClients` - Reloads enabled named OpenAI account clients each refresh
- `pollIntervalSeconds: UInt64` - Default 5 minutes (300 seconds)
- `snapshot: UsageSnapshot` - Current application state
- `lastGood: [ProviderClientID: ProviderUsageResult]` - Per-provider/account cache of last successful results
- `continuations: [UUID: AsyncStream.Continuation]` - Active subscribers

### Public API
- `init(clients:pollIntervalSeconds:)` - Initialize with clients and interval
- `start()`, `stop()` - Control poll loop
- `refreshNow()` - Immediate refresh from UI
- `authorizeCredentials(for:)` - Explicit provider credential authorization from UI
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
- If fetch succeeds: update `lastGood[result.id]` and mark `isStale = false`
- If fetch fails: use `lastGood[result.id]` with `isStale = true` and new errorState
- Falls back to current result if no cached

#### Publishing
- Updates continuations for all subscribers
- Calls `continuation.yield(snapshot)` on each state change

## OpenAI account persistence

### OpenAIAccountStore

- Persists account ID, display name, enabled state, and storage kind only.
- Always returns one fixed, non-removable default account using the normal Codex path.
- Derives additional auth directories from validated UUIDs under Application Support.
- Never stores OAuth credentials in UserDefaults.

### OpenAIAuthFileStore

- Reads Codex-compatible `auth.json` credentials.
- Writes managed directories as mode 0700 and auth files as mode 0600.
- Atomically persists rotated OAuth tokens and rejects account-identity changes.

## AuthStore (enum)

### Purpose
Persistence layer for authentication credentials using UserDefaults and Keychain.

### UserDefaults Keys
- `aiUsageMonitor.zaiApiKey`
- `aiUsageMonitor.claudeSetupToken`
- `aiUsageMonitor.claudeUseKeychain` (Bool)
- `aiUsageMonitor.cerebrasApiKey`
- `aiUsageMonitor.qwenCloudApiKey`

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
- Scheduled and ordinary manual refreshes disable authentication UI
- Only an explicit provider authorization refresh permits the macOS prompt
- Approved credentials are cached in memory for the current app session
- Parse JSON for accessToken (nested in claudeAiOauth or direct)

## Infrastructure Utilities

### LocalPaths (enum)
Static path resolution methods:
- `codexHomeURL()`, `codexAuthPath()`, and `codexConfigPath()` - Respect `CODEX_HOME`
- Managed OpenAI account paths come from `OpenAIAccountProfile`, not environment variables
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
