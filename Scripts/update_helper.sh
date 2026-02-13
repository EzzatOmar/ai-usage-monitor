#!/usr/bin/env bash
set -euo pipefail

# Usage: update_helper.sh <PID> <STAGED_APP_PATH> <INSTALL_TARGET_PATH>
#
# Called by UpdateChecker as a detached process right before the app quits.
# 1. Waits for the app to exit
# 2. Replaces the old .app with the staged one
# 3. Relaunches the new .app
# 4. Cleans up

APP_PID="$1"
STAGED_APP="$2"
INSTALL_TARGET="$3"

# 1. Wait for the old app to exit (poll every 0.5s, timeout after 30s)
WAITED=0
while kill -0 "$APP_PID" 2>/dev/null; do
    sleep 0.5
    WAITED=$((WAITED + 1))
    if [[ "$WAITED" -ge 60 ]]; then
        echo "Timed out waiting for app (PID $APP_PID) to exit." >&2
        exit 1
    fi
done

# 2. Remove old app
rm -rf "$INSTALL_TARGET"

# 3. Move staged app to install target
cp -R "$STAGED_APP" "$INSTALL_TARGET"

# 4. Clear quarantine attribute
xattr -cr "$INSTALL_TARGET" 2>/dev/null || true

# 5. Launch the new app
open "$INSTALL_TARGET"

# 6. Clean up staged app
rm -rf "$STAGED_APP"
