# CCC Protocol

This file is the canonical CCC workflow specification. README files and skills should point here instead of repeating these rules.

CCC is a single-session coordinator workflow for one incremental code change. The current agent session is the coordinator. CCC assigns planning and coding stages to Claude or Codex, writes versioned artifacts, and stops at a clear verdict.

Do not use `.ccc/current_run`; the output folder is always explicit.

## Finding IDs

Every actionable review concern has an ID: plan findings `P1..`, code findings `C1..`, questions `Q1..`, unique per artifact. Cross-version references use `<stage>:<id>` (for example `review_v0:C2`). The next version's `Changes Since ...` section answers each prior ID once as `fixed`, `rejected`, or `deferred`, with a reason, and answers questions inline. Required empty sections say `none`. IDs are structure, not compression; they apply in every caveman level, including `off`.

## Caveman Mode

Caveman mode is an **opt-in** compression level for agent-facing text. The default is `caveman=off`: every stage writes normal, complete prose, which favors plan and code quality over token savings. Compressed prose may degrade reasoning or drop nuance, so enable it deliberately.

Levels:

```text
off    default; normal prose everywhere
lite   caveman lite: no filler or hedging; articles and full sentences kept
full   caveman full: articles dropped, fragments allowed
ultra  caveman ultra: maximal compression
```

Wenyan levels are not supported: cross-agent artifacts must stay in the run's working language.

The style rules come from the `caveman` skill (upstream `JuliusBrussee/caveman`, `skills/caveman/SKILL.md`), which `<CCC_HOME>/scripts/ccc-install.sh` installs pinned by commit and SHA-256. Resolve its `SKILL.md` in this order: `$CCC_CAVEMAN_SKILL`; `caveman/SKILL.md` next to the installed `ccc` skill directory; `~/.claude/skills/caveman/SKILL.md`. If a level other than `off` is selected and none resolves, the run is blocked at start; do not improvise caveman rules from memory.

When the level is not `off`:

* Scope: `plan_vN.md`, `plan_vN_review.md`, `code_vN.md`, `review_vN.md`, cross-agent prompts, and reviewer replies. This intentionally overrides the caveman skill's own "persisted outside chat stays normal prose" boundary for these CCC files only.
* Out of scope, always normal prose: `task.md`, `run.md`, raw transcripts (kept verbatim), code, code comments, repository docs, commit text, and every message to the user.
* Never compress away: headings, `VERDICT` lines, required literals (`Initial plan.`, `Initial implementation.`, baseline keys), paths, commands, code, identifiers, numbers, error text, finding severity and content, verification commands and outcomes, risks, and blockers. The caveman skill's auto-clarity rules apply; when compression creates ambiguity, write normally.
* In-session stages load the resolved caveman skill at the selected level. Cross-agent prompts embed the resolved `SKILL.md` text plus one line: `Caveman level: <level>. Apply only to your reply/artifact text; never to code.`

Selection precedence:

```text
1. caveman=<level> in the command.
2. Else CCC_CAVEMAN, when it is a valid level.
3. Else off.
```

The level is persisted in `run.md` `## Runtime` as `caveman:` with `caveman_source: explicit|env|default|persisted`. A missing `caveman:` line means `off`. `/ccc resume` reuses the persisted level unless an explicit `caveman=<level>` replaces it.

## CCC Home

`<CCC_HOME>` is the directory that ships this protocol and the CCC scripts. It is **not** the target repository, and it is not the current working directory. Every skill resolves it before doing anything else, in this order:

1. `$CCC_HOME`, when set and `$CCC_HOME/protocol/CCC_PROTOCOL.md` exists.
2. The invoked skill's own directory, which ships `protocol/` and `scripts/` (for example `~/.claude/skills/ccc/protocol/CCC_PROTOCOL.md`).
3. A `ccc-duet` checkout root that contains `protocol/CCC_PROTOCOL.md`.

If none of the three resolves, the install is incomplete. Stop with `Status: blocked`, report which paths were tried, and point at `<CCC_HOME>/scripts/ccc-install.sh`. Never reconstruct this protocol, an artifact contract, or a prompt template from memory.

