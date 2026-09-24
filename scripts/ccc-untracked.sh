#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repo root required}
output=${2:?output folder required}
mode=${3:?--prompt or --manifest required}
[ "$mode" = --prompt ] || [ "$mode" = --manifest ] || { echo "invalid mode: $mode" >&2; exit 2; }

python3 - "$repo" "$output" "$mode" <<'PY'
import hashlib, json, os, stat, subprocess, sys

repo, output, mode = sys.argv[1:]
try:
    raw = subprocess.check_output(
        ["git", "-C", repo, "ls-files", "--others", "--exclude-standard", "-z"])
except subprocess.CalledProcessError as exc:
    raise SystemExit(exc.returncode or 1)

repo_b = os.fsencode(os.path.abspath(repo))
out_b = os.fsencode(os.path.abspath(output))
try:
    out_rel = os.path.relpath(out_b, repo_b)
except ValueError:
    out_rel = None
out_prefix = out_rel not in (None, b".") and out_rel.rstrip(b"/") + b"/"

paths = []
for path in raw.split(b"\0"):
    if not path:
        continue
    if out_prefix and (path == out_rel or path.startswith(out_prefix)):
        continue
    paths.append(path)
paths.sort()

def display(path):
    return json.dumps(os.fsdecode(path), ensure_ascii=True)

def inspect(path):
    full = os.path.join(repo_b, path)
    st = os.lstat(full)
    mode_octal = format(st.st_mode, "o")
    if stat.S_ISLNK(st.st_mode):
        target = os.readlink(full)
        target_b = os.fsencode(target)
        return hashlib.sha256(target_b).hexdigest(), st.st_size, mode_octal, "symlink", target
    if not stat.S_ISREG(st.st_mode):
        return None, st.st_size, mode_octal, "other", None
    with open(full, "rb") as fh:
        data = fh.read()
    digest = hashlib.sha256(data).hexdigest()
    kind = "binary" if b"\0" in data[:8000] else "text"
    if kind == "text":
        try:
            data.decode("utf-8")
        except UnicodeDecodeError:
            kind = "binary"
    return digest, len(data), mode_octal, kind, data

records = []
for path in paths:
    records.append((path, *inspect(path)))

if mode == "--manifest":
    for path, digest, size, mode_octal, kind, _ in records:
        print(f"{digest or '-'} {size} {mode_octal} {kind} {display(path)}")
else:
    print(f"untracked_count: {len(records)}")
    for path, digest, size, mode_octal, kind, value in records:
        print(f"=== untracked {kind} {display(path)} bytes={size} sha256={digest or '-'}")
        if kind == "text":
            text = value.decode("utf-8")
            for line in text.splitlines():
                print("+" + line)
            if not text.endswith(("\n", "\r")):
                print("=== missing-final-newline")
            print("=== end")
        elif kind == "symlink":
            print(f"target={display(value)}")
PY
