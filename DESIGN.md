# CCC Design

CCC is a file-based protocol for making one incremental code change safer through structured cross-review between Claude Code and Codex. This document covers the design rationale, full configuration, runtime contract, and related work. The canonical protocol lives in [protocol/CCC_PROTOCOL.md](protocol/CCC_PROTOCOL.md).

## Design Rationale

Most coding-agent projects are either single-agent editing tools or broad multi-agent frameworks. CCC is deliberately specific:

- **Planning and implementation are configurable.** Use the default `claude-codex`, reverse it with `codex-claude`, or run same-agent protocol-discipline loops.
- **The current session is the coordinator.** Coordinate from Claude or Codex without changing the artifact contract.
- **Artifacts are the interface.** Plans, reviews, code summaries, raw transcripts, and `.done` sentinels live in the run folder.
- **Review is bounded.** Rounds are explicit, so disagreement terminates as `blocked`, `complete`, or `APPROVE_AUTO_OVERRIDE` instead of looping forever.
- **No framework runtime is required.** CCC is a protocol plus skills and shell scripts, not a daemon, service, database, or graph engine.
- **The reviewer receives a self-contained prompt.** The coordinator includes the relevant task, artifacts, and git outputs, so review does not depend on hidden session memory.

## Configuration

Optional arguments may appear in any order.

| Argument | Values | Default |
|---|---|---|
| `plan-code=...` | `claude-codex`, `codex-claude`, `claude-claude`, `codex-codex` | `plan-code=claude-codex` |
| rounds | `p1-c1`, `p2-c2`, `p3-c2`, etc. | `p2-c2` |
| mode | `manual`, `normal`, `auto` | `normal` |
| `caveman=...` | `off`, `lite`, `full`, `ultra` | `caveman=off` |

Stages owned by the current coordinator session run directly. Stages owned by the other agent use a CLI subprocess and consume prompt budget.

`plan-code=<planner>-<coder>` controls ownership:

| Stage | Owner |
|---|---|
| `plan_vN` | planner |
| `plan_vN_review` | coder |
| `code_vN` | coder |
| `review_vN` | planner |

Examples:

| Config | Behavior |
|---|---|
| `plan-code=claude-codex` | Claude plans and reviews code; Codex reviews plans and implements. |
| `plan-code=codex-claude` | Codex plans and reviews code; Claude reviews plans and implements. |
| `plan-code=claude-claude` | Claude owns every stage. Protocol-discipline-only mode, not cross-model review. |
| `plan-code=codex-codex` | Codex owns every stage. Protocol-discipline-only mode, not cross-model review. |

Modes:

| Mode | Behavior |
|---|---|
| `manual` | Stop for user approval after each completed stage. |
| `normal` | Keep running, but block for human direction on major unresolved disagreement. |
| `auto` | Continue through reviewer disagreement and use `VERDICT: APPROVE_AUTO_OVERRIDE` at the final allowed version. Hard infrastructure or protocol failures still block. |

## CCC Home

The skills are the installed unit, but they do not carry the protocol as prose — each `SKILL.md` reads `<CCC_HOME>/protocol/CCC_PROTOCOL.md` and runs `<CCC_HOME>/scripts/*.sh`. `<CCC_HOME>` resolves from `$CCC_HOME`, else the invoked skill's own directory, else a `ccc-duet` checkout root — the first one containing `protocol/CCC_PROTOCOL.md`.

To make the second option hold, every `skills/<name>/` carries `protocol/` and `scripts/` as relative symlinks to the checkout root. The single canonical copy stays at the repository root, so there is nothing to keep in sync, and an installed skill directory is self-sufficient.

Two consequences worth stating:

- `<CCC_HOME>` is not the target repository. Reviewer CLI calls run from the target repository root; protocol and script paths never do.
- A hand-rolled `cp -R skills/<name>` produces dangling symlinks and a run with no protocol. Use `scripts/ccc-install.sh` (`--link` to track the checkout, `--copy` to dereference into a standalone install) and `scripts/ccc-check-install.sh` to verify. CI runs both modes.

When `<CCC_HOME>` cannot be resolved, CCC stops as `blocked`. It does not reconstruct the protocol, an artifact contract, or a prompt template from model memory — an unverifiable improvised contract is worse than a stopped run.

## Environment Variables

| Variable | Values | Purpose |
|---|---|---|
| `CCC_PLAN_CODE` | `claude-codex`, `codex-claude`, `claude-claude`, `codex-codex` | Default stage assignment when `plan-code=...` is omitted. |
| `CCC_REVIEW_PROMPT_MAX_BYTES` | integer byte limit | Maximum UTF-8 byte length of a cross-agent review prompt. Default: `200000`. |
| `CCC_CAVEMAN` | `off`, `lite`, `full`, `ultra` | Default caveman level when `caveman=...` is omitted on a new run. |
| `CCC_CAVEMAN_SKILL` | absolute path | caveman `SKILL.md` to use instead of the installed one. |
| `CCC_REVIEW_DIFF_BUDGET` | integer bytes, or `off` | Diff size above which code-review prompts switch to tiered mode (full diffs for top-priority files, summaries for the rest). Default: `60000`. |
| `CCC_REVIEW_SOURCE_GLOBS` | colon-separated `fnmatch` patterns | Paths that tiered review must treat as source (for repos whose product is Markdown or config). |
| `CCC_HOME` | absolute path | Directory holding `protocol/CCC_PROTOCOL.md` and `scripts/`. Overrides skill-directory resolution; useful when the skills are installed as copies but you want them to track a checkout. |

Values are case-sensitive. Invalid values are treated as absent.

`<CCC_HOME>/scripts/ccc-detect-session.sh` infers the current session:

