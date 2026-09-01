# YTDLPKit

YTDLPKit is an iOS-first Swift 6 package for extracting media metadata with
yt-dlp. It exposes a small, typed, concurrency-safe Swift API while keeping
Python and yt-dlp implementation details private.

> [!IMPORTANT]
> YTDLPKit is under active development. The repository contains the Swift API,
> embedded CPython runtime, pinned Python resources, fixtures, and reproducible
> runtime build tooling. Use a local checkout for development; no public release
> has been published.

## Scope

Version 1 provides metadata extraction and search. It does not download,
transcode, mux, play, or persist media. It does not require consumer-installed
Python, FFmpeg, command-line tools, or build scripts.

## Requirements

- Swift 6
- Xcode 16 or later
- iOS 16 or later

## Installation

After the first functional release is approved and published, add this package
in Xcode using its GitHub URL and select the `YTDLPKit` product. The
corresponding package declaration will be:

```swift
.package(url: "https://github.com/WhoSayIn/YTDLPKit.git", from: "1.0.0")
```

Until publication is explicitly approved, add the repository as a local
package (`File > Add Package Dependencies > Add Local`) or use:

```swift
.package(path: "../YTDLPKit")
```

Consumers import one module:

```swift
import YTDLPKit
```

## Usage

```swift
import YTDLPKit

let client = try YTDLPClient(configuration: .init())
let request = ExtractionRequest(
    url: URL(string: "https://www.youtube.com/watch?v=VIDEO_ID")!
)
let info = try await client.extract(request)

print(info.title)
for format in info.formats {
    print(format.id, format.height as Any)
}
```

Search returns the same immutable `MediaInfo` model:

```swift
let results = try await client.search("artist song", limit: 20)
```

`YTDLPClient` is an actor. It serializes Python initialization and Python API
access away from the main actor. Public result and error types are `Sendable`;
no Python object crosses the module boundary.

## Security and privacy

Media URLs returned by extractors are often signed, bearer-like, and temporary.
Treat them as secrets: use them only for the immediate operation, do not persist
them, and do not include them in telemetry, crash reports, or support logs.
YTDLPKit redacts URL queries, cookies, authorization data, and Python exception
payloads from public errors and logs.

The bundled yt-dlp module is pinned. Advanced consumers may select a local
module before runtime initialization, but it must pass containment, file type,
size, SHA-256, import, version, and API-compatibility validation. YTDLPKit never
downloads executable code or performs yt-dlp self-updates at runtime.

See [Architecture](Documentation/Architecture.md) and
[Security](Documentation/Security.md) for the complete trust model. Supported
toolchain and runtime combinations are listed in
[Compatibility](Documentation/Compatibility.md).

## App Store considerations

YTDLPKit is designed to be self-contained and to avoid downloading executable
code. Apple review policy, service terms, copyright law, and website behavior
can change, and inclusion of an interpreter or extractor does not guarantee App
Store approval. Application developers remain responsible for their content
sources, user permissions, permitted uses, disclosures, encryption export
compliance, and review submission. The embedded runtime links OpenSSL, so an app
must assess its own `ITSAppUsesNonExemptEncryption` declaration rather than
assuming the package is exempt.

YTDLPKit is an independent project and is not affiliated with or endorsed by
the yt-dlp project.

## Development

```sh
swift build
swift test
swift format lint --recursive --strict Sources Tests Examples
```

Normal tests use sanitized recorded fixtures and do not contact YouTube. Live
integration tests are opt-in and deliberately excluded from ordinary CI. See
[CONTRIBUTING.md](CONTRIBUTING.md) for local commands and contribution rules.

## Releases

YTDLPKit follows semantic versioning. Tags and GitHub releases are created only
after the runtime artifacts, checksums, notices, tests, DocC, and example app
have passed release validation. See [Release Process](Documentation/Releasing.md).

## License

YTDLPKit is available under the MIT License. Embedded and source dependencies
retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