The coordinator may record the resolved path in `## Runtime` as an optional `ccc_home:` line for provenance.

All protocol and skill references written as `<CCC_HOME>/...` resolve here. Companion CLI calls for reviewer stages still run from the **target repository root**, which is unrelated to `<CCC_HOME>`.

## Defaults

The default run is:

```text
plan-code=claude-codex p2-c2 normal
```

Meaning:

```text
plan-code=claude-codex   Claude owns planning and code review; Codex owns plan review and coding.
p2-c2                    allow plan_v0..plan_v2 and code_v0..code_v2.
normal                   block for human direction on unresolved major disagreement.
```

## Agents

CCC recognizes two agent names in configuration:

```text
claude
codex
```

CLI requirements:

```text
claude  Claude Code CLI with `claude --print`
codex   Codex CLI with `codex exec`
```

Check local CLI compatibility when practical:

```text
<CCC_HOME>/scripts/ccc-check-agent-cli.sh claude
<CCC_HOME>/scripts/ccc-check-agent-cli.sh codex
```

CCC uses non-interactive companion calls. It must not ask the user to run `/codex:` or `/claude:` slash commands.

## Syntax

```text
/ccc <output_folder> "<task>" [pN-cM] [manual|normal|auto] [plan-code=<planner>-<coder>] [caveman=off|lite|full|ultra]
/ccc resume <output_folder> [manual|normal|auto] [plan-code=<planner>-<coder>] [caveman=off|lite|full|ultra]
/ccc cancel <output_folder> "<reason>"
```

Codex may expose the same skill as `$ccc`; use the same arguments.

Valid `plan-code` values:

```text
plan-code=claude-codex
plan-code=codex-claude
plan-code=claude-claude
plan-code=codex-codex
```

Optional arguments may appear in any order. Reject duplicate arguments of the same type. On parse errors, print the error and stop without creating or modifying the run folder.

Argument defaults:

```text
plan-code  claude-codex
rounds     p2-c2
mode       normal
caveman    off
```

`pN-cM` is the required rounds syntax. It means:

```text
plan_rounds: N
revision_rounds: M
```

Mode is not persisted in `run.md`; `/ccc resume <output_folder>` defaults to `normal` unless `manual` or `auto` is passed again.

`plan-code` is persisted in `run.md`. `/ccc resume <output_folder>` reuses the persisted value unless the user passes an explicit replacement.

Plan-code selection precedence:

```text
1. If the command includes plan-code=<planner>-<coder>, use it.
2. Else, if CCC_PLAN_CODE is a valid planner-coder pair, use it.
3. Else, use default plan-code=claude-codex.
```

`CCC_PLAN_CODE` values are case-sensitive and must be one of `claude-codex`, `codex-claude`, `claude-claude`, or `codex-codex`. Any other value is treated as absent.

## Session Detection

Detection uses agent-provided environment markers:

```text
CLAUDECODE=1 or CLAUDE_CODE_SESSION_ID present -> claude
CODEX_CI=1 -> codex
both Claude and Codex markers present -> unknown
otherwise -> unknown
```

Shell markers are best-effort. Do not rely on parent-process names except as a future fallback; wrappers, sandboxes, tmux, and login shells make process-name detection unstable.

The coordinator records `session_detected` at run start for diagnostics only. The current session is always the coordinator.

## Stage Ownership

`plan-code=<planner>-<coder>` controls ownership:

```text
plan_vN          planner
plan_vN_review   coder
code_vN          coder
review_vN        planner
```

If a stage owner is the current session's agent, perform the stage directly. If the stage owner differs from the current session, invoke that owner through its non-interactive CLI and then validate the resulting artifact before writing `.done`.

Stages owned by the current session run in-session. Stages owned by the other agent use a CLI subprocess and consume prompt budget.

This keeps the common default optimized for model strengths and handoff pressure:

```text
Claude plans, then later reviews whether implementation matches that plan.
Codex reviews whether the plan is executable, then implements it.
```

