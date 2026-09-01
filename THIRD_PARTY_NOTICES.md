# Third-party notices

This file records the third-party components shipped by YTDLPKit. Complete
license texts are stored in `ThirdPartyLicenses/` and copied into the package
resource bundle under `Licenses/`.

YTDLPKit's MIT License applies only to original YTDLPKit source. The following
components retain their respective licenses.

## CPython

- Project: Python
- License: Python Software Foundation License Version 2 and included notices
- Source: https://github.com/python/cpython
- Bundled version/commit: CPython 3.13.14
  (`fd17997c3866d61e0e7bd8201b1d8f35b40a40bd`) via support release `3.13-b14`
- Local license copy: `ThirdPartyLicenses/CPython-LICENSE.txt`

CPython includes or links separately licensed components. Their exact versions
are recorded below and their license texts accompany the repository and package
resource bundle.

## Python Apple support build tooling/runtime

- Project: Python Apple support / selected iOS runtime pipeline
- License: BSD-3-Clause where BeeWare Python Apple Support is used
- Source: https://github.com/beeware/Python-Apple-support
- Bundled version/commit: BeeWare support release `3.13-b14`
  (`54d8ab6ef4fbac4d60706f311a986aee5236c71b`)
- Local license copy: `ThirdPartyLicenses/Python-Apple-support-LICENSE`

The checked-in runtime is structurally repackaged from this pinned support
release by `Scripts/runtime`; no CPython source patches are applied.

## PythonKit evaluation

- Project: PythonKit
- License: Apache License 2.0
- Source: https://github.com/pvieito/PythonKit
- Bundled version/commit: not bundled

PythonKit was evaluated for the private Swift/Python boundary but is not linked
or redistributed. YTDLPKit uses the public CPython embedding API through its
own small C bridge, avoiding a transitive PythonKit dependency and keeping
Python values out of the public Swift API.

## yt-dlp

- Project: yt-dlp
- License: The Unlicense, with separately licensed bundled components and
  notices as identified by the selected upstream release
- Source: https://github.com/yt-dlp/yt-dlp
- Bundled version/commit: `2026.08.19`
- Bundled resource SHA-256:
  `1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6`
- Local license and notice copies: `ThirdPartyLicenses/yt-dlp-LICENSE` and
  `ThirdPartyLicenses/yt-dlp-THIRD_PARTY_LICENSES.txt`

## yt-dlp Apple WebKit JavaScript challenge provider

- Project: yt-dlp-apple-webkit-jsi
- License: Apache License 2.0
- Source: https://github.com/grqz/yt-dlp-apple-webkit-jsi
- Bundled version/commit: `0.1.1`
  (`e466daca67cc0e1ca63b68cb8fbe80af16ce00a4`)
- Bundled resource SHA-256:
  `6b8267091d45410cdadbc1fe3d1fe5cdb9ed9de0420489790ba1fcc570c81821`
- Local license copy: `ThirdPartyLicenses/yt-dlp-apple-webkit-jsi-LICENSE`

## Binary runtime dependencies

The pinned BeeWare support artifact also contains the following CPython runtime
dependencies. Exact build revisions are recorded in `Runtime/runtime-lock.json`
and the generated SPDX SBOM.

- BZip2 1.0.8-2 — bzip2 license — `ThirdPartyLicenses/bzip2-LICENSE`
- libffi 3.4.7-2 — MIT — `ThirdPartyLicenses/libffi-LICENSE`
- mpdecimal 4.0.0-2 — BSD-2-Clause — `ThirdPartyLicenses/mpdecimal-COPYRIGHT.txt`
- OpenSSL 3.0.18-1 — Apache-2.0 — `ThirdPartyLicenses/OpenSSL-LICENSE.txt`
- Expat 2.8.1 — MIT — CPython's pinned `Modules/expat` copy —
  `ThirdPartyLicenses/Expat-COPYING`
- XZ 5.6.4-2 — mixed public-domain, 0BSD, GPL, and LGPL notices —
  `ThirdPartyLicenses/XZ-COPYING*`

The generated SPDX inventory and build provenance are stored under `Runtime/`.
