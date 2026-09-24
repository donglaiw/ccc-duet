---
name: ccc-plan-review
description: CCC plan review stage. The configured coder reviews plan_vN.md and produces plan_vN_review.md. Use only inside CCC.
---
# Skill: CCC Plan Review

Use only in CCC. Read `<CCC_HOME>/protocol/CCC_PROTOCOL.md`; coordinator full read satisfies an in-session stage in the same invocation. Standalone -> read fully. Follow its artifact contract.

## CCC Home

Resolve `$CCC_HOME`, then this skill's own directory, then a `ccc-duet` checkout containing the protocol; if none resolves, stop blocked and report paths. `<CCC_HOME>` is not the target repository; see protocol `## CCC Home`.

## Inputs

```text
<RUN>/task.md
<RUN>/artifacts/plan_vN.md
```

For `plan_v1+`, also include previous plan review context when available:

```text
<RUN>/artifacts/plan_v{N-1}.md
<RUN>/artifacts/plan_v{N-1}_review.md
```

## Output

```text
<RUN>/state/plan_vN_review.review.raw.md
<RUN>/artifacts/plan_vN_review.md
```

Do not write `.done`.

## Rules

* The configured coder owns this stage.
* If the coder is the current session's agent, perform the review directly.
* If the coder is `codex`, run `codex exec --sandbox read-only --output-last-message <RUN>/state/plan_vN_review.review.raw.md -` from the repository root.
* If the coder is `claude`, run `claude --print --output-format text --no-session-persistence --tools ""` from the repository root and capture stdout to `state/plan_vN_review.review.raw.md`.
* Include embedded protocol snapshot, exact byte log, caveman embedding when the run level is not `off`, compact reply contract, and complete required artifacts; v1+ uses delta handoff. If over `CCC_REVIEW_PROMPT_MAX_BYTES`, block.
* Use the plan-review prompt template from `<CCC_HOME>/protocol/CCC_PROTOCOL.md`.
* Tell the reviewer to evaluate only the artifacts and text included in the prompt, without inspecting other repository files.
* Tell reviewer: no edits; inspect only included text; emit only `READY`, finding IDs, and questions tagged `[minor]`/`[major]`.
* Do not let the reviewer edit code during plan review.
* Save the raw reviewer output to `state/plan_vN_review.review.raw.md` before writing the review artifact.
* Preserve reviewer findings faithfully when writing the artifact.
* The coordinator may write the final CCC `VERDICT:` line after interpreting reviewer output, but must not soften or discard material findings.
* If the coordinator uses `VERDICT: APPROVE_AUTO_OVERRIDE`, include exactly one `AUTO OVERRIDE:` line in `## Summary`.
* Treat ambiguous finding severity as major.
* If reviewer output does not clearly support a verdict, append a clarification call to the same raw transcript or stop as blocked.
* Do not write code artifacts.
