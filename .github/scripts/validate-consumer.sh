#!/bin/bash
set -euo pipefail

consumer_dir="$(mktemp -d "${TMPDIR:-/tmp}/ytdlpkit-consumer.XXXXXX")"
trap 'rm -rf "$consumer_dir"' EXIT

mkdir -p "$consumer_dir/Sources/Consumer"

repo_path="$(pwd)"
cat > "$consumer_dir/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "${repo_path}")],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [.product(name: "YTDLPKit", package: "YTDLPKit")]
        ),
    ]
)
EOF

cat > "$consumer_dir/Sources/Consumer/main.swift" <<'EOF'
import YTDLPKit

let _: YTDLPConfiguration = .init()
EOF

swift build --package-path "$consumer_dir"
