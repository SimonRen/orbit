#!/bin/bash
set -e

# Orbit Release Script
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.2.9
#
# Prerequisites:
# - Sparkle EdDSA key in Keychain (run generate_keys once)
# - Notarization profile "notary" in Keychain

VERSION=${1:-$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')}
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
        NEW_ITEM="        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
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

        # Insert after <!-- Latest version first --> comment (or after <language>en</language>)
        if grep -q "<!-- Latest version first -->" "$APPCAST_FILE"; then
            # Use perl for multi-line replacement
            perl -i -pe "s|(<!-- Latest version first -->)|\$1\n${NEW_ITEM}|" "$APPCAST_FILE"
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
            color: #333;
        }
        h2 { color: #1a1a1a; border-bottom: 1px solid #eee; padding-bottom: 8px; }
        ul { padding-left: 20px; }
        li { margin: 8px 0; }
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
