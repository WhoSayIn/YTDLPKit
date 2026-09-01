# Architecture

YTDLPKit is a Swift API boundary around a pinned Python runtime and yt-dlp. Its
architecture deliberately makes the difficult integration private so an app
links one SwiftPM product and imports one Swift module.

## Layers

1. The public Swift layer defines immutable `Sendable` request, result, log,
   and error values. It contains no Python types.
2. `YTDLPClient`, a public actor, owns one private runtime coordinator. All
   initialization and calls enter through this isolation boundary.
3. A private bridge constructs a new yt-dlp options dictionary per operation,
   invokes yt-dlp directly in process, sanitizes the result, serializes it to
   JSON, and releases Python values before returning.
4. Swift decoders validate the JSON into bounded public models, including
   checked `formats` and nested `requested_formats` data.
5. Private SwiftPM binary and resource targets provide the Python runtime,
   standard library, pinned yt-dlp module, and challenge provider.

Consumers do not configure Python paths, invoke build scripts, or use a Python
bridge. The private bridge calls CPython's C API directly. There is no public
singleton and no process-wide stdout or stderr redirection.

## Concurrency and initialization

Each client is an actor, while the embedded Python interpreter is process-wide.
A private coordinator deterministically initializes it once and rejects a later
incompatible runtime configuration. Python execution uses one serial executor
that does not run on the main actor. This provides a single ownership point for
Python's global interpreter state while allowing concurrent Swift callers to
suspend safely.

Cancellation is checked before scheduling, from a thread-safe yt-dlp progress
hook where upstream execution permits it, and after Python returns. A cancelled
task can still wait briefly for an upstream operation that cannot be safely
interrupted. Configured socket and operation timeouts bound that case.

## Extraction path

For each request, the bridge:

1. Validates the URL or search request and timeout bounds.
2. Creates a fresh, metadata-only options dictionary.
3. Installs a request-local logging and cancellation bridge.
4. Calls `YoutubeDL.extract_info(download: false)` directly.
5. Uses `YoutubeDL.sanitize_info` and JSON serialization.
6. Discards Python values and decodes Swift result types.
7. Redacts errors and emits only sanitized log fields.

Downloads, post-processors, external downloaders, FFmpeg, transcoding, muxing,
and AVPlayer integration are rejected or absent in version 1. The library does
not launch a yt-dlp executable. A subprocess-shaped empty-stdout fixture is
kept solely to prevent regression in error mapping.

## Runtime selection

The default module is a pinned pure-Python yt-dlp distribution shipped as a
package resource. An advanced caller may select a local module URL and expected
SHA-256 before the first runtime initialization. Validation checks:

- The URL is a local file with an allowed type and canonical path.
- The resolved path stays inside the explicitly allowed local container.
- File size is within a conservative limit.
- The complete file matches the caller-provided SHA-256.
- Python can import it without modifying unrelated search paths.
- Its version and required API surface are compatible with this YTDLPKit build.

Selection is immutable after initialization. A custom module is trusted code;
the digest establishes identity, not safety. Network-delivered modules,
self-update, and downloaded executable code are unsupported.

## Data lifetime

`MediaInfo` is an in-memory extraction result, not a persistence schema. Stream
URLs can be signed and expire without notice. Apps should select and consume a
format promptly, then discard the URL. Stable metadata such as an extractor ID
may be persisted by an app, but YTDLPKit provides no storage layer and makes no
promise that an extracted URL remains valid.

## Runtime artifact boundary

The repository vendors private XCFramework binary targets for supported iOS
device and Simulator architectures plus the required standard-library
resources. Exact source revisions, checksums, license texts, SBOM, and
provenance accompany them. Consumers resolve these through the single public
`YTDLPKit` product and run no build scripts. Runtime build mechanics are
documented separately from this library architecture.

## Non-goals

- Application UI or lifecycle management
- Playback and queueing
- Persistent models or caches
- Authentication-cookie storage
- Media downloads or post-processing
- A general-purpose Python API
- Compatibility guarantees for arbitrary yt-dlp forks
