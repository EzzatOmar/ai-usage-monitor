# 0005 - explicitly size the menu window

- Date: 2026-09-18
- Status: Active
- Task: [B4](../tasks/b/B4.md)
- Supersedes: `None`

## Context

The user reported retained menu-window height after disabling providers despite v0.1.22's `.fixedSize` modifier. That modifier establishes SwiftUI's ideal content size but does not guarantee that the native MenuBarExtra host discards its previous frame. Tests using automatic NSHostingController size constraints did not exercise that failure boundary.

## Decision

We will keep SwiftUI MenuBarExtra but explicitly synchronize its native window to the menu's measured ideal size through `MenuWindowSizingBridge`, an AppKit imperative shell attached as a background to `MenuBarRootView`.

## Architectural constraints

- Measure after fixed-width, ideal-height layout; never derive height from provider counts or duplicate row-layout rules.
- Resize only the bridge view's attached window using public AppKit APIs. Do not search global windows, depend on private SwiftUI class names, or touch Settings geometry.
- Defer and coalesce resize work until after layout; use the latest measurement and skip unchanged/invalid sizes to avoid feedback loops.
- Preserve the top edge when resizing; reapply on native key/resize events so cached-frame restoration cannot leave surplus space.
- Test actual native frames with automatic hosting sizing disabled, and gate releases on a real MenuBarExtra toggle/reopen smoke test.

## Consequences

- Provider/account toggles and changing quota/error details resize the outer window, not just its contents.
- A small AppKit bridge and notification lifecycle must be maintained alongside the SwiftUI layout.
- Settings ownership remains unchanged under decision 0001.

## Alternatives rejected

- `.fixedSize` alone: previous release did not resolve the user's report and fails the retained-frame regression.
- Recreate the scene with `.id` after each toggle: disrupts transient state and still delegates window geometry to SwiftUI.
- Replace MenuBarExtra with a custom status item/popover: unnecessarily replaces working menu presentation and event behavior.

## Evidence

- [B4](../tasks/b/B4.md)
- [Native-window tests](../Tests/MenuWindowSizingTests.swift)
- [Real-menu smoke test](../Scripts/test_menu_window_sizing.sh)
