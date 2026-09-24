#!/usr/bin/env bash
set -euo pipefail

protocol=${1:?protocol path required}
shift
[ "$#" -gt 0 ] || { echo "section name required" >&2; exit 2; }
[ -f "$protocol" ] || { echo "protocol not found: $protocol" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  sha=$(sha256sum "$protocol" | awk '{print $1}')
else
  sha=$(shasum -a 256 "$protocol" | awk '{print $1}')
fi
printf 'protocol_sha256: %s\n' "$sha"

for wanted in "$@"; do
  awk -v wanted="## $wanted" '
    /^```/ { fenced = !fenced }
    !fenced && $0 == wanted { found=1; print; next }
    found && !fenced && /^## / { exit }
    found { print }
    END { if (!found) exit 2 }
  ' "$protocol" || exit 2
done
