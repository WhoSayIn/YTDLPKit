#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
LOCK_FILE=${YTDLPKIT_RUNTIME_LOCK:-"$REPOSITORY_ROOT/Runtime/runtime-lock.json"}
DOWNLOAD_DIR=${YTDLPKIT_RUNTIME_DOWNLOAD_DIR:-"$REPOSITORY_ROOT/Runtime/Downloads"}
BUILD_DIR=${YTDLPKIT_RUNTIME_BUILD_DIR:-"$REPOSITORY_ROOT/Runtime/Build"}

PYTHON_BIN=${PYTHON_BIN:-python3}

mkdir -p "$DOWNLOAD_DIR" "$BUILD_DIR"

ARCHIVE_NAME=$(
    "$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["python"]["archive"])' "$LOCK_FILE"
)
ARCHIVE_PATH="$DOWNLOAD_DIR/$ARCHIVE_NAME"

"$SCRIPT_DIR/fetch-runtime.sh" "$LOCK_FILE" "$ARCHIVE_PATH"
set --
if [ -n "${YTDLPKIT_RUNTIME_SIGNING_IDENTITY:-}" ]; then
    set -- --signing-identity "$YTDLPKIT_RUNTIME_SIGNING_IDENTITY"
fi

"$PYTHON_BIN" "$SCRIPT_DIR/repackage_runtime.py" \
    --lock "$LOCK_FILE" \
    --archive "$ARCHIVE_PATH" \
    --output "$BUILD_DIR" \
    "$@"
"$SCRIPT_DIR/verify-runtime.sh" "$BUILD_DIR"

echo "Runtime artifacts are ready in $BUILD_DIR/dist"
