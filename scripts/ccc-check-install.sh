#!/usr/bin/env bash
set -euo pipefail

# Verify that every CCC skill can reach the protocol and scripts it references.
# Default target is this checkout's skills/; pass a directory to check an
# install (for example ~/.claude/skills).

CCC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$CCC_ROOT/skills}"
SKILLS=(ccc ccc-plan ccc-plan-review ccc-code ccc-code-review)
REQUIRED_SCRIPTS=(ccc-detect-session.sh ccc-check-agent-cli.sh ccc-validate.sh ccc-install.sh ccc-check-install.sh ccc-protocol-sections.sh ccc-untracked.sh ccc-diff-summary.sh)
errors=0

err() { echo "ccc-check-install: $*" >&2; errors=$((errors + 1)); }

[ -d "$TARGET" ] || { err "no such skills directory: $TARGET"; exit 1; }

for skill in "${SKILLS[@]}"; do
  dir="$TARGET/$skill"

  [ -d "$dir" ] || { err "$skill: not installed at $dir"; continue; }
  [ -f "$dir/SKILL.md" ] || err "$skill: missing SKILL.md"

  # The protocol must resolve from the skill's own directory. This is the
  # contract every SKILL.md relies on.
  if [ -s "$dir/protocol/CCC_PROTOCOL.md" ]; then
    grep -q '^# CCC Protocol$' "$dir/protocol/CCC_PROTOCOL.md" \
      || err "$skill: protocol/CCC_PROTOCOL.md is not the CCC protocol"
  else
    err "$skill: protocol/CCC_PROTOCOL.md does not resolve from $dir"
  fi

  for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -s "$dir/scripts/$script" ]; then
      bash -n "$dir/scripts/$script" || err "$skill: scripts/$script has a syntax error"
    else
      err "$skill: scripts/$script does not resolve from $dir"
    fi
  done

  # Every SKILL.md must state how to resolve <CCC_HOME>, and must not use a
  # bare `protocol/...` or `scripts/...` path outside that block: bare paths
  # resolve against the target repository at run time, not against CCC.
  if [ -f "$dir/SKILL.md" ]; then
    grep -q '^## CCC Home$' "$dir/SKILL.md" || err "$skill: SKILL.md has no ## CCC Home block"
    grep -q 'CCC_HOME' "$dir/SKILL.md" || err "$skill: SKILL.md never mentions CCC_HOME"

    stray="$(awk '
      /^## CCC Home$/ { skip = 1; next }
      /^## / { skip = 0 }
      !skip
    ' "$dir/SKILL.md" | grep -nE '`(protocol|scripts)/' || true)"

    if [ -n "$stray" ]; then
      printf '%s\n' "$stray" >&2
      err "$skill: SKILL.md uses a bare protocol/ or scripts/ path; use <CCC_HOME>/"
    fi
  fi
done

# Caveman is optional (runs default to caveman=off). Report it; a pinned copy
# whose bytes no longer match its pin is an error.
cave="$TARGET/caveman"
if [ -f "$cave/SKILL.md" ]; then
  if [ -f "$cave/.ccc-pin" ]; then
    want="$(awk '/^sha256: /{print $2}' "$cave/.ccc-pin")"
    if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$cave/SKILL.md" | awk '{print $1}')"
    else got="$(shasum -a 256 "$cave/SKILL.md" | awk '{print $1}')"; fi
    [ "$got" = "$want" ] || err "caveman: SKILL.md does not match .ccc-pin sha256"
    echo "caveman: pinned $(awk '/^ref: /{print $2}' "$cave/.ccc-pin")"
  else
    echo "caveman: present (not installed by CCC; unpinned)"
  fi
else
  echo "caveman: not installed (optional; needed only for caveman=lite|full|ultra)"
fi

if [ "$errors" -ne 0 ]; then
  echo "ccc-check-install: $errors problem(s) in $TARGET" >&2
  exit 1
fi

echo "CCC install valid: $TARGET"
