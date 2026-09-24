#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: ccc-validate.sh <ccc-run-folder>" >&2
  exit 2
fi

python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

RUN = Path(sys.argv[1])
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
VERDICT_RE = re.compile(r"^VERDICT: (APPROVE|APPROVE_WITH_MINOR_COMMENTS|APPROVE_AUTO_OVERRIDE|NEEDS_CHANGES|BLOCKER)$")
VERSION = r"(?:0|[1-9][0-9]*)"
STAGE_RE = re.compile(rf"^(?:plan_v{VERSION}|plan_v{VERSION}_review|code_v{VERSION}|review_v{VERSION})$")

CONTRACTS = {
    "plan": [
        "Summary",
        "Scope",
        "Proposed Changes",
        "Files and Areas",
        "Verification Plan",
        "Risks and Questions",
        "Changes Since Previous Plan Version",
    ],
    "plan_review": ["Summary", "Findings", "Questions", "Verdict"],
    "code": [
        "Overview",
        "What Changed",
        "Implementation Details",
        "Files Changed",
        "Git Baseline",
        "Verification",
        "Review Focus",
        "Risks and Unknowns",
        "Changes Since Previous Code Version",
    ],
    "review": ["Summary", "Diff Baseline", "Findings", "Tests to Add", "Questions", "Verdict"],
}

STATUS_VALUES = {"active", "complete", "blocked", "canceled"}
VERDICT_VALUES = {"APPROVE", "APPROVE_WITH_MINOR_COMMENTS", "APPROVE_AUTO_OVERRIDE", "NEEDS_CHANGES", "BLOCKER", "none"}
TERMINAL_ACTIONS = {"complete", "blocked", "canceled"}

errors = []


def err(message: str) -> None:
    errors.append(message)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        err(f"missing file: {path}")
        return ""


def section(text: str, name: str) -> str:
    pattern = re.compile(rf"^## {re.escape(name)}\n(?P<body>.*?)(?=^## |\Z)", re.M | re.S)
    match = pattern.search(text)
    return match.group("body").strip() if match else ""


def require_sections(path: Path, text: str, names) -> None:
    for name in names:
        if not re.search(rf"^## {re.escape(name)}$", text, re.M):
            err(f"{path}: missing section ## {name}")


def key_values(body: str) -> dict:
    values = {}
    for line in body.splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip()
    return values


def non_empty_section(path: Path, text: str, name: str) -> str:
    body = section(text, name)
    if not body:
        err(f"{path}: section ## {name} is empty")
    return body


