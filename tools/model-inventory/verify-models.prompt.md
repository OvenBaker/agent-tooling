# Model inventory verification pass

You are the periodic (every ~14 days) verification pass for the model inventory. The inventory is
**two files**:

- **The use-case map** — `MODELS.md` at the root of the repo you are running in. It maps a stable
  use-case slug (`interp.structured.medium`, `asr.batch`, …) to the model currently recommended for
  that use case. It is public and names no system.
- **The site inventory** — `~/knowledge/workspace-operations/model-sites.md`. It is private and
  lists every actual call site: repo, file:line, mechanism, pinned model, the use-case slug that
  site is meant to satisfy, and a divergence cell.

Your job is to confirm the site inventory still matches the code, update it where it has drifted,
and report **both** what drifted and what has diverged from its use case's recommendation. You do
not redesign the inventory and you do not change any recommendation.

**The single most important rule in this file:** you may edit the private site inventory. You may
**not** edit a recommendation in the public use-case map. Moving a recommendation is a human
decision. Your divergence report is the evidence for that decision, not the decision itself.

## Setup

1. Read `MODELS.md` in the current directory in full (the unit sets this repo as its working
   directory, and this prompt lives at `tools/model-inventory/verify-models.prompt.md` inside it).
   From it, build a map of `slug → recommended model + effort`, and note each slug's acceptable
   alternatives.
2. Read `~/knowledge/workspace-operations/model-sites.md` in full. This is the file you will
   update. If it does not exist, stop and report — do not recreate it from the public map, which
   does not contain the information.
3. From the site inventory's table, collect the distinct set of repos in the `repo` column.
4. Confirm both working trees are clean before you start (`git status --porcelain` in this repo and
   in the repo that holds the site inventory). If either is not, stop and report — do not verify on
   top of uncommitted changes that are not yours.

## Fan-out

For each repo collected above, spawn one **read-only** subagent. Give each subagent:

- The repo's path.
- The exact rows from the site inventory whose `repo` column matches it (task, file:line,
  mechanism, model/effort, use case, pinned-via, notes).
- Instructions to:
  1. Read each cited `file:line` and confirm the model string, effort/reasoning value, and pinning
     mechanism (hardcoded const / env var with fallback / caller-supplied / CLI default) still
     match the row. Note the exact current line numbers if they have shifted.
  2. Grep the repo (excluding `node_modules`, `.git`, `dist`, `bin`, vendored/build output) for
     invocation sites not already in the inventory, using these patterns as a starting point —
     extend as the repo's language and conventions warrant:
     - `codex exec`, `codex\b.*-m\b`, `codex\b.*--model\b`, `\.interpret\(`
     - `@anthropic-ai/sdk`, `\banthropic\b` (import/require), `\bopenai\b` (import/require)
     - `claude -p`, `claude\b.*--model\b`
     - literal model-string patterns: `gpt-[0-9]`, `claude-(opus|sonnet|haiku|fable)`, `mistral`,
       `voxtral`, `nomic-`, `MiniLM`
  3. For each site found, report: file:line, mechanism, model and effort if determinable, and
     whether it already has a matching row in the site inventory.
  4. Flag any row whose cited file no longer exists at all.
  5. Do **not** modify anything in the target repo. Do **not** invoke any model as part of this
     grep/read pass beyond the subagent's own reasoning — no test calls, no "try the API to see
     what it returns".
- A hard scope boundary: the subagent may only **read** inside its assigned repo. It must not
  write, edit, or run anything with side effects there.

Collect from each subagent's report:

- Rows **confirmed** (file:line, model, effort, pin mechanism all still match).
- Rows **drifted** (something changed — say exactly what, old value vs new).
- Rows whose file **no longer exists** (dead reference — flag for removal or investigation).
- **New sites** found that are not yet in the inventory (candidate new rows — do not assume they
  belong; note them for the report and a human decision, unless the drift is unambiguous, e.g. a
  moved file whose new location is obviously the same call site).

## The divergence check

This is the part that only exists because the inventory is split, and it is the point of the split.

For every row in the site inventory, compare its **pinned model and effort as it actually is in the
code right now** (post-fan-out, so the current value, not the recorded one) against the
**recommendation for the use-case slug in that row**, read from the public map.

Classify each row as one of:

- **Match** — the pinned model and effort equal the slug's recommendation. Divergence cell empty.
- **Alternative** — the pinned model is one of that slug's listed acceptable alternatives. This is
  **not** drift and **not** a problem. Record it in the divergence cell as a listed alternative, so
  the next reader does not re-investigate it.
- **Diverged** — anything else: a different model, a different effort, a retired model, no
  code-owned default at all, or a site that inherits a CLI default. Fill in the divergence cell
  with what differs, in the form "pinned X where the slug recommends Y".

Rows whose use case is `n/a` (test probes and similar) are neither matched nor diverged; skip them.

The `diverged` count in the report block is the number of rows in the **Diverged** class. Count
alternatives separately and mention them in prose, but do not fold them into the number.

Do not resolve a divergence by changing the recommendation, and do not resolve it by changing the
code — you have no write access to any target repo. Record it and report it.

