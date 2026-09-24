---
name: ccc
description: Coordinate the CCC single-session workflow using configurable planner/coder agents, explicit output folders, protocol-defined artifacts, and .done sentinels.
---
# Skill: CCC Coordinator

Use this skill to coordinate a CCC run from the current session. `plan-code=<planner>-<coder>` selects who owns planning and implementation.

Before action, resolve `<CCC_HOME>` and read `<CCC_HOME>/protocol/CCC_PROTOCOL.md`; record `ccc_home` and optional `protocol_sha256`. In-session stages may use that same full read; subprocesses receive embedded snapshots.

## CCC Home

`<CCC_HOME>` ships the protocol and scripts; it is not the target repository. Resolve it once per run:

1. `$CCC_HOME`, when set and its protocol exists.
2. This skill's own directory.
3. A `ccc-duet` checkout containing the protocol.

If none resolves, the install is incomplete: stop with `Status: blocked`, report the paths tried, and point at `<CCC_HOME>/scripts/ccc-install.sh`. Never reconstruct the protocol from memory. Record the resolved path in `## Runtime` as `ccc_home:`.

## Coordinator Checklist

1. Parse the requested CCC action: default start, `resume`, or `cancel`, optional mode `manual`, `normal`, or `auto`, optional `plan-code=<planner>-<coder>`, optional `caveman=off|lite|full|ultra`, and optional rounds `pN-cM`; mode is not persisted and `resume` defaults to `normal`.
2. Resolve the explicit output folder.
3. Create the run folder, `artifacts/`, and `state/` if needed.
4. Run `<CCC_HOME>/scripts/ccc-detect-session.sh` and record `session_detected`; the current session remains the coordinator.
5. Resolve `plan-code`, defaulting to `claude-codex`; explicit `plan-code=...` wins, then `CCC_PLAN_CODE`, then default. Resolve `caveman`: explicit `caveman=...` wins; else on resume the persisted value; else on start `CCC_CAVEMAN`; else `off`; record `caveman:` and `caveman_source:` in `## Runtime`. If the level is not `off`, resolve the caveman `SKILL.md` per the protocol `## Caveman Mode` or initialize the run as blocked.
6. For a new start, confirm required companion CLIs exit successfully, using `<CCC_HOME>/scripts/ccc-check-agent-cli.sh <agent>` when practical, or initialize the run as blocked.
7. For a new start, write `task.md` and initialize `run.md`, including `## Runtime` and the git baseline required by the protocol.
8. Determine the next stage from `.done` files and artifact verdicts.
9. Resolve the stage owner from `plan-code`: planner owns `plan_vN` and `review_vN`; coder owns `plan_vN_review` and `code_vN`.
10. If the stage owner is the current session's agent, perform the matching stage skill directly. If not, invoke the owner through its non-interactive CLI.
11. Validate the artifact with `<CCC_HOME>/scripts/ccc-validate.sh <output_folder>`, write the `.done` file, update `run.md`, and continue according to mode:
   * `manual` stops for user approval after one completed stage.
   * `normal` runs until complete or a human decision is needed.
   * `auto` runs through reviewer disagreement until complete unless a hard failure blocks the run.

## Reviewer CLI

Stages owned by the other agent are automatic shell commands:

```text
1. Build the review prompt from the protocol template.
2. Embed protocol snapshots from ccc-protocol-sections.sh; fail on extraction error.
3. Write exact UTF-8 prompt bytes to state/<stage>.prompt.bytes; enforce the byte ceiling.
4. For code review, build the diff block with ccc-diff-summary.sh (protocol `## Review Diff Budget`); in `tiered` mode serve `NEED` lines with at most one follow-up call. Capture ccc-untracked.sh --manifest and tracked/staged diffs before and after the owner command; block on mutation or script error.
5. Run the configured owner command from the repository root.
6. For review stages, write the CCC review artifact as an attested summary of the raw output.
```

For plan reviews, use `state/plan_vN_review.review.raw.md`.

For code reviews, use `state/review_vN.review.raw.md`.

If a code-review command mutates repository state, the companion CLI exits non-zero, produces no required raw transcript, or the output does not clearly support a verdict, stop with `Status: blocked`.

In `auto` mode, unresolved reviewer disagreement may be overridden only as described in the protocol. Preserve all review findings, use `VERDICT: APPROVE_AUTO_OVERRIDE`, and write exactly one `AUTO OVERRIDE:` line in `## Summary`; do not override hard failures.

Driver stages must not create git commits during a CCC run.

## Stage Skills

```text
ccc-plan
ccc-plan-review
ccc-code
ccc-code-review
```

Only this coordinator skill writes `.done` files.
