# Incompatible yt-dlp fixture

`incompatible-ytdlp.zip` is a network-free, stored ZIP with three UTF-8 entries,
each dated 2026-01-01 00:00:00:

- `yt_dlp/__init__.py`: `class YoutubeDL:\n    pass\n`
- `yt_dlp/version.py`: `__version__ = '2026.01.01'\n`
- `yt_dlp/dependencies.py`: `certifi = object()\n`

Imports succeed, but `YoutubeDL.sanitize_info` is deliberately missing. The
production bootstrap must raise its API-compatibility error after CPython has
started. The test copies this archive into its container and hashes its exact
bytes, exercising normal local-module validation before invoking the bridge.

The dedicated test target has one test and must run in a separate process from
the successful embedded-runtime smoke test. Do not add a reset hook: failure
is intentionally terminal for the interpreter's process lifetime.
