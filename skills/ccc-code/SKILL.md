---
name: ccc-code
description: CCC code stage. The configured coder implements or revises code_vN.md from the approved plan and prior review. Use only inside CCC.
---
# Skill: CCC Code

Use only in CCC. Read `<CCC_HOME>/protocol/CCC_PROTOCOL.md`; the coordinator's full read satisfies this for an in-session stage in the same invocation. Standalone -> read it fully. Follow its artifact contract.

## CCC Home

Resolve `$CCC_HOME`, then this skill's own directory, then a `ccc-duet` checkout containing the protocol; if none resolves, stop blocked and report paths. `<CCC_HOME>` is not the target repository; see protocol `## CCC Home`.

## Inputs

For `code_v0`:

```text
<RUN>/task.md
<RUN>/run.md
<RUN>/artifacts/plan_vN.md
<RUN>/artifacts/plan_vN_review.md
```

For `code_v1+` (delta handoff; answer every prior finding/question ID once):

```text
<RUN>/task.md
<RUN>/run.md
<RUN>/artifacts/code_v{N-1}.md
<RUN>/artifacts/review_v{N-1}.md
```

## Output

```text
<RUN>/artifacts/code_vN.md
```

Do not write `.done`.

## Rules

* Implement, verify, summarize actual diff; follow the run's caveman level for `code_vN.md` (absent or `off` = normal prose); never compress code or comments.
* Keep required headings, baseline keys, and `Initial implementation.` verbatim for v0.
* The configured coder owns this stage.
* Include the protocol-defined git baseline in `code_vN.md`.
* Do not create git commits during a CCC run.
* Keep changes scoped.
* Do not silently ignore review findings.
* Do not claim tests passed unless commands actually ran.
* Summarize the actual diff, not intent.
* Do not write review artifacts.
