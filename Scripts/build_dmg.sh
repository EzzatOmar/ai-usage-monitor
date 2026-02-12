#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AIUsageMonitor"
BUILD_DIR=".build/release"
DIST_DIR="dist"
STAGING_DIR="${DIST_DIR}/${APP_NAME}"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"

echo "Building release binary..."
swift build -c release

echo "Preparing staging folder..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp "${BUILD_DIR}/${APP_NAME}" "${STAGING_DIR}/${APP_NAME}"

echo "Creating DMG..."
mkdir -p "${DIST_DIR}"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_PATH}"

echo "DMG generated at ${DMG_PATH}"
