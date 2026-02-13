#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration --------------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/version.env"

APP_NAME="AIUsageMonitor"
BUNDLE_ID="com.omarezzat.aiusagemonitor"
BUILD_CONF="${1:-release}"
DIST_DIR="${ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${MARKETING_VERSION}.dmg"
DMG_STAGING="${DIST_DIR}/dmg-staging"
ICON_DIR="${ROOT}/.build/icon"
ICNS_PATH="${ICON_DIR}/AppIcon.icns"

# ---- 1. Build binary -------------------------------------------------------
echo "==> Building ${APP_NAME} (${BUILD_CONF})..."
swift build -c "${BUILD_CONF}"

# Resolve binary path (SPM puts it in arch-specific subdir)
HOST_ARCH="$(uname -m)"
BINARY_PATH="${ROOT}/.build/${HOST_ARCH}-apple-macosx/${BUILD_CONF}/${APP_NAME}"
if [[ ! -f "${BINARY_PATH}" ]]; then
    BINARY_PATH="${ROOT}/.build/${BUILD_CONF}/${APP_NAME}"
fi
if [[ ! -f "${BINARY_PATH}" ]]; then
    echo "ERROR: Could not find built binary." >&2
    exit 1
fi
echo "    Binary: ${BINARY_PATH}"

# ---- 2. Generate icon -------------------------------------------------------
echo "==> Generating app icon..."
mkdir -p "${ICON_DIR}/AppIcon.iconset"

MASTER="${ICON_DIR}/AppIcon.iconset/icon_master.png"
swift "${ROOT}/Scripts/generate_icon.swift" "${MASTER}"

# Generate all required iconset sizes using sips
generate_icon_size() {
    local sz="$1"
    local dbl=$((sz * 2))
    sips -z "${sz}" "${sz}" "${MASTER}" --out "${ICON_DIR}/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
    if [[ "${dbl}" -le 1024 ]]; then
        sips -z "${dbl}" "${dbl}" "${MASTER}" --out "${ICON_DIR}/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
    fi
}

generate_icon_size 16
generate_icon_size 32
generate_icon_size 128
generate_icon_size 256
generate_icon_size 512
cp "${MASTER}" "${ICON_DIR}/AppIcon.iconset/icon_512x512@2x.png"

# Remove the master file (iconutil doesn't expect it)
rm -f "${MASTER}"

iconutil -c icns "${ICON_DIR}/AppIcon.iconset" -o "${ICNS_PATH}"
echo "    Icon: ${ICNS_PATH}"

# ---- 3. Assemble .app bundle ------------------------------------------------
echo "==> Assembling ${APP_NAME}.app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ICNS_PATH}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "${ROOT}/Scripts/update_helper.sh" "${APP_BUNDLE}/Contents/Resources/update_helper.sh"
chmod +x "${APP_BUNDLE}/Contents/Resources/update_helper.sh"

GIT_COMMIT="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>AI Usage Monitor</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2025 AI Usage Monitor</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "    Bundle: ${APP_BUNDLE}"

# ---- 4. Strip extended attributes & ad-hoc sign -----------------------------
xattr -cr "${APP_BUNDLE}"

echo "==> Signing (ad-hoc)..."
codesign --force --sign - "${APP_BUNDLE}"

# ---- 5. Create DMG with drag-to-Applications layout -------------------------
echo "==> Creating DMG..."
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"

cp -R "${APP_BUNDLE}" "${DMG_STAGING}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING}/Applications"

TEMP_DMG="${DIST_DIR}/.tmp_${APP_NAME}.dmg"
rm -f "${TEMP_DMG}" "${DMG_PATH}"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -fs HFS+ \
    -format UDRW \
    -size 100m \
    "${TEMP_DMG}"

# Mount at /Volumes so Finder can see it
hdiutil attach "${TEMP_DMG}" -noautoopen -quiet
MOUNT_DIR="/Volumes/${APP_NAME}"

# Style the DMG window using AppleScript (with retries for Finder)
for i in 1 2 3; do
    if osascript <<'APPLESCRIPT' 2>/dev/null
        tell application "Finder"
            tell disk "AIUsageMonitor"
                open
                delay 3
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {100, 100, 760, 500}

                set theViewOptions to the icon view options of container window
                set arrangement of theViewOptions to not arranged
                set icon size of theViewOptions to 120

                set position of item "AIUsageMonitor.app" to {185, 200}
                set position of item "Applications" to {475, 200}

                update without registering applications
                delay 1
                close
            end tell
        end tell
APPLESCRIPT
    then
        echo "    DMG styled successfully."
        break
    else
        echo "    AppleScript attempt $i failed, retrying..."
        sleep 3
    fi
done

hdiutil detach "${MOUNT_DIR}" -quiet

# Convert to compressed read-only DMG
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
rm -f "${TEMP_DMG}"
rm -rf "${DMG_STAGING}"

echo ""
echo "==> Done!"
echo "    App:  ${APP_BUNDLE}"
echo "    DMG:  ${DMG_PATH}"
echo "    Version: ${MARKETING_VERSION} (build ${BUILD_NUMBER})"
