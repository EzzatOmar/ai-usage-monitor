# UI Module - Agent Guidelines

## Overview
SwiftUI views for the macOS MenuBarExtra app. MVVM pattern with MenuBarViewModel driving MenuBarRootView.

## Architecture

### MenuBarViewModel (@Observable final class)
- `@MainActor` - All mutations on main thread
- `@Bindable` in views for SwiftUI observation
- Contains UI state and business logic
- Subscribes to UsageStore updates via `updates()` stream

### View Hierarchy
- `MenuBarRootView` - Main panel container
- `ProviderRow` - Individual provider display row
- Editor modals (if show*Editor flags set)

## MenuBarViewModel State

### Usage Data
- `snapshot: UsageSnapshot` - Current provider results
- Updated via `store.updates()` stream

### Editor State (one per provider)
- `claudeSetupTokenInput: String` + `showClaudeTokenEditor: Bool`
- `zaiAPIKeyInput: String` + `showZAIKeyEditor: Bool`
- `cerebrasAPIKeyInput: String` + `showCerebrasKeyEditor: Bool`

### Toggles
- `claudeKeychainEnabled: Bool` - Claude keychain opt-in

### Actions (all @MainActor)
- `refreshNow()` - Trigger immediate store refresh
- `openClaudeTokenEditor()` - Load token into input field, show editor
- `saveClaudeToken()` - Trim, save/empty, hide editor, refresh
- `cancelClaudeTokenEditor()` - Hide editor without saving
- `enableClaudeKeychainAccess()` - Set flag, refresh
- `openZAIKeyEditor()` / `saveZAIKey()` / `cancelZAIKeyEditor()`
- `openCerebrasKeyEditor()` / `saveCerebrasKey()` / `cancelCerebrasKeyEditor()`

### Computed Properties
- `menuBarTitle: String` - "AI XX%" or "AI --"
- `menuBarSystemImage` - "exclamationmark.triangle" on error, "chart.pie" normal

## MenuBarRootView

### Structure
```swift
VStack(alignment: .leading, spacing: 10) {
    Header (title + refresh indicator)
    ForEach(ProviderID.allCases) { provider ->
        ProviderRow(...)
    }
    Divider()

    // Conditionally shown editors
    if showClaudeTokenEditor { ... }
    if showZAIKeyEditor { ... }
    if showCerebrasKeyEditor { ... }

    Footer (last updated + refresh button)
}
.padding(12)
.frame(width: 340)
```

### Key Patterns
- `@Bindable var model` for @Observable
- `ForEach(ProviderID.allCases, id: \.self)` iteration
- Look up result via `snapshot.results.first(where: { $0.provider == provider })`
- Conditional views with `if model.show*Editor`
- `ProgressView().controlSize(.small)` during refresh
- SecureField for credential inputs
- HStack with Cancel (leading) / Save (trailing) buttons

## ProviderRow

### Inputs
- `result: ProviderUsageResult?` - Provider's latest result (nil if pending)
- `provider: ProviderID` - Provider identifier
- `onClaudeSetup`, `onClaudeKeychainAccess`, `onZAISetup`, `onCerebrasSetup` closures

### Layout
```
HStack(alignment: .firstTextBaseline) {
    VStack {
        Provider name
        Primary usage text (percent + reset time) or "No quota data"
        Optional error detail text (lineLimit: 2)
        "Using last known data" if stale (orange)
    }

    Spacer()

    // Shows when errorState != nil
    VStack(alignment: .trailing) {
        Badge text (Auth needed, API error, etc.)

        // Provider-specific action buttons
        Claude: "Paste token" + "Allow keychain" (if not enabled)
        Z.AI: "Set key"
        Cerebras: "Set key"
    }
}
```

### Styling
- Badge: `.background(Color.red.opacity(0.12), in: Capsule())`
- Stale text: `.foregroundStyle(.orange)`
- Action buttons: `.font(.caption2)`
- Error messages: `.lineLimit(2)` with `.foregroundStyle(.secondary)`

## Editor Modals Pattern

Each editor follows this pattern:
```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Title")
        .font(.caption.weight(.semibold))
    Text("Instruction")
        .font(.caption2)
        .foregroundStyle(.secondary)
    SecureField("placeholder", text: $model.input)
        .textFieldStyle(.roundedBorder)
    HStack {
        Button("Cancel") { model.cancel() }
        Spacer()
        Button("Save") { model.save() }
    }
}
```

## SwiftUI Best Practices

### Observation
- Use `@Bindable` with `@Observable` view models
- Avoid @State in views for app state
- Keep state in ViewModel, not Views

### Layout
- Use fixed width for main panel: `.frame(width: 340)`
- Stack spacing: 10 for main, 6 for editors
- Control size: `.controlSize(.small)` for compact UI
- Padding: `.padding(12)` for main container

### Conditional Views
- One boolean per modal (e.g., `showClaudeTokenEditor`)
- Check error state before showing action buttons
- Only show applicable actions per provider

### Colors
- Error badges: `Color.red.opacity(0.12)` background
- Stale/warning: `.foregroundStyle(.orange)`
- Secondary text: `.foregroundStyle(.secondary)`
- Standard SwiftUI colors for everything else

### Accessibility
- All buttons have clear labels
- Error messages are truncated but meaningful
- Icons use system SF Symbols

## Updating UI Checklist

When adding new provider:
1. `ProviderID.allCases` iteration handles display automatically
2. Add provider-specific action buttons in `ProviderRow`
3. Add editor modal and input state to `MenuBarViewModel`
4. Add conditional editor view in `MenuBarRootView`
5. Add action closures to `ProviderRow` initializer

## MenuBarExtra Integration

Used in `AIUsageMonitorApp.swift`:
```swift
MenuBarExtra("AI", systemImage: model.menuBarSystemImage) {
    MenuBarRootView(model: model)
} label: {
    Text(model.menuBarTitle)
}
```