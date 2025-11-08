#!/bin/bash

VERSION_FILE="VERSION"
OUTPUT_FILE="Sources/soundctl/Version.swift"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: VERSION file not found"
    exit 1
fi

VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

cat > "$OUTPUT_FILE" << EOF
// This file is auto-generated. Do not edit manually.
// Run 'make generate-version' to update.

let version = "$VERSION"
EOF

echo "Generated $OUTPUT_FILE with version $VERSION"