Same-agent configurations (`claude-claude` and `codex-codex`) are protocol-discipline-only modes. They preserve artifact structure, validation, and bounded rounds, but they do not provide cross-model review.

## Modes

```text
manual  complete one stage, write its artifact and .done file, update run.md, then stop for user approval before the next stage
normal  run stages until complete, blocked, or canceled; unresolved major reviewer disagreement waits for a human decision
auto    run stages until complete, blocked by hard failure, or canceled; unresolved reviewer disagreement does not require human approval
```

Mode decisions:

| Situation | manual | normal | auto |
|---|---|---|---|
| Any stage completes | Stop for user approval before the next stage. | Continue. | Continue. |
| Review approves | Continue, subject to the manual approval stop above. | Continue. | Continue. |
| Review requests changes and another version is allowed | Stop for user approval before the next stage. | Write the next version. | Write the next version. |
| Review reports `BLOCKER` and another version is allowed | Block unless the user explicitly directs a clear fix. | Block unless the user explicitly directs a clear fix. | Treat as content-level reviewer disagreement and write the next version. |
| No version remains and unresolved findings are minor-only | Complete or advance with `VERDICT: APPROVE_WITH_MINOR_COMMENTS`. | Complete or advance with `VERDICT: APPROVE_WITH_MINOR_COMMENTS`. | Complete or advance with `VERDICT: APPROVE_AUTO_OVERRIDE`. |
| No version remains and unresolved findings are major or reviewer `BLOCKER` | Block for human decision. | Block for human decision. | Complete or advance with `VERDICT: APPROVE_AUTO_OVERRIDE`. |
| Hard failure | Block. | Block. | Block. |

Hard failures originate from the coordinator or infrastructure, not from reviewer prose: invalid CLI or auth state, failed commands, missing raw transcripts, validation failure, repository mutation, `HEAD` divergence, invalid baseline, prompt budget overflow, parse errors, and user cancellation.

## Rounds

CCC uses zero-based versions. `p2-c2` allows:

```text
plan_v0 -> plan_v0_review -> plan_v1 -> plan_v1_review -> plan_v2
code_v0 -> review_v0 -> code_v1 -> review_v1 -> code_v2
```

The final artifact at the maximum version is a decision point, not automatically an approval in `manual` or `normal` mode. `auto` mode may override unresolved reviewer disagreement at this point.

## Output Folder

The coordinator creates:

```text
<output_folder>/
  task.md
  run.md
  artifacts/
  state/
```

## Run File

When starting a new run, the coordinator writes `<output_folder>/task.md`, captures the git baseline files, and initializes `<output_folder>/run.md`.

`run.md` must include:

```text
# CCC Run

## Description
## Runtime
## Rounds
## Task Summary
## Git Baseline
## Workflow State
## Status
```

`## Description` is free-form human text describing the run.

`## Runtime` records:

```text
planner: <claude|codex>
coder: <claude|codex>
plan_code: <claude-codex|codex-claude|claude-claude|codex-codex>
session_detected: <claude|codex|unknown>
plan_code_source: <explicit|env|default|persisted>
caveman: <off|lite|full|ultra>              # optional; absent means off
caveman_source: <explicit|env|default|persisted>  # required when caveman is present
ccc_home: <absolute path>          # optional provenance
protocol_sha256: <sha256>          # optional snapshot provenance
```

`plan_code` must equal `<planner>-<coder>`.

On resume, `plan_code_source: persisted` records that the stored value was reused for that invocation. CCC does not preserve the original selection source separately.

`## Rounds` uses:

```text
plan_rounds: <N>
revision_rounds: <M>
```

`## Git Baseline` records:

```text
run_start_ref: <git sha or 4b825dc642cb6eb9a060e54bf8d69288fbee4904>
run_start_ref_kind: head | empty_tree
run_start_status_file: state/run_start.status
run_start_unstaged_diff: state/run_start.diff
run_start_staged_diff: state/run_start_cached.diff
```

`state/run_start.status` is the exact stdout of `git status --short` at run start. An empty file means the run started clean.

For normal repositories, `run_start_ref` is `git rev-parse --verify HEAD` and `run_start_ref_kind` is `head`.

