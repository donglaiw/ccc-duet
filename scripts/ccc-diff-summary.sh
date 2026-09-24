#!/usr/bin/env bash
set -euo pipefail

# Budgeted diff for CCC code-review prompts. The budget counts raw diff bytes.
# Under it, every file's full diff is emitted. Over it, source and test files are
# still always emitted in full; docs and generated/lock files are expanded
# smallest first while the budget allows, and binaries never. Everything not
# expanded becomes one summary entry (stats + hunk headers) that the reviewer
# must expand with NEED or waive with SKIP. Output is in path order.
#
#   ccc-diff-summary.sh <repo_root> <output_folder> <base> --auto [--budget BYTES]
#   ccc-diff-summary.sh <repo_root> <output_folder> <base> --hunks <json-path>...
#
# <base> is run_start_ref (HEAD sha or the empty-tree sha). The diff is the
# working tree against <base>, tracked and untracked, excluding <output_folder>.
# CCC_REVIEW_SOURCE_GLOBS forces matching paths to class=source.

if [ "$#" -lt 4 ]; then
  echo "usage: ccc-diff-summary.sh <repo_root> <output_folder> <base> --auto [--budget BYTES] | --hunks <json-path>..." >&2
  exit 2
fi

python3 - "$@" <<'PY'
import fnmatch, json, os, re, subprocess, sys

repo, output, base, mode, *rest = sys.argv[1:]
if mode not in ("--auto", "--hunks"):
    print(f"invalid mode: {mode}", file=sys.stderr); sys.exit(2)

budget = 60000
if mode == "--auto":
    if rest[:1] == ["--budget"] and len(rest) == 2 and re.fullmatch(r"[1-9][0-9]*", rest[1]):
        budget = int(rest[1])
    elif rest:
        print("--auto takes only --budget <positive integer>", file=sys.stderr); sys.exit(2)
elif not rest:
    print("--hunks needs at least one json-path", file=sys.stderr); sys.exit(2)

def git(*args, ok=(0,)):
    proc = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if proc.returncode not in ok:
        sys.stderr.write(proc.stderr.decode(errors="replace"))
        sys.exit(1)
    return proc.stdout

repo_abs = os.path.abspath(repo)
try:
    out_rel = os.path.relpath(os.path.abspath(output), repo_abs)
except ValueError:
    out_rel = None
inside = out_rel is not None and not out_rel.startswith("..") and out_rel != "."
spec = ["--", "."] + ([f":(exclude){out_rel}"] if inside else [])
out_prefix = os.fsencode(out_rel.rstrip("/") + "/") if inside else None

# Tracked changes: name-status + numstat, NUL-separated so any filename is safe.
files = {}  # path bytes -> dict
ns = git("diff", "--no-color", "--no-renames", "--name-status", "-z", base, *spec).split(b"\0")
i = 0
while i + 1 < len(ns):
    status, path = ns[i].decode(), ns[i + 1]
    files[path] = {"status": status, "tracked": True}
    i += 2
num = git("diff", "--no-color", "--no-renames", "--numstat", "-z", base, *spec).split(b"\0")
for rec in num:
    if not rec:
        continue
    add, dele, path = rec.split(b"\t", 2)
    if path in files:
        files[path]["add"], files[path]["del"] = add.decode(), dele.decode()

# Untracked, non-ignored files count as additions.
for path in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
    if not path or (out_prefix and (path + b"/").startswith(out_prefix)):
        continue
    files[path] = {"status": "??", "tracked": False}

def display(path):
    return json.dumps(os.fsdecode(path), ensure_ascii=True)

def file_diff(path):
    if files[path]["tracked"]:
        return git("diff", "--no-color", "--no-renames", base, "--", os.fsdecode(path))
    # exit 1 means "differs" for --no-index; anything else is a failure.
    return git("diff", "--no-color", "--no-index", "--", "/dev/null", os.fsdecode(path), ok=(0, 1))

LOCK = {b"package-lock.json", b"yarn.lock", b"pnpm-lock.yaml", b"poetry.lock", b"uv.lock",
        b"Cargo.lock", b"go.sum", b"Gemfile.lock", b"composer.lock", b"Pipfile.lock"}
