#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <project-or-workspace> <scheme> [destination]" >&2
    echo "example: $0 Examples/RuntimeSmokeTest.xcodeproj RuntimeSmokeTest 'platform=iOS Simulator,name=iPhone 16 Pro'" >&2
    exit 64
fi

CONTAINER=$1
SCHEME=$2
DESTINATION=${3:-"platform=iOS Simulator,name=iPhone 16 Pro"}
DERIVED_DATA=$(mktemp -d /tmp/ytdlpkit-runtime-smoke.XXXXXX)
trap 'rm -rf "$DERIVED_DATA"' EXIT HUP INT TERM

case "$CONTAINER" in
    *.xcworkspace) CONTAINER_ARGUMENT=-workspace ;;
    *.xcodeproj) CONTAINER_ARGUMENT=-project ;;
    *)
        echo "project must end in .xcodeproj or .xcworkspace" >&2
        exit 64
        ;;
esac

# The selected scheme must contain a test that initializes the packaged
# interpreter and imports ssl, hashlib, json, and yt_dlp. A successful build
# alone is not a runtime smoke test.
xcodebuild \
    "$CONTAINER_ARGUMENT" "$CONTAINER" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    test

APP_PATH=$(find "$DERIVED_DATA/Build/Products" -type d -name '*.app' -not -path '*Tests*' | head -1)
if [ -z "$APP_PATH" ]; then
    echo "smoke test passed, but no built application was found for structural inspection" >&2
    exit 1
fi

test -d "$APP_PATH/Frameworks/Python.framework"
test -f "$APP_PATH/python/lib/python313.zip" || test -f "$APP_PATH/Contents/Resources/python/lib/python313.zip"

EXTENSION_COUNT=$(find "$APP_PATH/Frameworks" -mindepth 1 -maxdepth 1 -type d -name '*.framework' ! -name 'Python.framework' | wc -l | tr -d ' ')
if [ "$EXTENSION_COUNT" -lt 68 ]; then
    echo "expected at least 68 Python extension frameworks; found $EXTENSION_COUNT" >&2
    exit 1
fi

echo "Simulator smoke test passed; app embeds Python and $EXTENSION_COUNT extension frameworks"
