#!/usr/bin/env bash
set -euo pipefail

# Usage: Set ARCH and VERSION env vars before running, e.g.:
#   ARCH=arm64 VERSION=1.2.3 ./build.sh

ARCH="${ARCH:-arm64}"
VERSION="${VERSION:-dev}"

# Remove 'v' prefix if present in version
echo "Building for arch: $ARCH, version: $VERSION"
VERSION_CLEAN=${VERSION#v}


# Replace currentVersion in HTMLPopup.swift with the build version
sed "s/var currentVersion = \".*\"/var currentVersion = \"$VERSION_CLEAN\"/" HTMLPopup.swift > HTMLPopup.build.swift


# Build the binary with version info
swiftc -o htmlpopup-${ARCH} HTMLPopup.build.swift \
  -framework Cocoa -framework WebKit -framework Foundation -framework AppKit

# Clean up temporary build file
rm HTMLPopup.build.swift


echo "Built htmlpopup-${ARCH} with version $VERSION_CLEAN"
