# Testing Module - Agent Guidelines

## Overview
XCTest-based tests for AIUsageMonitor. Tests use stub clients to isolate units under test.

## Test Structure

### Test File Locations
- `Tests/UsageStoreTests.swift` - UsageStore integration tests
- `Tests/ProviderDecodingTests.swift` - API response decoding tests

### Test Pattern
```swift
import XCTest
@testable import AIUsageMonitor

final class XxxTests: XCTestCase {
    func test_something() async throws {
        // Arrange
        // Act
        // Assert
    }
}
```

## Stub Client Pattern

Create stub providers for isolated testing:

```swift
private struct StubClient: ProviderClient {
    let providerID: ProviderID
    let response: ProviderUsageResult

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        self.response
    }
}
```

### Usage Example
```swift
let store = UsageStore(clients: [
    StubClient(providerID: .claude, response: ProviderUsageResult(...)),
    StubClient(providerID: .codex, response: ProviderUsageResult(...))
], pollIntervalSeconds: 3600)
```

## Common Test Patterns

### AsyncStream Testing
```swift
let stream = await store.updates()
var latest: UsageSnapshot?
for await value in stream {
   oc latest = value
    break  // Capture first value only
}
XCTAssertNotNil(latest)
```

### Refresh Testing
```swift
await store.refreshNow()
let snapshot = (await store.updates()).makeAsyncIterator().next()
// Assert snapshot state
```

### Error State Testing
```swift
let failingClient = StubClient(
    providerID: .xxx,
    response: ProviderUsageResult(
        provider: .xxx,
        primaryWindow: nil,
        secondaryWindow: nil,
        accountLabel: nil,
        lastUpdated: now,
        errorState:alan .authNeeded,
        isStale: false
    )
)
```

## Running Tests

### All Tests
```bash
swift test
```

### Single Test
```bash
swift test --filter test_methodName
swift test --filter test_className.test_methodName
```

### Test Verbosity
```bash
swift test --verbose
```

## Test Coverage Areas

### UsageStore Tests
- Publishes results for all providers
- Parallel fetching with multiple clients
- Stale result fallback when providers fail
- Multiple subscribers receive updates
- Polling behavior (start/stop/refresh)

### Provider Decoding Tests
- ISO8601 date parsing
- Unix timestamp conversion
- Snake_case to camelCase mapping
- Optional field handling
- Error states on invalid payloads

### Domain Tests (minimal)
- ProviderID cases enumeration
- UsageWindow percentage calculations
- ProviderErrorState badge/detail text

## Test Data Helpers

### Creating Test Dates
```swift
let now = Date()
let future = Date().addingTimeInterval(3600)
let past = Date().addingTimeInterval(-3600)
```

### Creating Test Windows
```swift
UsageWindow(
    usedPercent: 75.5,
    resetAt: future,
    windowSeconds: 86400
)
```

### Creating Test Results
```swift
ProviderUsageResult(
    provider: .claude,
    primaryWindow: testWindow,
    secondaryWindow: nil,
    accountLabel: "Test",
    lastUpdated: now,
    errorState: nil,
    isStale: false
)
```

## Testing Guidelines

### Arrange-Act-Assert
```swift
func test_calculatesRemainingPercent() {
    // Arrange
    let window = UsageWindow(usedPercent: 75, resetAt: nil, windowSeconds: nil)

    // Act
    let remaining = window.remainingPercent

    // Assert
    XCTAssertEqual(remaining, 25)
}
```

### Async Testing
- Use `async throws` for async test methods
- Await async operations
- Use `XCTAssertNoThrow` for async error checking

### Mocking
- Prefer stub clients over mocks
- Stub clients conform to `ProviderClient`
- Return predictable, testable values

### Test Isolation
- Each test should be independent
- Use fresh instances per test
- Avoid shared mutable state

## Debug Tests with #if DEBUG Extensions

Use debug extensions to parse test data:

```swift
#if DEBUG
let utilization = try? ClaudeClient.decodeUsageResponse(testData)
XCTAssertNotNil(utilization)
#endif
```

## Common Assertions

```swift
XCTAssertEqual(value, expected)
XCTAssertNotNil(value)
XCTAssertTrue(condition)
XCTAssertFalse(condition)
XCTAssertNoThrow(try expression)
XCTAssertThrowsError(try expression) { error in
    // Assert error properties
}
```

## When to Add Tests

- New provider client: Add decoding tests for API responses
- New domain type: Add calculation/conversion tests
- New UsageStore behavior: Add integration tests
- Bug fix: Add regression test for the bug