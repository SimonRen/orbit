#!/bin/bash
set -e

# Orbit Release Script
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.2.9
#
# Prerequisites:
# - Sparkle EdDSA key in Keychain (run generate_keys once)
# - Notarization profile "notary" in Keychain

# Read versions from project.yml using yq
PROJECT_VERSION=$(yq '.settings.base.MARKETING_VERSION' project.yml | tr -d '"')
BUILD_NUMBER=$(yq '.settings.base.CURRENT_PROJECT_VERSION' project.yml | tr -d '"')
VERSION=${1:-$PROJECT_VERSION}

# Version check: ensure project.yml matches the release version
if [[ "$VERSION" != "$PROJECT_VERSION" ]]; then
    echo "ERROR: Version mismatch!"
    echo "  Release version: $VERSION"
    echo "  project.yml MARKETING_VERSION: $PROJECT_VERSION"
    echo ""
    echo "Please update project.yml first:"
    echo "  MARKETING_VERSION: \"$VERSION\""
    echo "  CURRENT_PROJECT_VERSION: \"$((BUILD_NUMBER + 1))\""
    exit 1
fi
RELEASES_DIR="releases"
DMG_NAME="Orbit-v${VERSION}.dmg"
APPCAST_FILE="docs/appcast.xml"
RELEASE_NOTES_DIR="docs/release-notes"
BUILD_DIR=$(xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release -showBuildSettings 2>/dev/null | grep -m1 'TARGET_BUILD_DIR' | awk '{print $3}')

# Find Sparkle tools (in SPM artifacts after build)
find_sparkle_bin() {
    # Check common locations
    local locations=(
        "${HOME}/Library/Developer/Xcode/DerivedData/orbit-*/SourcePackages/artifacts/sparkle/Sparkle/bin"
        ".build/artifacts/sparkle/Sparkle/bin"
        "$(pwd)/SourcePackages/artifacts/sparkle/Sparkle/bin"
    )
    for loc in "${locations[@]}"; do
        # Use ls to expand glob, take first match
        local expanded=$(ls -d $loc 2>/dev/null | head -1)
        if [[ -d "$expanded" ]]; then
            echo "$expanded"
            return 0
        fi
    done
    return 1
}

echo "=== Building Orbit v${VERSION} (build ${BUILD_NUMBER}) ==="

# Regenerate Xcode project
echo "→ Regenerating Xcode project..."
xcodegen generate

# Use archive + export workflow for proper code signing of embedded frameworks
echo "→ Archiving Release configuration..."
ARCHIVE_PATH="${RELEASES_DIR}/Orbit.xcarchive"
rm -rf "$ARCHIVE_PATH"

xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    clean archive | tail -30

# Create export options plist
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPORT_OPTIONS="${RELEASES_DIR}/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>DN4YAHWP2P</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

# Export the archive (this properly re-signs all embedded frameworks)
echo "→ Exporting archive..."
EXPORT_PATH="${RELEASES_DIR}/export"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" | tail -20

APP_PATH="${EXPORT_PATH}/Orbit.app"
echo "→ App exported at: ${APP_PATH}"

# Verify signature
echo "→ Verifying code signature..."
codesign -dv --verbose=2 "${APP_PATH}" 2>&1 | grep -E "Identifier|Authority|Timestamp"
codesign --verify --deep --strict "${APP_PATH}" && echo "✓ Signature valid" || echo "✗ Signature INVALID"

# Notarize
echo "→ Submitting for notarization..."
cd "${EXPORT_PATH}"
rm -f Orbit-notarize.zip
ditto -c -k --keepParent Orbit.app Orbit-notarize.zip
xcrun notarytool submit Orbit-notarize.zip --keychain-profile "notary" --wait
rm -f Orbit-notarize.zip
cd "${PROJECT_ROOT}"

# Staple
echo "→ Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"

# Create DMG
echo "→ Creating DMG..."
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

# === Sparkle Signing ===
echo "→ Finding Sparkle tools..."
SPARKLE_BIN=$(find_sparkle_bin)
if [[ -z "$SPARKLE_BIN" ]]; then
    echo "⚠️  Sparkle tools not found. Skipping signature generation."
    echo "   Build the project first to download Sparkle, then re-run."
