#!/bin/bash
set -e

# Script to prepare Homebrew formula after creating a GitHub release

# Get version from VERSION file
if [ ! -f "VERSION" ]; then
  echo "❌ VERSION file not found"
  echo "Run this script from the project root directory"
  exit 1
fi

VERSION=$(cat VERSION)
REPO="graysoncash/soundctl"
TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
TEMP_DIR=$(mktemp -d)

echo "📦 Downloading release tarball..."
MAX_RETRIES=30
RETRY_DELAY=2
ATTEMPT=1

while [ $ATTEMPT -le $MAX_RETRIES ]; do
  echo "Attempt $ATTEMPT of $MAX_RETRIES..."
  if curl -L -f -o "${TEMP_DIR}/soundctl-${VERSION}.tar.gz" "${TARBALL_URL}"; then
    break
  fi
  
  if [ $ATTEMPT -lt $MAX_RETRIES ]; then
    echo "⏳ Waiting ${RETRY_DELAY}s before retry..."
    sleep $RETRY_DELAY
  fi
  
  ATTEMPT=$((ATTEMPT + 1))
done

if [ $ATTEMPT -gt $MAX_RETRIES ]; then
  echo "❌ Failed to download tarball after $MAX_RETRIES attempts"
  exit 1
fi

echo "🔐 Calculating SHA256..."
SHA256=$(shasum -a 256 "${TEMP_DIR}/soundctl-${VERSION}.tar.gz" | awk '{print $1}')

echo ""
echo "✨ Formula ready!"
echo ""
echo "Version: ${VERSION}"
echo "SHA256:  ${SHA256}"
echo ""
echo "Update soundctl.rb with:"
echo "  url \"${TARBALL_URL}\""
echo "  sha256 \"${SHA256}\""
echo ""

# Cleanup
rm -rf "${TEMP_DIR}"

# Optionally update the formula automatically
if [ "$1" = "--update" ]; then
  TAP_PATH="${TAP_PATH:-../homebrew-soundctl/Formula/soundctl.rb}"
  if [ -f "$TAP_PATH" ]; then
    echo "Updating formula in tap repo..."
    sed -i '' "s|url \".*\"|url \"${TARBALL_URL}\"|" "$TAP_PATH"
    sed -i '' "s|sha256 \".*\"|sha256 \"${SHA256}\"|" "$TAP_PATH"
    echo "✅ Formula updated at $TAP_PATH"
    echo "Don't forget to commit and push the tap repo!"
  else
    echo "⚠️  Tap repo not found at $TAP_PATH"
    echo "Update the formula manually with the values above"
  fi
fi
