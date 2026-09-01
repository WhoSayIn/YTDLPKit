# Security and Privacy

Extracted media URLs and their associated HTTP headers can contain signed,
short-lived bearer values. Never log or persist them. Re-extract when they
expire.

YTDLPKit sanitizes public errors and log events before invoking the configured
handler. URL query strings, cookies, authorization headers, credentials, raw
Python tracebacks, and sensitive local paths are not part of its diagnostic API.

The bundled runtime and yt-dlp resources are pinned. YTDLPKit does not download
executable code or run yt-dlp self-update. A local custom module is trusted code
and must be explicitly selected and hash-validated before runtime initialization.

For the complete threat model, see `Documentation/Security.md` in the repository.
