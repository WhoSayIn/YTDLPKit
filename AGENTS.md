# Repository Guidelines

## Project Structure & Module Organization

`Sources/YTDLPKit/` contains the public Swift 6 API, concurrency boundary, embedded-runtime adapter, DocC catalog, privacy manifest, and packaged resources. `Sources/CYTDLPPythonBridge/` is the C bridge to the vendored CPython runtime. Binary frameworks live under `Vendor/PythonRuntime/`; their pinned metadata, provenance, and SBOM live in `Runtime/` and `ThirdPartyLicenses/`. Tests are in `Tests/YTDLPKitTests/`, with sanitized JSON in `Tests/Fixtures/`. The sample consumer is `Examples/YTDLPKitExample/`; runtime maintenance scripts are under `Scripts/runtime/`.

## Build, Test, and Development Commands

- `swift build` — compile the package with the local Swift 6 toolchain.
- `swift test --skip LiveIntegrationTests` — run the deterministic, network-free suite used by CI.
- `swift format lint --recursive --strict Package.swift Sources Tests Examples` — enforce repository formatting.
- `.github/scripts/validate-vendored-runtime.sh` — check packaged runtime resources, licenses, manifests, and binaries after runtime changes.
- `Scripts/runtime/smoke-test-simulator.sh` — exercise embedded Python initialization in an iOS Simulator.

Build `Examples/YTDLPKitExample/YTDLPKitExample.xcodeproj` after public API changes. Live tests are separately gated; do not make routine validation depend on network access.

## Coding Style & Naming Conventions

Use two-space indentation and let `swift format` define layout. Follow Swift naming conventions: `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and descriptive enum cases. Preserve Swift 6 strict concurrency: public values and errors should remain `Sendable`, Python access stays actor-isolated, and Python objects must not cross the module boundary. Keep the public API small and metadata-focused.

## Testing Guidelines

Tests use XCTest. Name test files `*Tests.swift` and methods `testExpectedBehavior`. Prefer focused unit tests backed by sanitized fixtures. Cover malformed input, cancellation, concurrent callers, typed error mapping, redaction, formats, and nested `requested_formats`. Never add cookies, credentials, signed URLs, unsanitized extractor output, or ordinary-suite network calls.

## Commit & Pull Request Guidelines

Use short, imperative, focused subjects (for example, `Add timeout error mapping`). Pull requests must describe observable behavior, scope, risk, and verification. Include tests and DocC for public API changes. Discuss runtime packaging, licensing, security-model, or public API changes in an issue first. Runtime updates must record exact upstream versions, checksums, reproducible inputs, licenses, provenance, SBOM changes, and simulator/device validation.
