#!/usr/bin/env bash
# Build + zip + publish a release for the CURRENT OS.
#   Usage:  tool/release.sh <version> [--required]
#   e.g.    tool/release.sh 1.1.0
#
# You can only build for the OS you're on. Run this on macOS for the mac package;
# build Windows on a Windows machine (commands printed below).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -z "$VERSION" ] && { echo "usage: tool/release.sh <version> [--required]   e.g. tool/release.sh 1.1.0"; exit 1; }
REQUIRED="${2:-}"

case "$(uname -s)" in
  Darwin)
    echo "Building macOS release (v$VERSION)..."
    flutter build macos --release
    APP="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' | head -1)"
    [ -n "$APP" ] || { echo "no .app found in build output"; exit 1; }
    echo ""
    echo ">>> IMPORTANT: notarize \"$APP\" (xcrun notarytool submit ... --wait) before"
    echo ">>> publishing, or Gatekeeper will block the relaunch on other Macs. <<<"
    echo ""
    ZIP="build/$(basename "${APP%.app}")-$VERSION-mac.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    node tool/publish_release.js macos "$VERSION" "$ZIP" $REQUIRED
    ;;
  *)
    echo "This OS can't build the macOS/Windows desktop package directly."
    echo "On a WINDOWS machine, run:"
    echo "  flutter build windows --release"
    echo "  Compress-Archive build\\windows\\x64\\runner\\Release\\* Tulanam-$VERSION-win.zip"
    echo "  node tool/publish_release.js windows $VERSION Tulanam-$VERSION-win.zip $REQUIRED"
    exit 1
    ;;
esac
