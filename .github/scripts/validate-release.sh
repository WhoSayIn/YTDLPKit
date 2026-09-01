#!/bin/bash
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Expected a semantic version such as 1.2.3 or 1.2.3-rc.1." >&2
  exit 1
fi

if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" != "v${version}" ]]; then
  echo "Tag ${GITHUB_REF_NAME:-<missing>} does not match v${version}." >&2
  exit 1
fi

placeholder_pattern='TO BE FINALIZED|TO BE PUBLISHED|PLACEHOLDER|example\.invalid|github\.com/OWNER/'
if rg -n "$placeholder_pattern" Package.swift THIRD_PARTY_NOTICES.md README.md; then
  echo "Release metadata still contains publication placeholders." >&2
  exit 1
fi

required_files=(
  LICENSE
  THIRD_PARTY_NOTICES.md
  SECURITY.md
  README.md
  CHANGELOG.md
  Documentation/Architecture.md
  Documentation/Compatibility.md
  Documentation/Security.md
  Documentation/Releasing.md
)

for file in "${required_files[@]}"; do
  if [[ ! -s "$file" ]]; then
    echo "Required release file is missing or empty: $file" >&2
    exit 1
  fi
done

if rg -n 'https://(www\.)?(youtube\.com|youtu\.be)/[^ ]*[?&](sig|signature|token|expire)=' Tests Sources Documentation README.md; then
  echo "A committed source, fixture, or document appears to contain a signed production URL." >&2
  exit 1
fi

python3 - <<'PY'
import json
from pathlib import Path

manifest = json.loads(Path("Runtime/ArtifactManifest.json").read_text())
signing = manifest.get("signing", {})
if signing.get("mode") != "signed" or signing.get("identity") in (None, "", "-"):
    raise SystemExit(
        "Release runtime is not signed with the maintainer's stable distribution identity."
    )
PY

echo "Release metadata validated for ${version}."
