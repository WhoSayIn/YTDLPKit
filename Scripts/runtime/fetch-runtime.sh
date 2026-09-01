#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <runtime-lock.json> <archive-path>" >&2
    exit 64
fi

LOCK_FILE=$1
ARCHIVE_PATH=$2
PYTHON_BIN=${PYTHON_BIN:-python3}

read_lock_field() {
    "$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["python"][sys.argv[2]])' "$LOCK_FILE" "$1"
}

URL=$(read_lock_field url)
EXPECTED_SHA256=$(read_lock_field sha256)

verify_archive() {
    ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "runtime archive checksum mismatch" >&2
        echo "expected: $EXPECTED_SHA256" >&2
        echo "actual:   $ACTUAL_SHA256" >&2
        return 1
    fi
}

if [ -f "$ARCHIVE_PATH" ] && verify_archive; then
    echo "Using verified runtime archive $ARCHIVE_PATH"
    exit 0
fi

mkdir -p "$(dirname -- "$ARCHIVE_PATH")"
PARTIAL_PATH="$ARCHIVE_PATH.partial"
rm -f "$PARTIAL_PATH"
curl --fail --location --proto '=https' --tlsv1.2 "$URL" --output "$PARTIAL_PATH"
mv "$PARTIAL_PATH" "$ARCHIVE_PATH"
verify_archive
echo "Downloaded and verified $ARCHIVE_PATH"