For fresh repositories with no commits, `run_start_ref` is the Git empty-tree SHA `4b825dc642cb6eb9a060e54bf8d69288fbee4904` and `run_start_ref_kind` is `empty_tree`.

`## Workflow State` is machine-readable:

```text
current_stage: <stage|none>
latest_artifact: <artifact path|none>
latest_verdict: <APPROVE|APPROVE_WITH_MINOR_COMMENTS|APPROVE_AUTO_OVERRIDE|NEEDS_CHANGES|BLOCKER|none>
next_action: <stage|complete|blocked|canceled>
```

`## Status` must contain exactly one of:

```text
active
complete
blocked
canceled
```

All `run.md` writes use a temporary file in the same directory, then an atomic rename.

## Agent Calls

Stages owned by the current session's agent are performed directly with the matching stage skill.

Stages owned by the other agent use a non-interactive CLI call from the repository root.

For Codex-owned stages:

```text
codex exec --output-last-message <output-file> -
```

For Codex-owned read-only review stages, add:

```text
--sandbox read-only
```

For Claude-owned stages:

```text
claude --print --output-format text --no-session-persistence
```

For Claude-owned read-only review stages, add:

```text
--tools ""
```

`--tools ""` is a Claude CLI contract, not an independent sandbox proof. Use `<CCC_HOME>/scripts/ccc-check-agent-cli.sh claude` when practical.

## Review Prompt Contract

All cross-agent calls use self-contained prompts. The coordinator includes the task, relevant CCC artifacts, and relevant git outputs. The recipient evaluates exactly the prompt contents.

This symmetry is a deliberate tradeoff. The recipient does not independently re-derive the whole changeset from repository state. Integrity depends on the coordinator assembling a complete prompt, preserving raw transcripts for review stages, and using the pre/post git-diff mutation guard for code review commands.

Before invoking another agent, compute the UTF-8 byte length of the exact stdin payload. The default ceiling is:

```text
CCC_REVIEW_PROMPT_MAX_BYTES=200000
```

If the prompt would exceed the ceiling, stop with `Status: blocked` before writing the raw transcript and report:

```text
Reviewer prompt exceeds CCC_REVIEW_PROMPT_MAX_BYTES; narrow the task, reduce the diff, or raise the limit explicitly.
```

Reviewer prompts must include:

```text
Do not edit files.
Review only the artifacts and diffs included in this prompt. Do not inspect other repository files.
Tag each finding as [minor] or [major].
READY: yes|no
```

The coordinator maps readiness to CCC verdicts:

```text
READY: yes with no material findings      -> VERDICT: APPROVE
READY: yes with only minor findings       -> VERDICT: APPROVE_WITH_MINOR_COMMENTS
READY: no with fixable findings           -> VERDICT: NEEDS_CHANGES
READY: no with external blocker/unsafe uncertainty -> VERDICT: BLOCKER
```

The coordinator saves raw reviewer output at:

```text
state/plan_vN_review.review.raw.md
state/review_vN.review.raw.md
```

The CCC review artifact is an attested summary of the raw reviewer output, not a replacement for it. The coordinator may write the final `VERDICT:` line after interpreting the raw output, but it must not silently soften or discard material findings.

Reviewer prose cannot promote a finding to hard-failure status. Hard failures are detected only by coordinator-side checks.

Every review prompt ends with this compact reply contract:

```text
READY: yes|no
<ID> [major|minor] <loc> — <problem> — <fix>
Q<n> <question>
NEED <json-path>          (tiered code review only)
SKIP <json-path> — <reason>   (tiered code review only)
```

Nothing else. Unparseable output -> clarification or block. Prompts use stable order: static rules + protocol snapshots, task, current artifacts, diffs last. For v1+, include task, full current artifact, and prior review Findings/Questions/VERDICT; omit prior plan/code artifact. Code reviews still include the full current diff against baseline. Log exact stdin UTF-8 bytes at `state/<stage>.prompt.bytes` before the ceiling check.

Protocol snapshots come from `<CCC_HOME>/scripts/ccc-protocol-sections.sh <protocol> <Section>...`; failure is a hard failure. Stage inputs:

