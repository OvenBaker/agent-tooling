# Model inventory verification pass

You are running as the periodic (every ~14 days) verification pass for `MODELS.md`, the checked-in
inventory of every place our code invokes an LLM (Claude, Codex/GPT, Mistral, or a local model).
Your job is to confirm the inventory still matches reality, update it where it has drifted, and
report what changed. You do not redesign the inventory or add new policy — you verify and record.

## Setup

1. Read `MODELS.md` in the current directory (expected: `~/repos/agent-tooling/MODELS.md` — the unit sets the
   agent-tooling checkout as its working directory, and this prompt file lives at
   `tools/model-inventory/verify-models.prompt.md` inside it) in full.
2. From its Inventory table, collect the distinct set of repos referenced in the `repo` column.
3. Confirm `agent-tooling`'s own working tree is clean before you start
   (`git status --porcelain`). If it is not, stop and report — do not verify on top of uncommitted
   changes that aren't yours.

## Fan-out

For each repo collected above, spawn one **read-only** subagent. Give each subagent:

- The repo's path.
- The exact rows from `MODELS.md` whose `repo` column matches it (task, file:line, mechanism,
  model/effort, pinned-via, notes).
- Instructions to:
  1. Read each cited `file:line` and confirm the model string, effort/reasoning value, and pinning
     mechanism (hardcoded const / env var with fallback / caller-supplied / CLI default) still
     match the row. Note the exact current line numbers if they've shifted.
  2. Grep the repo (excluding `node_modules`, `.git`, `dist`, `bin`, vendored/build output) for
     invocation sites not already in the inventory, using these patterns as a starting point —
     extend as the repo's language/conventions warrant:
     - `codex exec`, `codex\b.*-m\b`, `codex\b.*--model\b`, `\.interpret\(`
     - `@anthropic-ai/sdk`, `\banthropic\b` (import/require), `\bopenai\b` (import/require)
     - `claude -p`, `claude\b.*--model\b`
     - literal model-string patterns: `gpt-[0-9]`, `claude-(opus|sonnet|haiku|fable)`, `mistral`,
       `voxtral`, `nomic-`, `MiniLM`
  3. For each site found, report: file:line, mechanism, model+effort if determinable, and whether
     it already has a matching row in `MODELS.md`.
  4. Flag any row whose cited file no longer exists at all.
  5. Do **not** modify anything in the target repo. Do **not** invoke any model as part of this
     grep/read pass beyond your own subagent reasoning — no test calls, no "try the API to see what
     it returns."
- A hard scope boundary: this subagent may only **read** inside its assigned repo. It must not
  write, edit, or run anything with side effects there.

Collect from each subagent's report:
- Rows **confirmed** (file:line, model, effort, pin mechanism all still match).
- Rows **drifted** (something changed — say exactly what, old value vs new).
- Rows whose file **no longer exists** (dead reference — flag for removal or investigation).
- **New sites** found that aren't yet in the inventory (candidate new rows — do not assume they
  belong; note them for the report and a human decision, unless the drift is unambiguous, e.g. a
  moved file whose new location is obviously the same call site).

## Version checks

Alongside the fan-out, directly check (these don't need a subagent):

- `codex --version` vs `npm view @openai/codex version` — report both and whether they match.
- `claude --version` vs whatever "latest" means for your install channel (check `claude --help`
  or the installed update mechanism) — report both and whether they match.
- Whether `~/.codex/config.toml`'s default model still matches the "Known defaults" section of
  `MODELS.md`.

## Updating MODELS.md

After the fan-out returns:

1. For every row confirmed unchanged, update its `last verified` cell to today's date (no other
   change).
2. For every row that drifted, update the row's data (model/effort/pin/file:line as needed) *and*
   its `last verified` date, and add a short note of what changed and when in the `notes` column
   (e.g. "model changed gpt-5.6-terra → gpt-5.6-sol, drift found 2026-09-21").
3. For dead file references, move the row to "Retired / not live" with a one-line reason, rather
   than deleting it outright — the inventory's value is partly historical.
4. For genuinely new sites a subagent found, add them as new rows with `last verified` set to
   today and a note that they were discovered by this pass, not surveyed by a human. Do not invent
   a task description you're not confident of — if the purpose of a new call site isn't obvious
   from the code, say so in the notes rather than guessing.
5. Leave the "Open items" section's existing entries alone unless this pass resolves one (e.g. a
   flagged discrepancy turns out to be intentional, or a dead timer is now confirmed removable) —
   in which case move it to a brief line noting it was resolved and on what date, rather than
   deleting the history of what was open.

## Commit

1. Create (or reuse, if already on it) a branch named `chore/model-inventory-<YYYY-MM-DD>` (today's
   date) in the `agent-tooling` repo.
2. Commit the updated `MODELS.md` with a message summarizing what was confirmed vs what drifted
   (e.g. "Model inventory verification 2026-09-21: 24 confirmed, 1 drifted (santa reranker), 2 new
   sites found").
3. Do **not** push. Do **not** open a PR. Do **not** merge to main. This branch waits for the
   operator to review.

## Report

Write a short report (not a transcript) covering:

- Rows confirmed: count.
- Rows drifted: list each, old value → new value.
- Rows removed to Retired: list each, with reason.
- New sites found: list each, with file:line and a one-line description; flag which ones you
  added as rows vs which you're leaving for a human to triage.
- Codex/Claude CLI version check results.
- The branch name and commit sha you created.

### The machine-readable block — REQUIRED, and the last thing you write

`run-verify.sh` reads this block to decide what the operator is shown. Its ABSENCE is treated as a failed
pass even when the exit code is zero, because a run that produced no report produced nothing anyone can act
on. So end your output with exactly this, one field per line, no surrounding prose, code fence or blank line
inside it:

```
MODEL-INVENTORY-REPORT
confirmed: <integer>
drifted: <integer>
new-sites: <integer>
retired: <integer>
branch: <branch name, or "none" if you committed nothing>
commit: <short sha, or "none">
```

Every count is an integer, never a range or a word. `branch`/`commit` are `none` when nothing drifted and you
therefore made no commit — that is the ordinary quiet outcome, not a failure.

## Do-not list

- No model invocations beyond the fan-out subagents' own reasoning — no test prompts, no "let's
  see what this model says," no live API calls to any provider.
- No edits outside `agent-tooling` (the repo this file and `MODELS.md` live in). Every subagent is
  read-only in its target repo; only the orchestrating pass writes, and only to `MODELS.md` inside
  `agent-tooling`.
- No secrets, tokens, or credentials in the report or the commit — if a grep incidentally surfaces
  one, redact it rather than quoting it.
- No push, no PR, no merge. The branch is for the operator to review and land themselves.