def parse_run_md() -> tuple[str, str, dict]:
    run_md = RUN / "run.md"
    text = read(run_md)
    if not text:
        return "", "", {}

    if text.count("# CCC Run") != 1:
        err("run.md: expected exactly one '# CCC Run' heading")

    require_sections(
        run_md,
        text,
        ["Description", "Runtime", "Rounds", "Task Summary", "Git Baseline", "Workflow State", "Status"],
    )

    runtime = key_values(section(text, "Runtime"))
    planner = runtime.get("planner")
    coder = runtime.get("coder")
    plan_code = runtime.get("plan_code")
    session_detected = runtime.get("session_detected")
    plan_code_source = runtime.get("plan_code_source")
    agents = {"claude", "codex"}
    if planner not in agents:
        err("run.md: Runtime planner must be claude or codex")
    if coder not in agents:
        err("run.md: Runtime coder must be claude or codex")
    if planner in agents and coder in agents:
        expected_plan_code = f"{planner}-{coder}"
        if plan_code != expected_plan_code:
            err(f"run.md: Runtime plan_code must be {expected_plan_code}")
    if plan_code not in {"claude-codex", "codex-claude", "claude-claude", "codex-codex"}:
        err("run.md: Runtime plan_code has invalid value")
    if session_detected not in {"claude", "codex", "unknown"}:
        err("run.md: Runtime session_detected must be claude, codex, or unknown")
    if plan_code_source not in {"explicit", "env", "default", "persisted"}:
        err("run.md: Runtime plan_code_source must be explicit, env, default, or persisted")
    caveman = runtime.get("caveman")
    caveman_source = runtime.get("caveman_source")
    if caveman is not None:
        if caveman not in {"off", "lite", "full", "ultra"}:
            err("run.md: Runtime caveman must be off, lite, full, or ultra")
        if caveman_source not in {"explicit", "env", "default", "persisted"}:
            err("run.md: Runtime caveman_source must be explicit, env, default, or persisted")
    elif caveman_source is not None:
        err("run.md: Runtime caveman_source requires caveman")

    rounds = key_values(section(text, "Rounds"))
    for key in ("plan_rounds", "revision_rounds"):
        value = rounds.get(key)
        if not value or not re.fullmatch(r"0|[1-9][0-9]*", value):
            err(f"run.md: Rounds must contain {key}: <non-negative integer without leading zero>")

    baseline = key_values(section(text, "Git Baseline"))
    run_start_ref = baseline.get("run_start_ref", "")
    if not SHA_RE.fullmatch(run_start_ref):
        err("run.md: Git Baseline run_start_ref must be a 40-char lowercase hex SHA")

    if baseline.get("run_start_ref_kind") not in {"head", "empty_tree"}:
        err("run.md: Git Baseline run_start_ref_kind must be head or empty_tree")

    if baseline.get("run_start_ref_kind") == "empty_tree" and run_start_ref != EMPTY_TREE:
        err("run.md: empty_tree baseline must use the Git empty-tree SHA")

    for key in ("run_start_status_file", "run_start_unstaged_diff", "run_start_staged_diff"):
        rel = baseline.get(key)
        if not rel:
            err(f"run.md: Git Baseline missing {key}")
        elif not (RUN / rel).exists():
            err(f"run.md: Git Baseline {key} points to missing file {rel}")

    workflow = key_values(section(text, "Workflow State"))
    current_stage = workflow.get("current_stage")
    if current_stage != "none" and not (current_stage and STAGE_RE.fullmatch(current_stage)):
        err("run.md: Workflow State current_stage must be none or a valid stage")

    latest_verdict = workflow.get("latest_verdict")
    if latest_verdict not in VERDICT_VALUES:
        err("run.md: Workflow State latest_verdict has invalid value")

    latest_artifact = workflow.get("latest_artifact")
    if latest_artifact and latest_artifact != "none" and not (RUN / latest_artifact).exists():
        err(f"run.md: latest_artifact points to missing file {latest_artifact}")

    next_action = workflow.get("next_action", "")
    if next_action not in TERMINAL_ACTIONS and not STAGE_RE.fullmatch(next_action):
        err("run.md: Workflow State next_action must be a valid stage or terminal action")

    status_lines = [line.strip() for line in section(text, "Status").splitlines() if line.strip()]
    if len(status_lines) != 1 or status_lines[0] not in STATUS_VALUES:
        err("run.md: Status must contain exactly one valid status value")
        status = ""
    else:
        status = status_lines[0]

    expected_actions = {
        "complete": "complete",
        "blocked": "blocked",
        "canceled": "canceled",
    }
    if status in expected_actions and next_action != expected_actions[status]:
        err(f"run.md: Status {status} requires next_action: {expected_actions[status]}")

    if status == "active" and not STAGE_RE.fullmatch(next_action):
        err("run.md: Status active requires next_action to be a valid stage")

    current_done = RUN / "state" / f"{current_stage}.done"
    if current_stage and current_stage != "none" and not current_done.exists():
        err(f"run.md: current_stage requires done file {current_done}")

    return run_start_ref, status, workflow


def artifact_kind(path: Path):
    name = path.name
    patterns = [
        (r"^plan_v(0|[1-9][0-9]*)\.md$", "plan", "# Plan v{}"),
        (r"^plan_v(0|[1-9][0-9]*)_review\.md$", "plan_review", "# Plan v{} Review"),
        (r"^code_v(0|[1-9][0-9]*)\.md$", "code", "# Code v{}"),
        (r"^review_v(0|[1-9][0-9]*)\.md$", "review", "# Review v{}"),
    ]
    for pattern, kind, heading_template in patterns:
        match = re.fullmatch(pattern, name)
        if match:
            version = match.group(1)
            return kind, int(version), heading_template.format(version)
    return None, None, None


