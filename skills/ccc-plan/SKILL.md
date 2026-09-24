---
name: ccc-plan
description: CCC planning stage. The configured planner writes or revises plan_vN.md from the task and prior plan review. Use only inside CCC.
---
# Skill: CCC Plan

Use only in CCC. Read `<CCC_HOME>/protocol/CCC_PROTOCOL.md`; coordinator full read satisfies an in-session stage in the same invocation. Standalone -> read fully. Follow its artifact contract.

## CCC Home

Resolve `$CCC_HOME`, then this skill's own directory, then a `ccc-duet` checkout containing the protocol; if none resolves, stop blocked and report paths. `<CCC_HOME>` is not the target repository; see protocol `## CCC Home`.

## Inputs

For `plan_v0`:

```text
<RUN>/task.md
```

For `plan_v1+`:

```text
<RUN>/task.md
<RUN>/artifacts/plan_v{N-1}.md
<RUN>/artifacts/plan_v{N-1}_review.md
```

## Output

```text
<RUN>/artifacts/plan_vN.md
```

Do not write `.done`.

## Rules

* Do not edit code during planning. Follow the run's caveman level (`run.md` `caveman:`; absent or `off` = normal prose). Include concrete verification and answer every prior ID once in `Changes Since Previous Plan Version`.
* The configured planner owns this stage.
* Keep the plan scoped to the task.
* For `plan_v1+`, directly address the prior plan review findings in `Changes Since Previous Plan Version`.
* Do not silently ignore review findings.
* Include concrete verification steps.
* Do not write review artifacts.
