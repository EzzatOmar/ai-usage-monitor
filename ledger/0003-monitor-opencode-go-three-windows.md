# 0003 - monitor OpenCode Go through its three-window usage API

- Date: 2026-09-17
- Status: Active
- Task: [A5](../tasks/a/A5.md)
- Supersedes: `None`

## Context

OpenCode Go enforces rolling 5-hour, weekly, and subscription-month quotas. The existing domain and stale cache support only two subscription windows. Upstream now implements a dedicated bearer-key usage endpoint.

## Decision

We will query only `GET https://opencode.ai/zen/go/v1/usage` for Go usage, decoding its server-calculated percentages and reset timestamps in a pure core. Credentials resolve from the app's saved key, `OPENCODE_GO_API_KEY`, then the `opencode-go` API entry in OpenCode's local auth file.

We will add an optional `tertiaryWindow` to `ProviderUsageResult`. For Go, primary/secondary/tertiary mean 5-hour/weekly/monthly. All three survive stale-cache fallback and render separately. Go contributes its lowest remaining percentage across these windows to the menu title; other providers retain their existing primary-window selection.

## Architectural constraints

- Never make inference calls or scrape the console to measure Go usage.
- Read local auth without mutation; removing the saved key must not delete OpenCode's credentials.
- Follow `XDG_DATA_HOME` for OpenCode's auth path, defaulting to `~/.local/share/opencode/auth.json`.
- Monthly reset timestamps come from the server; do not assume calendar-month or fixed 30-day resets.
- Do not show arbitrary response bodies or credential-bearing transport errors in UI/logs.
- Distinguish API subscription entitlement errors from generic HTTP 403/edge failures.

## Consequences

- Supports accurate three-window monitoring without paid requests or new dependencies.
- Keeps existing provider initializers and selection behavior compatible.
- Accepts dependency on an upstream endpoint whose schema may evolve; malformed/incomplete payloads fail rather than fabricating unused quota.
- Saved keys follow the existing explicit API-key UserDefaults convention; local discovered keys are never persisted by this app.

## Alternatives rejected

- Dashboard cookies/browser automation: unnecessary auth and maintenance burden now that an API exists.
- Local token/cost estimates: cannot reconstruct authoritative subscription windows.
- Encoding monthly quota as a model window: semantically wrong and hides primary/secondary UI.
- Generalizing all windows and selection rules for every provider: broader migration than this integration requires.

## Evidence

- [A5 research and verification](../tasks/a/A5.md)
- [Pinned usage route](https://github.com/anomalyco/opencode/blob/88c6c7abc7f320b6aabed2634ac0b2d6e6ecea67/packages/console/app/src/routes/zen/go/v1/usage.ts)
- [Official Go documentation](https://opencode.ai/docs/go/)