GEN_DIRS = (b"vendor/", b"node_modules/", b"dist/", b"build/", b"third_party/", b"__generated__/")
DOC_EXT = (b".md", b".rst", b".adoc")

# Repos where Markdown or config is the product can force paths to class=source:
# CCC_REVIEW_SOURCE_GLOBS="protocol/*:skills/*/SKILL.md" (fnmatch, ':'-separated).
SOURCE_GLOBS = [g for g in os.environ.get("CCC_REVIEW_SOURCE_GLOBS", "").split(":") if g]

def classify(path, diff):
    name = os.path.basename(path)
    if any(fnmatch.fnmatchcase(os.fsdecode(path), g) for g in SOURCE_GLOBS):
        return (4, "binary") if b"GIT binary patch" in diff or b"\nBinary files " in b"\n" + diff else (0, "source")
    low = path.lower()
    if b"\nBinary files " in b"\n" + diff or b"GIT binary patch" in diff:
        return 4, "binary"
    if name in LOCK or low.endswith((b".min.js", b".min.css", b".map", b".snap")) \
            or any(low.startswith(d) or (b"/" + d) in low for d in GEN_DIRS):
        return 3, "generated"
    if low.endswith(DOC_EXT) or low.startswith(b"docs/"):
        return 2, "docs"
    if re.search(rb"(^|/)(tests?|spec|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$", low):
        return 1, "test"
    return 0, "source"

records = []
for path in sorted(files):
    diff = file_diff(path)
    tier, cls = classify(path, diff)
    rec = files[path]
    if not rec["tracked"]:
        lines = diff.count(b"\n+") - 1 if diff else 0
        rec["add"], rec["del"] = (str(max(lines, 0)), "0") if cls != "binary" else ("-", "-")
    records.append({"path": path, "diff": diff, "tier": tier, "cls": cls, **rec})

def header(r, state):
    return (f"=== file {state} {r['status']} {display(r['path'])} "
            f"+{r.get('add', '?')} -{r.get('del', '?')} bytes={len(r['diff'])} class={r['cls']}")

def emit_full(r):
    sys.stdout.write(header(r, "full") + "\n")
    sys.stdout.flush()
    sys.stdout.buffer.write(r["diff"])
    if r["diff"] and not r["diff"].endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.flush()

def emit_summary(r, max_hunks=20):
    sys.stdout.write(header(r, "summary") + "\n")
    hunks = [l for l in r["diff"].split(b"\n") if l.startswith(b"@@")]
    for h in hunks[:max_hunks]:
        sys.stdout.write("  " + h.decode("utf-8", errors="replace") + "\n")
    if len(hunks) > max_hunks:
        sys.stdout.write(f"  ... {len(hunks) - max_hunks} more hunks\n")

if mode == "--hunks":
    by_display = {display(r["path"]): r for r in records}
    for want in rest:
        r = by_display.get(want)
        if r is None:
            print(f"unknown path: {want}", file=sys.stderr); sys.exit(2)
        emit_full(r)
    sys.exit(0)

total = sum(len(r["diff"]) for r in records)
if total <= budget:
    print(f"diff_mode: full files={len(records)} bytes={total} budget={budget}")
    for r in records:
        emit_full(r)
    sys.exit(0)

# Over budget: source and test are never summarized, whatever their size.
# Docs, then generated/lock files, fill the remaining budget smallest first.
# Binary files are never expanded.
expanded = {r["path"] for r in records if r["cls"] in ("source", "test")}
spent = sum(len(r["diff"]) for r in records if r["path"] in expanded)
for r in sorted(records, key=lambda r: (r["tier"], len(r["diff"]), r["path"])):
    if r["cls"] in ("docs", "generated") and spent + len(r["diff"]) <= budget:
        expanded.add(r["path"]); spent += len(r["diff"])
summarized = [r for r in records if r["path"] not in expanded]
print(f"diff_mode: tiered files={len(records)} bytes={total} budget={budget} "
      f"full={len(expanded)} summarized={len(summarized)}")
for r in records:
    if r["path"] in expanded:
        emit_full(r)
for r in records:
    if r["path"] not in expanded:
        emit_summary(r)
PY
