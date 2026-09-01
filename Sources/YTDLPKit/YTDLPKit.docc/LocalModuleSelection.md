# Local Module Selection

The bundled yt-dlp module is the supported default. An advanced application may
select a local module URL and expected SHA-256 in its configuration before the
first client initializes Python.

The module must be a local regular file inside the configured container, satisfy
the size limit, match its complete SHA-256 digest, import successfully, report a
compatible version, and provide the required API surface. Selection cannot
change after runtime initialization.

Hash validation proves which bytes were selected; it does not make untrusted
Python safe. The module executes with the application's privileges. Never fetch
or activate a module as part of a background update, remote-config change, or
server response.
