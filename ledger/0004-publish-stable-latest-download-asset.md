# 0004 - publish a stable latest-download asset

- Date: 2026-09-18
- Status: Active
- Task: [B3](../tasks/b/B3.md)
- Supersedes: `None`

## Context

The GitHub Pages website points to GitHub's latest-release download URL for `AIUsageMonitor.dmg`, but releases previously published only versioned filenames. The link therefore failed despite a current release being available. Website deployment and release publication run independently on pushes to main.

## Decision

We will publish both `AIUsageMonitor-<version>.dmg` and a byte-identical `AIUsageMonitor.dmg` in every release. The static website continues to use `/releases/latest/download/AIUsageMonitor.dmg`; GitHub resolves the latest release when the user clicks.

## Architectural constraints

- `Scripts/build_dmg.sh` creates both names from the same packaged image.
- The release workflow verifies equality and uploads both assets in the same release creation command.
- Keep the versioned asset for existing consumers and explicit version downloads.
- Do not embed a release version in the website's download URL or require a site rebuild for each release.

## Consequences

- Website downloads automatically track published releases without browser API requests or deploy-order coupling.
- Each release stores a duplicate DMG; the small storage cost avoids extra hosting or redirect services.
- Older releases without the alias cannot serve the stable URL if manually designated latest.

## Alternatives rejected

- Generate a versioned URL during website builds: couples deployment to release timing and can point to an unpublished asset.
- Fetch the GitHub releases API in the browser: adds JavaScript, rate limits, and runtime failure modes to a static download link.
- Link only to the releases page: reliable but removes the existing direct-download behavior.

## Evidence

- [B3](../tasks/b/B3.md)
- [Release workflow](../.github/workflows/release.yml)
- [DMG packaging](../Scripts/build_dmg.sh)
