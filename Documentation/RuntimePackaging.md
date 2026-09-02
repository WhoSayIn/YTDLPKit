# Python runtime packaging

YTDLPKit pins BeeWare's Python Apple support release `3.13-b14`, containing
CPython 3.13.14. The URL and upstream SHA-256 digest are recorded in
`Runtime/runtime-lock.json`. The runtime is not fetched or transformed on a
consumer's machine. The layout follows CPython's
[iOS embedding and framework guidance](https://docs.python.org/3/using/ios.html).

## Why repackaging is required

The upstream `Python.xcframework` contains the Python framework, the standard
library, and architecture-specific extension modules. The latter are Mach-O
dynamic libraries stored as `.so` files. Upstream's normal integration copies
those files into an app, turns every file into a framework, writes an `.fwork`
loader mapping, and signs it in an app-target build phase.

YTDLPKit performs the structural transformation when producing a release:

- `PythonRuntime.xcframework.zip` contains only the device and universal
  simulator Python frameworks.
- Each standard-library extension becomes its own two-slice XCFramework. Its
  install name is normalized to `@rpath/<module>.framework/<module>`.
- `_ssl` and `_hashlib` carry a `PrivacyInfo.xcprivacy` in both framework
  slices because they incorporate OpenSSL. The manifest declares no tracking,
  collected data, or tracking domains. It reproduces OpenSSL 3.0.18's sole
  required-reason declaration: file timestamps for reason `C617.1`.
- Both `Python.framework` slices carry a core privacy manifest declaring file
  timestamps (`C617.1`) and system boot time (`35F9.1`), with no tracking,
  collected data, or tracking domains.

The core binary also contains `statfs` and `fstatfs` symbols. YTDLPKit's
metadata-only runtime does not use disk-capacity behavior that qualifies for
DiskSpace reason `E174.1`, so the manifest does not make that declaration.
Those symbols remain an archive-analysis and App Store validation risk to
recheck for every runtime update and submission.

Apple documents privacy-manifest placement and validation in
[Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).

- `PythonRuntimeResources.zip` contains a deterministic `python313.zip` and
  the `.fwork` mappings for every device and simulator extension filename. It
  also contains the device-arm64, simulator-arm64, and simulator-x86_64
  `_sysconfigdata__ios_*.py` modules required by CPython during initialization.
- `ArtifactManifest.json` records the source pin and SHA-256 of every produced
  archive. They can also be used as SwiftPM checksums if a future release moves
  from checked-in local binary targets to URL-based binary targets.
- `BuildProvenance.json` records the source material, artifact subjects, build
  interpreter, and transformation-script digests. `SBOM.spdx.json` inventories
  the runtime components, including CPython's pinned Expat 2.8.1 copy, in SPDX
  2.3 form with dependency relationships. The inventory also validates and
  records the bundled yt-dlp 2026.08.19 executable ZIP and
  yt-dlp-apple-webkit-jsi 0.1.1-noextapp-53dcc9d provider ZIP, and certifi
  2026.7.22 wheel, including their source locations, SHA-256 values, licenses,
  and the provider's pinned source commit. certifi supplies the Mozilla CA
  bundle used by embedded OpenSSL for verified HTTPS connections.

The release omits only the pinned test/sample extension list recorded in
`ArtifactManifest.json`: `_ctypes_test`, `_test*`, `_xxtestfuzz`, `xxlimited`,
`xxlimited_35`, and `xxsubtype`. Runtime modules are not pruned without import
closure evidence.

This layout lets SwiftPM/Xcode embed and sign ordinary frameworks. Consumers do
not add a build phase, install Python, supply paths, or run a script.

## Produce and verify artifacts

Requirements are macOS, Xcode command-line tools, Python 3.11 or newer,
`curl`, and `shasum`.

```sh
Scripts/runtime/build-runtime.sh
```

To isolate build products outside the checkout:

```sh
YTDLPKIT_RUNTIME_DOWNLOAD_DIR=/tmp/ytdlpkit-downloads \
YTDLPKIT_RUNTIME_BUILD_DIR=/tmp/ytdlpkit-runtime \
Scripts/runtime/build-runtime.sh
```

The build fails closed on a source checksum mismatch, archive traversal,
inconsistent architecture module sets, a failed Mach-O transformation, or a
verification error. `verify-runtime.sh` checks every release archive checksum,
ZIP integrity, XCFramework architecture set, standard-library contents, and
loader-mapping count. It also validates the privacy manifests, exclusions,
sysconfig modules, SPDX relationships, and optional signatures.

Local builds remain unsigned. Release automation can request post-transform
framework signing with a stable identity:

```sh
YTDLPKIT_RUNTIME_SIGNING_IDENTITY="Developer ID Application: Example" \
Scripts/runtime/build-runtime.sh
```

Signing runs after binaries, install names, plists, and privacy manifests are
finalized, uses no timestamp, and verifies every framework with strict
`codesign` validation before archives are produced. The selected identity and
mode are recorded in the artifact manifest and provenance.

## Package integration boundary

The pipeline deliberately does not edit `Package.swift`. Maintainers copy the
verified, expanded XCFrameworks into `Vendor/PythonRuntime` and the extracted
resource payload into `Sources/YTDLPKit/Resources/PythonRuntime`, then update
the checked-in manifest, provenance, and SBOM. The package declares each
framework as a private local binary target. This keeps installation to one
SwiftPM dependency and avoids relying on dozens of separately hosted binary
artifact URLs.

All extension binary targets must be dependencies of the private runtime target
so Xcode embeds them in the application. The runtime bootstrap must use its
resource bundle to configure Python's module search path with both:

1. `python/lib/python313.zip`
2. `python/lib/python3.13/lib-dynload`

The transformation removes the upstream consumer build phase, but an iOS
simulator smoke test and a signed physical-device smoke test remain release
gates. Static inspection alone cannot prove that Apple's loader, code signing,
and CPython's `.fwork` hook operate correctly in the final application.

Run the package's embedded-runtime XCTest on an iOS Simulator:

```sh
xcodebuild test \
  -scheme YTDLPKit \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:YTDLPKitTests/EmbeddedRuntimeSmokeTests \
  CODE_SIGNING_ALLOWED=NO
```

The test initializes the packaged interpreter and imports `ssl`, `hashlib`,
`json`, and `yt_dlp`. Release validation also inspects a built consumer app for
the Python framework, standard-library ZIP, and all extension frameworks. A
compile-only result is not runtime proof.

## Provenance

- Upstream source: `beeware/Python-Apple-support`
- Support release: `3.13-b14`
- Upstream release commit: `54d8ab6ef4fbac4d60706f311a986aee5236c71b`
- CPython: 3.13.14
- Upstream archive digest: see `Runtime/runtime-lock.json`

Do not update only the URL. A runtime update requires a complete lock change,
fresh artifacts, manifest review, simulator validation, physical-device
validation, notices review, and a new package release.
