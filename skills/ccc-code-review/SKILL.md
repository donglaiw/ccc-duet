---
name: ccc-code-review
description: CCC code review stage. The configured planner reviews code_vN.md and actual repository changes against the CCC git baseline. Use only inside CCC.
---
# Skill: CCC Code Review

Use only in CCC. Read `<CCC_HOME>/protocol/CCC_PROTOCOL.md`; coordinator full read satisfies an in-session stage in the same invocation. Standalone -> read fully. Follow its artifact contract.

## CCC Home

Resolve `$CCC_HOME`, then this skill's own directory, then a `ccc-duet` checkout containing the protocol; if none resolves, stop blocked and report paths. `<CCC_HOME>` is not the target repository; see protocol `## CCC Home`.

## Inputs

```text
<RUN>/task.md
<RUN>/run.md
<RUN>/artifacts/code_vN.md
```

For `review_v1+`, also read:

```text
<RUN>/artifacts/review_v{N-1}.md
<RUN>/artifacts/code_v{N-1}.md
```

## Output

```text
<RUN>/state/review_vN.review.raw.md
<RUN>/artifacts/review_vN.md
```

Do not write `.done`.

## Rules

* The configured planner owns this stage.
* If the planner is the current session's agent, perform the review directly.
* If the planner is `codex` and `HEAD` equals `run_start_ref`, run `codex exec --sandbox read-only --output-last-message <RUN>/state/review_vN.review.raw.md -` from the repository root.
* If `HEAD` differs from `run_start_ref`, stop as blocked because commits are not allowed during a CCC run.
* If the planner is `codex` and the baseline is empty-tree, use the same `codex exec --sandbox read-only` reviewer command and include the protocol's fallback prompt and diff commands.
* If the planner is `claude`, run `claude --print --output-format text --no-session-persistence --tools ""` from the repository root and capture stdout to `state/review_vN.review.raw.md`.
* Include embedded protocol snapshot, caveman embedding when the run level is not `off`, exact byte log, complete current diff, and compact reply contract; v1+ gets prior review Findings/Questions/VERDICT. If over the prompt ceiling, block.
* Use the code-review prompt template from `<CCC_HOME>/protocol/CCC_PROTOCOL.md`.
* Tell the reviewer to evaluate only the artifacts and diffs included in the prompt, without inspecting other repository files.
* For Codex reviewer commands, do not pass `--dangerously-bypass-approvals-and-sandbox`.
* Carry the diff via `<CCC_HOME>/scripts/ccc-diff-summary.sh` per protocol `## Review Diff Budget` (unless `CCC_REVIEW_DIFF_BUDGET=off`). In `tiered` mode require `NEED`/`SKIP` per summarized file, serve `NEED` with one follow-up call, record `diff_mode:`, `skipped:`, and `unreviewed:` in `## Diff Baseline`; source/test files are never summarized, and any unreviewed source/test file forbids every approval verdict.
* Verify `HEAD == run_start_ref`; include excluded status/cached/unstaged diffs, empty-tree fallback, and `<CCC_HOME>/scripts/ccc-untracked.sh ... --prompt`. Capture `--manifest` plus tracked/staged diffs before/after; any change blocks.
* Inspect the actual git diff using the `run_start_ref` from `run.md`.
* Do not trust `code_vN.md` alone.
* For `review_v1+`, focus on whether prior findings were fixed and whether new issues were introduced.
* Save the raw reviewer output to `state/review_vN.review.raw.md` before writing the review artifact.
* Preserve reviewer findings faithfully when writing the artifact.
* The coordinator may write the final CCC `VERDICT:` line after interpreting reviewer output, but must not soften or discard material findings.
* If the coordinator uses `VERDICT: APPROVE_AUTO_OVERRIDE`, include exactly one `AUTO OVERRIDE:` line in `## Summary`.
* Treat ambiguous finding severity as major.
* If reviewer output does not clearly support a verdict, append a clarification call to the same raw transcript or stop as blocked.
