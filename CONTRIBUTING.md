# Contributing to YTDLPKit

Thanks for helping improve YTDLPKit. Changes should preserve the package's
small public surface, Swift 6 strict-concurrency guarantees, and iOS-first
one-dependency installation.

## Before opening a change

1. Open an issue for public API, runtime packaging, licensing, or security-model
   changes before investing in an implementation.
2. Keep application features out of the library. Persistence, playback, UI,
   downloads, transcoding, and muxing are intentionally out of scope.
3. Never commit cookies, credentials, signed media URLs, or unsanitized yt-dlp
   output. Fixtures must be reviewed and sanitized.
4. Do not add live network calls to the normal test suite.

## Local checks

Use Xcode 16 or a compatible Swift 6 toolchain, then run:

```sh
swift build
swift test
swift format lint --recursive --strict Sources Tests Examples
```

Also build the example app from `Examples/YTDLPKitExample` when changing the
public API. Runtime packaging changes must be tested on both an iOS Simulator
and a physical iPhone.

## Testing

- Prefer small unit tests and sanitized recorded JSON fixtures.
- Cover malformed values, cancellation, concurrent callers, typed error
  mapping, redaction, `formats`, and nested `requested_formats`.
- Ordinary CI must remain deterministic and network-free.
- Live tests require an explicit environment opt-in and are run only in the
  separately gated workflow. Never make a pull request depend on YouTube being
  reachable or returning a particular format.

## Dependency and runtime updates

Updates to CPython, yt-dlp, the JavaScript challenge provider, or any
binary runtime must include:

1. Exact upstream versions and source commits.
2. Reproducible build inputs and commands.
3. Published SHA-256 checksums and SwiftPM artifact checksum.
4. Updated license notices, provenance, and SBOM.
5. Fixture, unit, simulator, live opt-in, and physical-device validation.
6. Confirmation that no runtime code download or self-update was introduced.

Select a custom local yt-dlp module only before constructing the first client.
Tests must exercise invalid type, path containment, size, digest, import,
version, and API-compatibility failures.

## Pull requests

Use focused commits and explain observable behavior, risk, and verification.
Public API changes require documentation and tests. Do not commit generated
build products, signing material, or local package state.

By contributing, you agree that your contribution is licensed under the MIT
License in this repository.