```text
CLAUDECODE=1 or CLAUDE_CODE_SESSION_ID present -> claude
CODEX_CI=1 -> codex
both present -> unknown
otherwise -> unknown
```

Detection is diagnostic. The current session remains the coordinator.

## Run Metadata

`run.md` records:

```text
planner: <claude|codex>
coder: <claude|codex>
plan_code: <claude-codex|codex-claude|claude-claude|codex-codex>
session_detected: <claude|codex|unknown>
plan_code_source: <explicit|env|default|persisted>
ccc_home: <absolute path>          # optional provenance
```

On resume, persisted values are reused unless explicitly overridden.

`ccc_home` is optional and unvalidated; it records which CCC install drove the run.

## Review Contract

All cross-agent calls use a self-contained prompt. The coordinator includes the task, relevant CCC artifacts, and relevant git outputs. The reviewer output is captured as:

```text
state/plan_vN_review.review.raw.md
state/review_vN.review.raw.md
```

This symmetry is a tradeoff: the reviewer does not independently re-derive the whole changeset. Review integrity depends on the coordinator assembling the prompt faithfully, preserving the raw transcript, and using the pre/post git-diff mutation guard around code review commands.

CCC blocks instead of silently truncating when the UTF-8 byte length of the full stdin payload exceeds `CCC_REVIEW_PROMPT_MAX_BYTES`.

## Token Efficiency

Most savings are structural and always on: finding and question IDs make review handoffs addressable, later rounds send the current artifact plus the prior review's findings instead of whole prior versions, cross-agent prompts embed only the protocol sections a stage needs (`scripts/ccc-protocol-sections.sh`, with a `protocol_sha256`), prompts put stable content first for provider prompt caching, and `state/<stage>.prompt.bytes` makes the cost measurable.

Prose compression is **opt-in**. `caveman=lite|full|ultra` applies the [caveman](https://github.com/JuliusBrussee/caveman) skill to plan, code-summary, and review artifacts, cross-agent prompts, and reviewer replies. The default is `caveman=off` because compressed prose can degrade model reasoning and drop nuance, and CCC optimizes for plan and code quality first. Raw transcripts, `task.md`, `run.md`, code, comments, repository docs, and messages to the user are never compressed. Caveman's own guidance keeps persisted files in normal prose; CCC deliberately overrides that only for its own agent-to-agent artifacts, and only when a run opts in.

`scripts/ccc-install.sh` installs caveman's `skills/caveman/SKILL.md` pinned by commit and SHA-256 and writes a `.ccc-pin` record; `scripts/ccc-check-install.sh` reports it and flags a modified pinned copy. A failed download only warns, since `caveman=off` runs do not need it; a run that asks for a level without the skill blocks at start. Bumping the pin means reviewing upstream and updating `CAVEMAN_REF` and `CAVEMAN_SHA256` together.

Large diffs are budgeted (`scripts/ccc-diff-summary.sh`, `CCC_REVIEW_DIFF_BUDGET`, default 60000 raw diff bytes). Under the budget the reviewer sees every file in full, so small changes are unaffected. Over it, source and test files are still always shown in full; only docs, generated/lock/vendored files, and binaries can be reduced to stats plus hunk headers. The reviewer must `NEED` or `SKIP` each summarized file, and `NEED` is served in one follow-up call. This keeps review quality for code intact: the savings come only from files where a line-by-line read rarely finds bugs. A validator guard refuses any approval verdict if a source or test file is recorded as `unreviewed`. Repositories whose product is Markdown or config mark those paths as source with `CCC_REVIEW_SOURCE_GLOBS`.

Code reviews also include a deterministic untracked-file block (`scripts/ccc-untracked.sh`); its manifest (SHA, size, `st_mode`, kind) is compared before and after the reviewer runs, so content, permission, or type changes to new files block the run.

## Rules

Only one coordinator session should be active for a given output folder.

Do not commit during an active CCC run. Commit only after the run reaches a terminal state.

Reviewer commands must not mutate tracked or staged repository content. CCC captures `git diff` and `git diff --cached` before and after code review commands and blocks if they differ.

## Related Work

CCC sits near several existing coding-agent projects, but it has a narrower target than most of them: structured cross-review for one incremental change.

| Project | What It Is Good At | How CCC Differs |
|---|---|---|
| [OpenHands](https://github.com/All-Hands-AI/OpenHands) | autonomous software-engineering agents, sandboxed execution, SWE-style tasks | CCC is not a full autonomous agent runtime; it coordinates one bounded Claude/Codex change loop. |
| [Aider](https://github.com/Aider-AI/aider) | practical git-aware pair programming with strong editing UX | CCC separates planning, coding, and review ownership into explicit artifacts. |
| Aider architect/editor patterns | splitting planning and editing across model roles | CCC specializes the pattern for Claude Code and Codex with explicit review rounds and verdicts. |
| [AutoGen](https://github.com/microsoft/autogen) | general multi-agent conversations and tool orchestration | CCC is not a framework; it is a concrete protocol for a specific coding workflow. |
| [LangGraph](https://github.com/langchain-ai/langgraph) | state-machine and graph orchestration for long-running agents | CCC uses plain files and shell-callable CLIs instead of requiring a graph runtime. |
| [MetaGPT](https://github.com/FoundationAgents/MetaGPT) | role-specialized software-company-style agent pipelines | CCC avoids broad role simulation and focuses on one implementation/review loop. |
| [ChatDev](https://github.com/OpenBMB/ChatDev) | research-style multi-agent software conversations | CCC is designed for real repository diffs, git baselines, validator checks, and CLI integration. |

The closest conceptual shape is a generator-reviewer loop:

```text
planner -> plan -> coder review -> coder implementation -> planner review -> revision or verdict
```

CCC keeps that shape small and concrete: one coordinator, two configurable stage owners, one run folder, one incremental change.