| Stage | Embedded sections |
|---|---|
| plan_vN | Finding IDs, Artifact Contracts |
| plan_vN_review | Finding IDs, Review Prompt Contract, Verdicts |
| code_vN | Finding IDs, Artifact Contracts, Git Review Baseline |
| review_vN | Finding IDs, Review Prompt Contract, Verdicts, Git Review Baseline, Review Diff Budget |

When `caveman` is not `off`, also embed `Caveman Mode` and the resolved caveman `SKILL.md`.

Reviewers do not receive Artifact Contracts; they reply in the compact format above. The coordinator reads the full protocol once per invocation, may record its hash, and writes the attested artifact.

## Git Review Baseline

Driver commits during a run are not allowed. The intended review surface is the working tree relative to `run_start_ref`.

When `run_start_ref_kind` is `head`, confirm `git rev-parse HEAD` equals `run_start_ref` before any code-review command. If `HEAD` has moved, stop with `Status: blocked`; recover by restoring `HEAD` to `run_start_ref`, or cancel and start a new run.

For `head` mode, first verify `HEAD == run_start_ref`; do not include triple-dot stat/diff output after that check. Use these git outputs in code-review prompts, applying pathspec exclusions when the run folder is inside the repository:

```text
git status --short -- . ':(exclude)<output_folder>'
git diff --cached -- . ':(exclude)<output_folder>'
git diff -- . ':(exclude)<output_folder>'
```

Include `<CCC_HOME>/scripts/ccc-untracked.sh <repo_root> <output_folder> --prompt` in every code-review prompt when `CCC_REVIEW_DIFF_BUDGET=off`; otherwise `## Review Diff Budget` supplies the `git diff --cached`, `git diff`, and untracked content in one block. It lists non-ignored untracked files, excluding the run folder, with JSON-safe paths and text/binary/symlink/other content. Its `--manifest` output is a mutation guard captured immediately before and after the reviewer call:

```text
<sha256|-> <size> <octal st_mode> <kind> <json-path>
```

Hash regular-file bytes and symlink target bytes; `st_mode` includes file type and permission bits. Any manifest difference, including chmod or type changes, blocks. Script errors block. Hashing has no size cap; prompt size remains bounded by `CCC_REVIEW_PROMPT_MAX_BYTES`. Empty-tree mode uses the same untracked block and exclusions, with the baseline diff commands below.

When `run_start_ref_kind` is `empty_tree`, compare the empty tree to `HEAD` without triple-dot merge-base syntax:

```text
git status --short -- . ':(exclude)<output_folder>'
git diff --stat 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- . ':(exclude)<output_folder>'
git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- . ':(exclude)<output_folder>'
git diff --cached -- . ':(exclude)<output_folder>'
git diff -- . ':(exclude)<output_folder>'
```

To guard tracked and staged repository content, capture `git diff` and `git diff --cached` immediately before and after any code-review command. If the before/after outputs differ, stop with `Status: blocked`, report the mutation diff to the user, and require the user to restore or stash those changes before resuming.

## Review Diff Budget

Code-review prompts carry the change through `<CCC_HOME>/scripts/ccc-diff-summary.sh <repo_root> <output_folder> <run_start_ref> --auto --budget <B>`, where `<B>` is `CCC_REVIEW_DIFF_BUDGET` (UTF-8 bytes, default `60000`). This output replaces the `git diff --cached`, `git diff`, and `ccc-untracked.sh --prompt` blocks in the prompt; keep `git status --short` so staged and unstaged state stays visible. The mutation guard is unchanged.

`CCC_REVIEW_DIFF_BUDGET=off` disables this section: use the separate `git diff --cached`, `git diff`, and untracked blocks from `## Git Review Baseline`.

The script diffs the working tree against `run_start_ref`, tracked and untracked, excluding the run folder, and prints `diff_mode: full` or `diff_mode: tiered` first.

