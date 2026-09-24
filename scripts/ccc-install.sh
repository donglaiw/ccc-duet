#!/usr/bin/env bash
set -euo pipefail

# Install the five CCC skills so each installed skill dir carries the protocol
# and scripts it references. Without this, `<CCC_HOME>/protocol/CCC_PROTOCOL.md`
# does not resolve from an installed skill.

CCC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS=(ccc ccc-plan ccc-plan-review ccc-code ccc-code-review)
DEST="${HOME}/.claude/skills"
MODE="link"
FORCE=0
CAVEMAN=1
CAVEMAN_SRC=""

# Optional caveman style skill (opt-in per run via caveman=lite|full|ultra).
# Pinned by commit and SHA-256; bump all three together after reviewing upstream.
CAVEMAN_REPO="JuliusBrussee/caveman"
CAVEMAN_REF="2fd153c67988e980fb0b2455c90832159a6a5a25"
CAVEMAN_SHA256="0bf09a0a9a017d004a81d4b693e5a2d830e1a28230a5885df773e1ed9c0571cc"
CAVEMAN_URL="https://raw.githubusercontent.com/${CAVEMAN_REPO}/${CAVEMAN_REF}/skills/caveman/SKILL.md"

usage() {
  cat <<'USAGE'
Usage: ccc-install.sh [--dest DIR] [--link|--copy] [--force] [--no-caveman] [--caveman-src FILE]

  --dest DIR   skills directory to install into (default: ~/.claude/skills)
  --link       symlink each skill to this checkout, so edits take effect
               immediately and protocol/scripts resolve through the checkout
               (default)
  --copy       copy each skill, dereferencing the bundled protocol/ and
               scripts/ into real files, for a checkout-independent install
  --force      replace existing entries at the destination
  --no-caveman skip installing the pinned caveman skill
  --caveman-src FILE
               install caveman from a local SKILL.md instead of downloading
               (offline installs); the pinned SHA-256 is still enforced
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest) [ "$#" -ge 2 ] || { echo "ccc-install: --dest needs a directory" >&2; exit 2; }
            DEST="$2"; shift 2 ;;
    --link) MODE="link"; shift ;;
    --copy) MODE="copy"; shift ;;
    --force) FORCE=1; shift ;;
    --no-caveman) CAVEMAN=0; shift ;;
    --caveman-src) [ "$#" -ge 2 ] || { echo "ccc-install: --caveman-src needs a file" >&2; exit 2; }
                   CAVEMAN_SRC="$2"; CAVEMAN=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ccc-install: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -f "$CCC_ROOT/protocol/CCC_PROTOCOL.md" ] || {
  echo "ccc-install: not a ccc-duet checkout: $CCC_ROOT" >&2; exit 1; }

mkdir -p "$DEST"

for skill in "${SKILLS[@]}"; do
  src="$CCC_ROOT/skills/$skill"
  dst="$DEST/$skill"

  [ -f "$src/SKILL.md" ] || { echo "ccc-install: missing $src/SKILL.md" >&2; exit 1; }

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ "$FORCE" -eq 1 ]; then
      rm -rf "$dst"
    else
      echo "ccc-install: $dst exists; re-run with --force to replace" >&2
      exit 1
    fi
  fi

  case "$MODE" in
    link) ln -s "$src" "$dst" ;;
    copy) cp -RL "$src" "$dst" ;;
  esac
  echo "ccc-install: $MODE $skill -> $dst"
done

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# Caveman is optional for runs (default caveman=off), so a failed fetch warns
# instead of failing the CCC install.
install_caveman() {
  local dst="$DEST/caveman" pin="$DEST/caveman/.ccc-pin" tmp
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -f "$pin" ] && grep -qx "sha256: $CAVEMAN_SHA256" "$pin"; then
      echo "ccc-install: caveman already pinned at $CAVEMAN_REF -> $dst"; return 0
    fi
    if [ "$FORCE" -ne 1 ]; then
      echo "ccc-install: $dst exists and is not this pin; leaving it (use --force to replace)" >&2
      return 0
    fi
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/ccc-caveman.XXXXXX")"
  if [ -n "$CAVEMAN_SRC" ]; then
    cp "$CAVEMAN_SRC" "$tmp" || { rm -f "$tmp"; echo "ccc-install: cannot read $CAVEMAN_SRC" >&2; return 1; }
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$CAVEMAN_URL" -o "$tmp" || { rm -f "$tmp"; echo "ccc-install: caveman download failed: $CAVEMAN_URL" >&2; return 1; }
  else
    rm -f "$tmp"; echo "ccc-install: curl not found; cannot fetch caveman" >&2; return 1
  fi

  local got; got="$(sha256_of "$tmp")"
  if [ "$got" != "$CAVEMAN_SHA256" ]; then
    rm -f "$tmp"
    echo "ccc-install: caveman SHA-256 mismatch (got $got, want $CAVEMAN_SHA256); not installed" >&2
    return 1
  fi

  rm -rf "$dst"
  mkdir -p "$dst"
  mv "$tmp" "$dst/SKILL.md"
  chmod 644 "$dst/SKILL.md"
  printf 'repo: %s\nref: %s\nsha256: %s\nlicense: MIT (upstream skills/); see https://github.com/%s\n' \
    "$CAVEMAN_REPO" "$CAVEMAN_REF" "$CAVEMAN_SHA256" "$CAVEMAN_REPO" > "$pin"
  echo "ccc-install: caveman $CAVEMAN_REF -> $dst"
}

if [ "$CAVEMAN" -eq 1 ]; then
  install_caveman || echo "ccc-install: warning: caveman not installed; runs with caveman=lite|full|ultra will block (caveman=off is unaffected)" >&2
fi

echo
"$CCC_ROOT/scripts/ccc-check-install.sh" "$DEST"