def validate_artifact(path: Path, run_start_ref: str) -> None:
    kind, version, heading = artifact_kind(path)
    if kind is None:
        err(f"{path}: invalid artifact filename")
        return

    text = read(path)
    if not text.strip():
        err(f"{path}: artifact is empty")
        return

    if len(re.findall(rf"^{re.escape(heading)}$", text, re.M)) != 1:
        err(f"{path}: expected exactly one heading '{heading}'")

    require_sections(path, text, CONTRACTS[kind])

    if kind in {"plan_review", "review"}:
        verdicts = [line for line in text.splitlines() if line.startswith("VERDICT:")]
        if len(verdicts) != 1 or not VERDICT_RE.fullmatch(verdicts[0]):
            err(f"{path}: expected exactly one valid whole-line VERDICT")
        else:
            verdict = verdicts[0].split(": ", 1)[1]
            summary_override_lines = [
                line for line in section(text, "Summary").splitlines()
                if line.startswith("AUTO OVERRIDE:")
            ]
            override_lines = [
                line for line in text.splitlines()
                if line.startswith("AUTO OVERRIDE:")
            ]
            if verdict == "APPROVE_AUTO_OVERRIDE" and len(summary_override_lines) != 1:
                err(f"{path}: APPROVE_AUTO_OVERRIDE requires exactly one AUTO OVERRIDE: line in ## Summary")
            if verdict == "APPROVE_AUTO_OVERRIDE" and len(override_lines) != 1:
                err(f"{path}: AUTO OVERRIDE: must appear only once")
            if verdict != "APPROVE_AUTO_OVERRIDE" and override_lines:
                err(f"{path}: AUTO OVERRIDE: requires VERDICT: APPROVE_AUTO_OVERRIDE")
        raw_path = RUN / "state" / f"{path.stem}.review.raw.md"
        if not raw_path.exists():
            err(f"{path}: missing raw reviewer transcript {raw_path}")
        elif not read(raw_path).strip():
            err(f"{path}: raw reviewer transcript is empty: {raw_path}")

    if kind == "plan":
        body = non_empty_section(path, text, "Changes Since Previous Plan Version")
        if version == 0 and body.strip() != "Initial plan.":
            err(f"{path}: plan_v0 Changes Since must be exactly 'Initial plan.'")

    if kind == "code":
        body = non_empty_section(path, text, "Changes Since Previous Code Version")
        if version == 0 and body.strip() != "Initial implementation.":
            err(f"{path}: code_v0 Changes Since must be exactly 'Initial implementation.'")
        baseline = key_values(section(text, "Git Baseline"))
        if baseline.get("run_start_ref") != run_start_ref:
            err(f"{path}: Git Baseline run_start_ref must match run.md")
        current_head = baseline.get("current_head")
        if not current_head or (current_head != "none" and not SHA_RE.fullmatch(current_head)):
            err(f"{path}: Git Baseline current_head must be a SHA or none")

    if kind == "review":
        baseline = key_values(section(text, "Diff Baseline"))
        if baseline.get("run_start_ref") != run_start_ref:
            err(f"{path}: Diff Baseline run_start_ref must match run.md")
        diff_mode = baseline.get("diff_mode")
        unreviewed = baseline.get("unreviewed")
        if diff_mode is not None and diff_mode not in {"full", "tiered"}:
            err(f"{path}: Diff Baseline diff_mode must be full or tiered")
        approvals = {"VERDICT: APPROVE", "VERDICT: APPROVE_WITH_MINOR_COMMENTS", "VERDICT: APPROVE_AUTO_OVERRIDE"}
        if unreviewed not in (None, "", "none") and approvals & set(text.splitlines()):
            err(f"{path}: unreviewed source/test files forbid approval verdicts")


def validate_done_file(path: Path) -> None:
    text = read(path)
    values = key_values(text)
    stage = values.get("stage")
    artifact = values.get("artifact")

    if not stage:
        err(f"{path}: missing stage")
    elif path.stem != stage:
        err(f"{path}: done filename must match stage")
    elif not STAGE_RE.fullmatch(stage):
        err(f"{path}: invalid stage")

    if values.get("status") != "complete":
        err(f"{path}: status must be complete")

    if artifact:
        expected_artifact = f"artifacts/{stage}.md" if stage else None
        if expected_artifact and artifact != expected_artifact:
            err(f"{path}: artifact must be {expected_artifact}")
        if not (RUN / artifact).exists():
            err(f"{path}: artifact path missing: {artifact}")
    else:
        err(f"{path}: missing artifact")


def artifact_stage(path: Path) -> str:
    return path.stem


def validate_sequential_versions(artifact_paths: list[Path]) -> None:
    by_kind = {}
    for path in artifact_paths:
        kind, version, _ = artifact_kind(path)
        if kind is None:
            continue
        by_kind.setdefault(kind, set()).add(version)

    for kind, versions in by_kind.items():
        for version in versions:
            for prior in range(version):
                if prior not in versions:
                    err(f"artifacts: {kind} v{version} requires {kind} v{prior}")


def validate_artifact_done_pairs(artifact_paths: list[Path]) -> None:
    for path in artifact_paths:
        stage = artifact_stage(path)
        done_path = RUN / "state" / f"{stage}.done"
        if not done_path.exists():
            err(f"{path}: missing matching done file {done_path}")


def main() -> int:
    if not RUN.exists() or not RUN.is_dir():
        err(f"run folder does not exist: {RUN}")
    run_start_ref, _, _ = parse_run_md()

    artifacts = RUN / "artifacts"
    artifact_paths = []
    if not artifacts.is_dir():
        err(f"missing artifacts directory: {artifacts}")
    else:
        artifact_paths = sorted(artifacts.glob("*.md"))
        for path in artifact_paths:
            validate_artifact(path, run_start_ref)
        validate_sequential_versions(artifact_paths)
        validate_artifact_done_pairs(artifact_paths)

    state = RUN / "state"
    if not state.is_dir():
        err(f"missing state directory: {state}")
    else:
        for path in sorted(state.glob("*.done")):
            validate_done_file(path)

    if errors:
        for message in errors:
            print(f"ccc-validate: {message}", file=sys.stderr)
        return 1

    print(f"CCC run valid: {RUN}")
    return 0


sys.exit(main())
PY