else
    echo "→ Generating Sparkle EdDSA signature..."
    # sign_update outputs: sparkle:edSignature="xxx" length="yyy"
    SIGN_OUTPUT=$("${SPARKLE_BIN}/sign_update" "${RELEASES_DIR}/${DMG_NAME}" 2>&1) || {
        echo "⚠️  Sparkle signing failed. Make sure EdDSA key is in Keychain."
        echo "   Run: ${SPARKLE_BIN}/generate_keys"
        SIGN_OUTPUT=""
    }

    if [[ -n "$SIGN_OUTPUT" ]]; then
        ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
        FILE_SIZE=$(stat -f%z "${RELEASES_DIR}/${DMG_NAME}")
        PUB_DATE=$(date -R)

        echo "   Signature: ${ED_SIGNATURE:0:40}..."
        echo "   Size: ${FILE_SIZE} bytes"

        # Update appcast.xml with new version
        echo "→ Updating appcast.xml..."
        RELEASE_URL="https://github.com/simonren/orbit/releases/download/v${VERSION}/${DMG_NAME}"
        NOTES_URL="https://simonren.github.io/orbit/release-notes/${VERSION}.html"

        # Create new item XML
        # sparkle:version = CFBundleVersion (build number), sparkle:shortVersionString = marketing version
        NEW_ITEM="        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:releaseNotesLink>${NOTES_URL}</sparkle:releaseNotesLink>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure
                url=\"${RELEASE_URL}\"
                sparkle:edSignature=\"${ED_SIGNATURE}\"
                length=\"${FILE_SIZE}\"
                type=\"application/octet-stream\" />
        </item>"

        # Insert after <!-- Latest version first ... --> comment (or after <language>en</language>)
        if grep -q "<!-- Latest version first" "$APPCAST_FILE"; then
            # Use perl for multi-line replacement - match the comment and insert after it
            perl -i -pe "s|(<!-- Latest version first[^>]*-->)|\$1\n${NEW_ITEM}|" "$APPCAST_FILE"
        else
            # Fallback: insert after <language>en</language>
            perl -i -pe "s|(<language>en</language>)|\$1\n\n        <!-- Latest version first -->\n${NEW_ITEM}|" "$APPCAST_FILE"
        fi

        # Create release notes template if it doesn't exist
        if [[ ! -f "${RELEASE_NOTES_DIR}/${VERSION}.html" ]]; then
            echo "→ Creating release notes template..."
            mkdir -p "${RELEASE_NOTES_DIR}"
            cat > "${RELEASE_NOTES_DIR}/${VERSION}.html" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            padding: 20px;
            max-width: 600px;
            line-height: 1.5;
            background: #ffffff;
            color: #333;
        }
        h2 { color: #1a1a1a; border-bottom: 1px solid #ddd; padding-bottom: 8px; }
        ul { padding-left: 20px; }
        li { margin: 8px 0; }
        @media (prefers-color-scheme: dark) {
            body { background: #2d2d2d; color: #e0e0e0; }
            h2 { color: #ffffff; border-bottom-color: #555; }
        }
    </style>
</head>
<body>
HTMLEOF
            echo "    <h2>What's New in Orbit ${VERSION}</h2>" >> "${RELEASE_NOTES_DIR}/${VERSION}.html"
            echo "    <ul>" >> "${RELEASE_NOTES_DIR}/${VERSION}.html"
            echo "        <li>TODO: Add release notes</li>" >> "${RELEASE_NOTES_DIR}/${VERSION}.html"
            echo "    </ul>" >> "${RELEASE_NOTES_DIR}/${VERSION}.html"
            echo "</body>" >> "${RELEASE_NOTES_DIR}/${VERSION}.html"
            echo "</html>" >> "${RELEASE_NOTES_DIR}/${VERSION}.html"
        fi
    fi
fi

echo ""
echo "=== Release Complete ==="
echo "DMG: ${RELEASES_DIR}/${DMG_NAME}"
ls -la "${RELEASES_DIR}/${DMG_NAME}"
echo ""
echo "Next steps:"
echo "  1. Edit release notes: ${RELEASE_NOTES_DIR}/${VERSION}.html"
echo "  2. git add docs/ && git commit -m 'Release v${VERSION}'"
echo "  3. git tag v${VERSION} && git push origin main --tags"
echo "  4. Create GitHub Release: gh release create v${VERSION} ${RELEASES_DIR}/${DMG_NAME}"