* `full`: the whole diff fits the budget. Every file is shown in full. Nothing else changes.
* `tiered`: `source` and `test` files are **always** shown in full, whatever their size; they are never summarized. `docs` and `generated` (lock, vendored, build, minified) files are shown in full, smallest first, while the running total stays within the budget. `binary` files are never expanded. Everything else becomes a `=== file summary ...` entry with `+adds -dels`, byte size, class, and its hunk headers. Classes come from path and extension; set `CCC_REVIEW_SOURCE_GLOBS` (colon-separated `fnmatch` patterns, for example `protocol/*:skills/*/SKILL.md`) when Markdown or config files are the product. Files print in path order.

The budget counts raw diff bytes, not headers or summary lines. The prompt as a whole is still bounded by `CCC_REVIEW_PROMPT_MAX_BYTES`.

For each summarized file, the reviewer reply must contain exactly one of:

```text
NEED <json-path>
SKIP <json-path> — <reason>
```

A summarized file with neither line counts as `NEED`. If any file is `NEED`, the coordinator runs the script with `--hunks <json-path>...` and makes **one** follow-up call: the same prompt, the reviewer's first reply, the requested diffs, and `Give your final reply in the same format.` Log its size at `state/<stage>.prompt2.bytes`; the byte ceiling applies to it. Append both replies to the raw transcript, separated by `=== follow-up ===`. `NEED` lines in the follow-up reply are not served; those files stay unreviewed. Capture the mutation guard before the first call and after the last.

`review_vN.md` `## Diff Baseline` then records:

```text
diff_mode: full|tiered
skipped: none | <json-path>, ...
unreviewed: none | <json-path>, ...
```

`skipped` lists summarized files the reviewer waived with `SKIP` (docs, generated, binary only). `unreviewed` lists any `source` or `test` file the reviewer never saw in full; the tiered rules above make it `none`, and it exists as a guard. When `unreviewed` is not `none`, no approval verdict is allowed (`APPROVE`, `APPROVE_WITH_MINOR_COMMENTS`, or `APPROVE_AUTO_OVERRIDE`); use `NEEDS_CHANGES` or `BLOCKER`.

An in-session reviewer follows the same rules and may run `--hunks` directly instead of a follow-up call.

## Verdicts

All review artifacts use exactly one whole-line verdict:

```text
VERDICT: APPROVE
VERDICT: APPROVE_WITH_MINOR_COMMENTS
VERDICT: APPROVE_AUTO_OVERRIDE
VERDICT: NEEDS_CHANGES
VERDICT: BLOCKER
```

`APPROVE_AUTO_OVERRIDE` is machine-readable evidence that the coordinator proceeded in `auto` mode despite unresolved reviewer disagreement. It must include exactly one whole line beginning with `AUTO OVERRIDE:` in the artifact's `## Summary`.

Minor issues are non-material comments, nits, or follow-up suggestions that do not affect correctness, safety, data integrity, public contracts, user-visible behavior, or verification. Major issues affect one of those areas or make the result unsafe to judge. Findings must be tagged `[minor]` or `[major]`; ambiguous severity is major.

## Transitions

Planning:

```text
planner writes artifacts/plan_vN.md
coordinator writes state/plan_vN.done
coder reviews plan_vN and writes artifacts/plan_vN_review.md
coordinator writes state/plan_vN_review.done
```

If plan review approves, move to code. If it requests changes and another plan version is allowed, planner writes the next plan. If no version remains, follow the mode table.

Code:

```text
coder writes artifacts/code_vN.md
coordinator writes state/code_vN.done
planner reviews code_vN and writes artifacts/review_vN.md
coordinator writes state/review_vN.done
```

If code review approves, the workflow is complete. If it requests changes and another code version is allowed, coder writes the next code version. If no version remains, follow the mode table.

## Artifact Contracts

`plan_vN.md` required sections:

```text
# Plan vN
## Summary
## Scope
## Proposed Changes
## Files and Areas
## Verification Plan
## Risks and Questions
## Changes Since Previous Plan Version
```

`plan_v0.md` must write `Initial plan.` in `Changes Since Previous Plan Version`.

`plan_vN_review.md` required sections:

```text
# Plan vN Review
## Summary
## Findings
## Questions
## Verdict
```

