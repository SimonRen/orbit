#!/bin/bash
set -e

# orb-kubectl Release Script
# Usage: ./scripts/release-orb-kubectl.sh <version>
# Example: ./scripts/release-orb-kubectl.sh 1.1.0
#
# Prerequisites:
# - Custom kubectl binary at vendor/bin/kubectl
# - GitHub CLI (gh) authenticated

VERSION=${1:?Usage: $0 <version>}
VENDOR_DIR="vendor/bin"
KUBECTL_SRC="${VENDOR_DIR}/kubectl"
OUTPUT_NAME="orb-kubectl"
ZIP_NAME="orb-kubectl-darwin-universal.zip"

echo "=== Releasing orb-kubectl v${VERSION} ==="

# Check kubectl binary exists
if [[ ! -f "$KUBECTL_SRC" ]]; then
    echo "Error: kubectl binary not found at $KUBECTL_SRC"
    echo "Please place your custom kubectl build there first."
    exit 1
fi

# Verify it's a universal binary
echo "→ Verifying binary..."
file "$KUBECTL_SRC" | grep -q "universal binary" || {
    echo "Warning: Binary may not be universal (arm64 + x86_64)"
    echo "Current: $(file "$KUBECTL_SRC")"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
}

# Create zip
echo "→ Creating release archive..."
cd "$VENDOR_DIR"
cp kubectl "$OUTPUT_NAME"
rm -f "$ZIP_NAME"
zip "$ZIP_NAME" "$OUTPUT_NAME"
rm "$OUTPUT_NAME"

# Calculate checksum
CHECKSUM=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
echo "→ SHA256: $CHECKSUM"

# Get file size
SIZE=$(stat -f%z "$ZIP_NAME")
echo "→ Size: $SIZE bytes ($(( SIZE / 1024 / 1024 ))MB)"

cd - > /dev/null

# Create GitHub release
echo "→ Creating GitHub release..."
gh release create "orb-kubectl-v${VERSION}" \
    "${VENDOR_DIR}/${ZIP_NAME}" \
    --title "orb-kubectl v${VERSION}" \
    --notes "kubectl with retry support for port-forwarding in Orbit.

## Installation
Install via Orbit menu: **Orbit → Install orb-kubectl...**

## Checksum
\`\`\`
SHA256: ${CHECKSUM}
\`\`\`
"

RELEASE_URL="https://github.com/simonren/orbit/releases/download/orb-kubectl-v${VERSION}/${ZIP_NAME}"

echo ""
echo "=== Release Complete ==="
echo "Release: https://github.com/simonren/orbit/releases/tag/orb-kubectl-v${VERSION}"
echo ""
echo "Next steps - update ToolManager.swift:"
echo ""
echo "    static let orbKubectlDefinition = ToolDefinition("
echo "        name: \"orb-kubectl\","
echo "        version: \"${VERSION}\","
echo "        downloadURL: URL(string: \"${RELEASE_URL}\")!,"
echo "        sha256: \"${CHECKSUM}\","
echo "        description: \"kubectl with retry support for port-forwarding\""
echo "    )"
echo ""
echo "Then release a new Orbit version for users to get the update."
