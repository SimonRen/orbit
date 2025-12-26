#!/bin/bash
set -e

# Orbit Release Script
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.2.9

VERSION=${1:-$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')}
RELEASES_DIR="releases"
DMG_NAME="Orbit-v${VERSION}.dmg"
BUILD_DIR=$(xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release -showBuildSettings 2>/dev/null | grep -m1 'TARGET_BUILD_DIR' | awk '{print $3}')

echo "=== Building Orbit v${VERSION} ==="

# Regenerate Xcode project
echo "→ Regenerating Xcode project..."
xcodegen generate

# Clean and build Release
echo "→ Building Release configuration..."
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release clean build | xcpretty || xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release clean build | tail -20

# Get actual build directory after build
BUILD_DIR=$(xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release -showBuildSettings 2>/dev/null | grep -m1 'TARGET_BUILD_DIR' | awk '{print $3}')
APP_PATH="${BUILD_DIR}/Orbit.app"

echo "→ App built at: ${APP_PATH}"

# Verify signature
echo "→ Verifying code signature..."
codesign -dv --verbose=2 "${APP_PATH}" 2>&1 | grep -E "Identifier|Authority|Timestamp"

# Notarize
echo "→ Submitting for notarization..."
cd "${BUILD_DIR}"
rm -f Orbit-notarize.zip
zip -r Orbit-notarize.zip Orbit.app
xcrun notarytool submit Orbit-notarize.zip --keychain-profile "notary" --wait
rm -f Orbit-notarize.zip

# Staple
echo "→ Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"

# Create DMG
echo "→ Creating DMG..."
cd "${OLDPWD}"
mkdir -p "${RELEASES_DIR}"
rm -rf dmg-staging "${RELEASES_DIR}/${DMG_NAME}"
mkdir dmg-staging
cp -R "${APP_PATH}" dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "Orbit" -srcfolder dmg-staging -ov -format UDZO "${RELEASES_DIR}/${DMG_NAME}"
rm -rf dmg-staging

# Notarize DMG
echo "→ Notarizing DMG..."
xcrun notarytool submit "${RELEASES_DIR}/${DMG_NAME}" --keychain-profile "notary" --wait
xcrun stapler staple "${RELEASES_DIR}/${DMG_NAME}"

echo ""
echo "=== Release Complete ==="
echo "DMG: ${RELEASES_DIR}/${DMG_NAME}"
ls -la "${RELEASES_DIR}/${DMG_NAME}"