Each `plan_vN_review.md` must have a corresponding non-empty raw transcript:

```text
state/plan_vN_review.review.raw.md
```

`code_vN.md` required sections:

```text
# Code vN
## Overview
## What Changed
## Implementation Details
## Files Changed
| File | Purpose |
|---|---|
## Git Baseline
## Verification
## Review Focus
## Risks and Unknowns
## Changes Since Previous Code Version
```

`## Git Baseline` must include:

```text
run_start_ref: <sha>
current_head: <sha|none>
```

`code_v0.md` must write `Initial implementation.` in `Changes Since Previous Code Version`.

Review artifacts are faithful indexes: `## Summary` is at most three lines including counts and raw path; `## Findings` has one line per ID and preserves severity/content. Use `none` for an empty required section.

`review_vN.md` required sections:

```text
# Review vN
## Summary
## Diff Baseline
## Findings
## Tests to Add
## Questions
## Verdict
```

`## Diff Baseline` must include:

```text
run_start_ref: <sha>
```

Each `review_vN.md` must have a corresponding non-empty raw transcript:

```text
state/review_vN.review.raw.md
```

## Write Ordering

For every stage, write files in this order:

```text
1. For reviewer stages, write state/<stage>.review.raw.md.tmp and atomically rename it to state/<stage>.review.raw.md.
2. Write artifacts/<stage>.md.tmp.
3. Validate the intended final artifact path and required raw transcript, when applicable.
4. Atomically rename artifacts/<stage>.md.tmp to artifacts/<stage>.md.
5. Write state/<stage>.done.tmp.
6. Atomically rename state/<stage>.done.tmp to state/<stage>.done.
7. Update run.md through a same-directory temporary file and atomic rename.
```

The `.done` file is the commit point for a stage.

## Validation Before .done

Before writing `.done`, validate:

```text
artifact exists
artifact is non-empty
expected top-level heading exists exactly once
required sections exist exactly as listed
review artifacts contain exactly one valid whole-line VERDICT
APPROVE_AUTO_OVERRIDE has exactly one whole "AUTO OVERRIDE:" line in ## Summary, and no other verdict uses "AUTO OVERRIDE:" lines
plan_v0 and code_v0 have required Changes Since text
code_vN Git Baseline contains run_start_ref and current_head
review_vN Diff Baseline SHA equals run_start_ref from run.md
plan_vN_review and review_vN have non-empty state/<stage>.review.raw.md files
```

Filename-to-heading validation is exact:

```text
plan_v(0|[1-9][0-9]*)\.md          -> # Plan v\1
plan_v(0|[1-9][0-9]*)_review\.md   -> # Plan v\1 Review
code_v(0|[1-9][0-9]*)\.md          -> # Code v\1
review_v(0|[1-9][0-9]*)\.md        -> # Review v\1
```

Only the coordinator writes `.done` files.

Done file content:

```text
---
stage: <stage>
artifact: artifacts/<artifact>.md
status: complete
---
Completed by CCC coordinator after artifact validation.
```

## Resume

`/ccc resume <output_folder>` reads `run.md`, `.done` files, artifact verdicts, and configured rounds, then continues from the next missing stage.

Resume must not infer workflow state only from `run.md`; `.done` files and artifact verdicts are the source of truth.

If an artifact exists without the matching `.done`, stop and ask the user to repair: rerun the stage, move the artifact aside, or manually validate it and write `.done` only if it satisfies this protocol. If `.done` exists without its artifact, the run is invalid and must be repaired before resume.

## Cancel

```text
/ccc cancel <output_folder> "<reason>"
```

The coordinator writes or updates `run.md` with `Status: canceled`, records the reason, and stops. Cancel does not delete artifacts.

## Validator

Use:

```text
<CCC_HOME>/scripts/ccc-validate.sh <output_folder>
```

## Final Output

Always end with:

```text
CCC run: <output_folder>
Stage completed: <stage|none>
Next action: <stage|complete|blocked|canceled>
```

## Stage Skills

Use:

```text
ccc
ccc-plan
ccc-plan-review
ccc-code
ccc-code-review
```
