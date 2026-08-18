# UI Module - Agent Guidelines

## Overview

SwiftUI views for a macOS `MenuBarExtra` app. A shared `@MainActor`
`MenuBarViewModel` drives the compact usage panel and settings content. An
AppKit shell presents the settings window reliably from the accessory app.

## View hierarchy

- `MenuBarRootView` — routine usage for activated providers only.
- `ProviderRow` — quota, account, stale state, and errors; no configuration.
- `SettingsRootView` — all provider activation, credentials, and update actions.
- `ProviderSettingsRow` — provider toggle plus applicable credential action.
- `APIKeySettingsEditor` — reusable secure inline key editor.
- `UpdateSettingsSection` — manual update check and download/install status.
- `SettingsWindowPresenter` — main-actor AppKit window creation, activation,
  reuse, close, and reopen shell.

`AIUsageMonitorApp` injects the presenter action into the menu:

```swift
MenuBarExtra(...) {
    MenuBarRootView(
        model: model,
        onOpenSettings: { settingsWindowPresenter.showSettings() }
    )
}
.menuBarExtraStyle(.window)
```

The presenter hosts `SettingsRootView` in one retained `NSWindow` through
`NSHostingController`. The menu and hosted settings view must receive the same
model instance. Do not replace this with `SettingsLink`, `openSettings`, or a
SwiftUI `Settings` scene; those paths are unreliable for this
`.accessory`/`LSUIElement` menu bar app. See ledger decision 0001.

## MenuBarViewModel

`MenuBarViewModel` is `@MainActor` and `@Observable`. Views use `@Bindable`.
It owns:

- the latest `UsageSnapshot` and provider-enabled dictionary;
- credential editor inputs and visibility state;
- Claude keychain authorization state;
- updater state and actions;
- `activeProviders`, which delegates to the pure `ProviderSelection` rules.

Provider activation persists through `AuthStore`. Enabling a provider triggers
an immediate refresh. The menu title's minimum quota must be calculated only
from activated providers.

## Main usage menu

Keep the menu compact and monitoring-focused:

```swift
VStack(alignment: .leading, spacing: 10) {
    Header
    ForEach(model.activeProviders) { ProviderRow(...) }
    Divider()
    Footer // updated time, GitHub, Settings, refresh icon, Quit
}
.padding(12)
.frame(width: 340)
```

Rules:

- Never render disabled providers, activation toggles, key editors, credential
  actions, or manual update checking in the main menu.
- Show an empty state that directs users to Settings when no provider is active.
- Refresh is icon-only, has an accessibility label/help string, and shares the
  footer row with Quit.
- Provider errors may explain that authorization is available in Settings.

## Settings

Settings lists `ProviderID.allCases` so disabled providers remain discoverable.
Each row has a persisted toggle. Configuration controls are provider-specific:

- Claude — explicit keychain authorization.
- Z.AI, Cerebras, Kimi, Minimax, QwenCloud — set/remove API key and secure editor.
- Codex, Gemini, Cursor — local-login/session description; no key editor.

Keep API inputs in `SecureField`, trim on save through view-model actions, and
show the existing QwenCloud validation error inline. Update controls belong
below the provider list and preserve all `UpdateStatus` states.

## SwiftUI conventions

- Use `@Bindable` with observable view models.
- Keep app state and actions in the view model, not local view state.
- Local `@State` is appropriate only for ephemeral presentation such as an
  error-details popover.
- Use `.controlSize(.small)` for compact controls.
- Use secondary/tertiary styles for quota metadata and orange for stale or
  caution text.
- Give every icon-only action an accessibility label and help text.
- Keep settings window effects in `SettingsWindowPresenter`; views invoke its
  injected action and do not manage AppKit windows.

## Updating the UI

When adding a provider:

1. Add it to `ProviderID.allCases` through the enum case.
2. Add its settings description and applicable setup controls.
3. Add credential editor state/actions to `MenuBarViewModel` if needed.
4. Keep `ProviderRow` focused on usage and errors.
5. Add selection tests when activation behavior changes.
