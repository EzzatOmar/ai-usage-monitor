# Domain Module - Agent Guidelines

## Overview
Contains core domain models and types used throughout the application. All types are Sendable and most are Equatable.

## Types

### ProviderID (enum)
- CaseIterable enum for all supported AI providers
- RawValue is String (provider name)
- Cases: claude, codex, gemini, zai, cerebras
- Used for iteration in UI and lookup in results

### ProviderErrorState (enum)
- Error states for provider operations
- Cases: authNeeded, tokenExpired, endpointError(String), parseError(String), networkError(String)
- Conforms to Error, Sendable, Equatable
- Computed properties: badgeText (UI display), detailText (tooltip/explanation)

### UsageWindow (struct)
- Contains usage statistics for a time window
- Properties: usedPercent, resetAt, windowSeconds
- Computed: remainingPercent
- Equatable, Sendable

### ProviderUsageResult (struct)
- Result of a fetchUsage() call from a provider client
- Properties: provider, primaryWindow, secondaryWindow, accountLabel, lastUpdated, errorState, isStale
- Equatable, Sendable
- Never thrown; always returned

### UsageSnapshot (struct)
- Complete application state at a point in time
- Properties: results (array), lastUpdated, isRefreshing
- Static member: empty
- Computed: minimumRemainingPercent across all providers
- Equatable, Sendable

## Formatting Rules
- Use `String` rawValue for ProviderID
- Optional Date fields nil when unknown
- Percent values always 0-100 range (enforce in computed properties)
- Error states with String payload use description/localizedDescription
- All domain types use computed properties, not stored derived values

## When to Extend
- Adding new provider: add case to ProviderID
- New error state: add case to ProviderErrorState with appropriate badge/detail text
- Additional window types: add tertiaryWindow to UsageWindow/ProviderUsageResult