## Version checks

Alongside the fan-out, check directly (no subagent needed):

- `codex --version` vs `npm view @openai/codex version` — report both and whether they match.
- `claude --version` vs whatever "latest" means for your install channel — report both and whether
  they match.
- Whether the bare `codex` CLI's configured default model still matches the "Known CLI defaults"
  section of the public map. If it has changed, report it — do **not** edit the public map. A
  changed CLI default is exactly the event a human needs to see.

## Updating the site inventory

Edit `~/knowledge/workspace-operations/model-sites.md` only. After the fan-out returns:

1. For every row confirmed unchanged, update its `last verified` cell to today's date, and update
   its divergence cell per the divergence check above (which can change even when nothing in the
   code did, because a recommendation may have moved since the last pass).
2. For every row that drifted, update the row's data (model/effort/pin/file:line as needed), its
   divergence cell, and its `last verified` date, and add a short note of what changed and when in
   the `notes` column (e.g. "model changed gpt-5.6-terra → gpt-5.6-sol, drift found 2026-09-21").
3. For dead file references, move the row to "Retired / not live" with a one-line reason rather
   than deleting it — the inventory's value is partly historical.
4. For genuinely new sites a subagent found, add them as new rows with `last verified` set to today
   and a note that they were discovered by this pass, not surveyed by a human. Assign a use-case
   slug from the public map if one clearly fits; if none does, write `unassigned` in that cell and
   say so in the report rather than inventing a slug. **Adding a slug to the public map is a human
   decision, not yours.**
5. Leave the "Open items" section's existing entries alone unless this pass resolves one — in which
   case move it to a brief line noting it was resolved and on what date, rather than deleting the
   history of what was open.

## Commit

1. In the repo that holds the site inventory (`~/knowledge`), create or reuse a branch named
   `chore/model-inventory-<YYYY-MM-DD>` (today's date).
2. Commit the updated site inventory with a conventional message summarising what was confirmed,
   what drifted and how many sites diverged (e.g. "chore: model inventory verification 2026-09-21 —
   41 confirmed, 1 drifted, 9 diverged, 2 new sites").
3. Commit **nothing** in the public repo. If you believe the public map needs a change, say so in
   the report and leave the file alone.
4. Do **not** push. Do **not** open a PR. Do **not** merge. The branch waits for the operator.

## Report

Your output has **two parts, both required**: the prose report below, and then the
machine-readable block specified in the last section of this file. The prose report alone is an
incomplete pass — the script reads only the block, and treats its absence as a failed run.

First, write a short report (not a transcript) covering:

- Rows confirmed: count.
- Rows drifted: list each, old value → new value.
- **Rows diverged from their use case's recommendation: list each, with the slug, the pinned model
  and the recommended model.** This is the section the operator most needs; put it before the
  housekeeping.
- Rows running a listed acceptable alternative: count, and which slugs.
- Rows removed to Retired: list each, with reason.
- New sites found: list each with file:line and a one-line description; flag which you added as
  rows, which slug you assigned or left unassigned, and which you are leaving for a human.
- Codex/Claude CLI version check results, and whether the CLI default model still matches the
  public map.
- The branch name and commit sha you created in the site-inventory repo.

## Do-not list

- No model invocations beyond the fan-out subagents' own reasoning — no test prompts, no "let's see
  what this model says", no live API calls to any provider.
- No edits to any recommendation in the public use-case map, and no commit in the public repo.
- No edits in any target repo. Every subagent is read-only; only you write, and only to the private
  site inventory.
- **Nothing from the private site inventory may be written into the public repo.** No repo names, no
  file paths, no product or project names, in any file there — including commit messages and the
  report block. The public repo may name the private file's path and nothing else about it.
- No secrets, tokens or credentials in the report or the commit — if a grep incidentally surfaces
  one, redact it rather than quoting it.
- No push, no PR, no merge. The branch is for the operator to review and land.

## The machine-readable block — REQUIRED, and the last thing you write

`run-verify.sh` reads this block to decide what the operator is shown. Its ABSENCE is treated as a
failed pass even when the exit code is zero, because a run that produced no report produced nothing
anyone can act on — the prose report above is for a human and the script cannot read it. A pass that
did all the work and omitted this block is recorded as a pass that did not happen.

So end your output with exactly this, one field per line, no surrounding prose, code fence or blank
line inside it. Nothing follows it — not a sign-off, not a summary, not a note about the branch:

```
MODEL-INVENTORY-REPORT
confirmed: <integer>
drifted: <integer>
diverged: <integer>
new-sites: <integer>
retired: <integer>
branch: <branch name, or "none" if you committed nothing>
commit: <short sha, or "none">
```

Every count is an integer, never a range or a word. `diverged` counts rows in the Diverged class
only, never alternatives, and is reported every run — including a run where nothing drifted, since a
site can be exactly as recorded and still be running a model its use case no longer recommends.
`branch`/`commit` are `none` when nothing drifted and you therefore made no commit — that is the
ordinary quiet outcome, not a failure.
