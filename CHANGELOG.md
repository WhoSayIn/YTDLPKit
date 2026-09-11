# Changelog

All notable changes to YTDLPKit will be documented here. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.1.2 - 2026-09-11

- Reuse the process-wide SHA-256-validated embedded resource layout across clients while preserving first-use validation and module identity mismatch rejection.

## 0.1.1 - 2026-09-08

- Expose typed media chapters and tolerate malformed individual chapter entries.

## 0.1.0 - 2026-09-02

- Add the initial Swift 6 actor API for metadata extraction and search.
- Embed a reproducibly packaged CPython 3.13 runtime and pinned yt-dlp module.
- Add typed metadata models, format selection, cancellation, redacted logging,
  fixture tests, simulator runtime tests, and opt-in live integration tests.
