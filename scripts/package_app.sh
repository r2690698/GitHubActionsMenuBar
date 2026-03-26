#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GitHubActionsMenuBar"
PRODUCT_NAME="${APP_NAME}.app"
BUILD_DIR="${ROOT_DIR}/.build/release"
OUTPUT_DIR="${ROOT_DIR}/dist"
APP_DIR="${OUTPUT_DIR}/${PRODUCT_NAME}"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

"${ROOT_DIR}/scripts/build_app_icon.sh"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT_DIR}/packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT_DIR}/packaging/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

if [[ -n "${APP_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
fi

if [[ -n "${APP_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_BUILD}" "${APP_DIR}/Contents/Info.plist"
fi

find "${BUILD_DIR}" -maxdepth 1 -name '*.bundle' -exec cp -R {} "${RESOURCES_DIR}/" \;

chmod +x "${MACOS_DIR}/${APP_NAME}"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}"
fi

echo "Packaged app: ${APP_DIR}"
