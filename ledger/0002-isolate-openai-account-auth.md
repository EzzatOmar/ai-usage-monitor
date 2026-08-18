# 0002 - isolate OpenAI account identities and auth

- Date: 2026-08-18
- Status: Active
- Task: [A3](../tasks/a/A3.md)
- Supersedes: `None`

## Context

OpenAI/Codex was previously modeled as one provider result with several auth
sources used only as fallbacks. Supporting concurrent named accounts requires
stable result/cache identity and isolated rotating OAuth credentials. The first
account must remain compatible with the user's normal Codex CLI path, while
additional accounts must not overwrite that login or each other.

## Decision

We will model every OpenAI account as a stable `ProviderClientID` under the
Codex provider. One non-removable default profile resolves `$CODEX_HOME` or
`~/.codex`; every additional profile has a UUID and an isolated directory under
`~/Library/Application Support/AIUsageMonitor/OpenAIAccounts/`. Account metadata
contains only ID, display name, enabled state, and storage kind. Managed OAuth
credentials are stored only as mode-0600 `auth.json` files in mode-0700 account
directories.

AI Usage Monitor will perform user-triggered OpenAI authorization-code + PKCE
login itself, using the official Codex OAuth client and registered localhost
callback ports. It will persist rotated refresh credentials atomically. A
permanent refresh or authorization failure becomes UI state requiring an
explicit Login again action; background polling never starts browser login.

## Architectural constraints

- Multiple account identity applies only to `ProviderID.codex`; other providers remain keyed solely by provider.
- `UsageStore` results and stale cache must use `ProviderClientID`, never `ProviderID` alone.
- The default account's auth/config paths are resolved through `LocalPaths`; its files are never migrated into managed storage.
- Additional account paths are derived from validated UUIDs, never display names or user-provided paths.
- Never persist OAuth tokens in UserDefaults, task files, logs, or account metadata.
- Login is interactive and explicit; refresh is noninteractive and must persist token rotation before later polls.
- Account mismatch, expired/reused/revoked refresh, or repeated 401/403 must require re-login rather than silently switching accounts.

## Consequences

- Named OpenAI accounts can coexist and be enabled, cached, refreshed, removed, and displayed independently.
- The app owns a localhost OAuth callback and secure file lifecycle, increasing authentication code and testing responsibility.
- OpenAI changes to the Codex OAuth client, scopes, callback allow-list, or token schema may require a coordinated update.

## Alternatives rejected

- Multiple `CODEX_HOME` environment variables: a process has only one value and cannot represent simultaneous accounts.
- Invoking an installed `codex login`: Codex may be absent or broken and would make app authentication depend on an external executable/version.
- Copying default credentials: risks refresh-token races and breaks the required default-path ownership.
- Storing all accounts in one auth file or UserDefaults: permits overwrite/cross-account leakage and weakens credential permissions.
- Automatic login after auth failure: background browser prompts are intrusive and violate explicit-interaction rules.

## Evidence

- [A3 account-aware usage task](../tasks/a/A3.md)
- [A4 managed OAuth lifecycle task](../tasks/a/A4.md)
- [Official Codex authentication source](https://github.com/openai/codex/tree/main/codex-rs/login)
