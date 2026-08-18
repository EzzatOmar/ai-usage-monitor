# 0001 - host settings in an AppKit window

- Date: 2026-08-18
- Status: Active
- Task: [B2](../tasks/b/B2.md)
- Supersedes: `None`

## Context

The application is an `LSUIElement` menu-bar utility running with AppKit's
`.accessory` activation policy. SwiftUI's `SettingsLink` did not make the
SwiftUI `Settings` scene visible from the window-style `MenuBarExtra` in
production on macOS 26. This is a documented class of SwiftUI activation
failures for menu-bar-only applications, and content rendering tests cannot
exercise scene presentation.

## Decision

We will present settings through a main-actor AppKit window shell that lazily
creates and retains one `NSWindow`, hosts `SettingsRootView` in an
`NSHostingController`, explicitly activates the application, and orders the
window front. The settings content remains SwiftUI and shares the menu's
`MenuBarViewModel` instance.

## Architectural constraints

- `SettingsWindowPresenter` owns settings window creation, activation, reuse,
  close, and reopen behavior.
- The menu gear invokes the presenter through an injected action; it must not
  depend on `SettingsLink`, `openSettings`, private selectors, or a SwiftUI
  `Settings` scene.
- Keep the app's `.accessory`/`LSUIElement` behavior; opening settings must not
  require a persistent or temporary Dock icon.
- Keep window effects on the main actor and provider/update state in the shared
  `MenuBarViewModel`.

## Consequences

- Settings presentation is deterministic and directly integration-testable as
  an actual window lifecycle.
- The project accepts a small AppKit imperative shell and explicit window
  lifecycle management around otherwise SwiftUI content.
- Future macOS window behavior changes must be handled in the presenter rather
  than spread through menu views.

## Alternatives rejected

- SwiftUI `SettingsLink`/`openSettings`: unreliable for accessory
  `MenuBarExtra` applications and failed in production.
- Private `showSettingsWindow:` selectors: unsupported on modern macOS.
- Temporarily switching to `.regular` activation or using a hidden window:
  adds Dock-icon flicker, timing races, and unnecessary window state.
- Adding a settings-access package: unnecessary for a single retained window
  and expands the dependency surface.

## Evidence

- [B2 production report and verification](../tasks/b/B2.md)
- [Showing Settings from macOS Menu Bar Items](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Apple Feedback FB10184971](https://github.com/feedback-assistant/reports/issues/327)
