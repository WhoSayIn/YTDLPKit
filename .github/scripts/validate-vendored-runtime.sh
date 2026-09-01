#!/bin/bash
set -euo pipefail

build_root="${1:-}"
if [[ -z "$build_root" || ! -f "$build_root/dist/ArtifactManifest.json" ]]; then
  echo "usage: $0 <runtime-build-directory>" >&2
  exit 64
fi

comparison_root="$(mktemp -d "${TMPDIR:-/tmp}/ytdlpkit-vendored-runtime.XXXXXX")"
trap 'rm -rf "$comparison_root"' EXIT

unzip -q "$build_root/dist/PythonRuntime.xcframework.zip" -d "$comparison_root/core"
diff -qr "$comparison_root/core/PythonRuntime.xcframework" Vendor/PythonRuntime/PythonRuntime.xcframework

while IFS= read -r archive; do
  name="$(basename "$archive" .xcframework.zip)"
  extension_root="$comparison_root/extensions/$name"
  mkdir -p "$extension_root"
  unzip -q "$archive" -d "$extension_root"
  diff -qr "$extension_root/$name.xcframework" "Vendor/PythonRuntime/Extensions/$name.xcframework"
done < <(find "$build_root/dist" -maxdepth 1 -name '*.xcframework.zip' ! -name 'PythonRuntime.xcframework.zip' | sort)

unzip -q "$build_root/dist/PythonRuntimeResources.zip" -d "$comparison_root/resources"
diff -qr \
  "$comparison_root/resources/python" \
  Sources/YTDLPKit/Resources/PythonRuntime/python

cmp "$build_root/dist/ArtifactManifest.json" Runtime/ArtifactManifest.json
cmp "$build_root/dist/BuildProvenance.json" Runtime/BuildProvenance.json
cmp "$build_root/dist/SBOM.spdx.json" Runtime/SBOM.spdx.json
cmp Runtime/ArtifactManifest.json Sources/YTDLPKit/Resources/Licenses/ArtifactManifest.json
cmp Runtime/BuildProvenance.json Sources/YTDLPKit/Resources/Licenses/BuildProvenance.json
cmp Runtime/SBOM.spdx.json Sources/YTDLPKit/Resources/Licenses/SBOM.spdx.json
cmp ThirdPartyLicenses/Expat-COPYING "$comparison_root/resources/Licenses/Expat-COPYING"
cmp ThirdPartyLicenses/Expat-COPYING Sources/YTDLPKit/Resources/Licenses/Expat-COPYING
test -s Sources/YTDLPKit/Resources/Licenses/THIRD_PARTY_NOTICES.md

expected_extensions="$(find Vendor/PythonRuntime/Extensions -mindepth 1 -maxdepth 1 -name '*.xcframework' | wc -l | tr -d ' ')"
built_extensions="$(find "$build_root/dist" -maxdepth 1 -name '*.xcframework.zip' ! -name 'PythonRuntime.xcframework.zip' | wc -l | tr -d ' ')"
if [[ "$expected_extensions" != "$built_extensions" ]]; then
  echo "Vendored extension count differs from rebuilt artifact count." >&2
  exit 1
fi

echo "Vendored runtime and resources match the clean rebuild."
