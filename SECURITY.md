# Security policy

## Supported versions

Security fixes are provided for the latest released minor version. Before the
first stable release, fixes are made on the default branch only.

## Reporting a vulnerability

Do not open a public issue for suspected vulnerabilities. Use GitHub's private
security-advisory reporting flow for the repository. Include the affected
version, impact, reproduction steps, and whether sensitive output was exposed.
Do not include real cookies, credentials, authorization headers, or signed
media URLs; redact them or use synthetic values.

Maintainers will acknowledge a report when it is received, assess severity,
coordinate a fix and disclosure, and credit the reporter if requested. No
specific response time is promised while the project is volunteer-maintained.

## Security boundaries

- Extracted media URLs may grant temporary access and must be treated as
  secrets. YTDLPKit does not provide persistence for them.
- The bundled runtime and yt-dlp resources are pinned and verified during the
  release process. Runtime self-update and executable-code download are not
  supported.
- A caller-selected local yt-dlp module is trusted code. It is accepted only
  before runtime initialization and after structural, digest, import, version,
  and compatibility checks.
- Network responses and Python output are untrusted. They are decoded into
  bounded Swift value types and sanitized before logging or error reporting.
- YTDLPKit does not accept or manage account cookies in version 1.

See `Documentation/Security.md` for the detailed threat model.
