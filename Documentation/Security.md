# Security and privacy model

YTDLPKit handles untrusted network data and may return temporary access URLs.
Its default behavior minimizes what crosses the Python boundary and what can be
observed in logs.

## Sensitive values

Treat all of the following as secrets:

- Signed media and manifest URLs, including query parameters
- Cookies, authorization headers, and extractor credentials
- Local paths that expose a user's container layout
- Raw Python exceptions or yt-dlp diagnostic dumps that can embed requests

Public error descriptions and log events must not contain these values. URL
logging is limited to a normalized scheme/host or a redacted identifier where
needed. Sanitization is applied before invoking a caller's logging handler; the
handler never receives a rich object and is not relied upon to perform redaction.

## Temporary URL handling

Extracted URLs are bearer-like, often IP- or session-sensitive, and routinely
expire. Keep them in memory only for the immediate operation. Do not put them
in `UserDefaults`, databases, analytics, crash reports, screenshots, test
fixtures, or issue reports. Re-extract instead of retrying an old persisted URL.

The public result types are designed for predictable decoding and testing, not
as persistence schemas. Applications that create their own persisted model must
explicitly omit transient URL-bearing properties.

## Trusted computing base

The runtime XCFrameworks, Python standard library, private CPython C bridge,
yt-dlp module, JavaScript challenge provider, and their linked libraries execute
in the application process. Releases pin and hash these inputs and include their
provenance and licenses. Maintainers review upstream updates and do not accept
automatic dependency-update merges for binary runtime changes.

An advanced local yt-dlp module executes trusted code with the app's privileges.
Path, size, digest, import, version, and API checks prevent mistakes and
unexpected substitution; they cannot prove that selected code is benign.

## Network and resource limits

Requests use explicit timeouts. Decoding applies type and size expectations to
untrusted JSON. Each operation owns its options, logger, and cancellation state
so one caller cannot mutate another request. Python calls are serialized and do
not redirect process-wide file descriptors.

Metadata-only extraction avoids FFmpeg, external downloaders, post-processors,
and subprocess execution. It does not eliminate risks in Python, TLS, parsers,
website JavaScript, or the extractor itself; keep all pinned components current.

## Logs and errors

Logging is disabled unless a caller supplies a `@Sendable` handler. Events use
a small typed surface and pre-redacted strings. Errors expose a stable category,
safe context, and an underlying diagnostic code where appropriate, not raw
Python object representations.

Tests include known secret-shaped query parameters, cookies, authorization
headers, local paths, and Python tracebacks. Failures occur if those values
reach public descriptions or log callbacks.

## App Store and service policy

The package is built to be self-contained and never downloads executable code
at runtime. That design reduces one review concern but does not guarantee App
Store acceptance. Application behavior, content, entitlements, service terms,
and review policy remain the integrating developer's responsibility. yt-dlp
compatibility also does not grant permission to access, copy, or distribute
content. Because the embedded runtime links OpenSSL, integrating applications
must assess their own encryption export-compliance answers, including
`ITSAppUsesNonExemptEncryption`; YTDLPKit does not claim a blanket exemption.
See Apple's
[`ITSAppUsesNonExemptEncryption` documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

Report vulnerabilities through the private process in `SECURITY.md`.
