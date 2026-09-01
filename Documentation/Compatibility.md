# Compatibility

| YTDLPKit | Swift | Xcode | iOS | CPython | yt-dlp |
| --- | --- | --- | --- | --- | --- |
| Unreleased | 6 | 16 or later | 16 or later | 3.13.14 | 2026.08.19 |

The package is iOS-first. Its public models can compile on macOS 13 or later so
fixture tests and tooling can run on a host Mac, but the embedded extraction
runtime is available only in iOS application and XCTest processes.

