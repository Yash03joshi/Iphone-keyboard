#!/usr/bin/env bash
# Downloads the ML Kit Digital Ink resource bundle that the keyboard extension must embed.
set -euo pipefail
VERSION=9.0.2
BUNDLE=MLKitDigitalInkRecognition_resource.bundle
cd "$(dirname "$0")/.."
mkdir -p Resources
tmp=$(mktemp -d)
curl -fL -o "$tmp/$BUNDLE.zip" \
  "https://github.com/d-date/google-mlkit-swiftpm/releases/download/$VERSION/$BUNDLE.zip"
rm -rf "Resources/$BUNDLE"
unzip -q "$tmp/$BUNDLE.zip" -d "$tmp/out"
mv "$(find "$tmp/out" -type d -name "$BUNDLE" | head -1)" Resources/
rm -rf "$tmp"
echo "Fetched Resources/$BUNDLE"
