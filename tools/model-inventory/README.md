# Model inventory verification

The model inventory is **two files**, deliberately:

- **`MODELS.md`** at the root of this repo — a map from a stable use-case slug to the model currently
  recommended for that use case. It is public, and it names no repo, path, host or product. Code names a
  slug and reads its model from its own config; this file is the source of truth for what the slug should
  currently map to.
- **A private site inventory**, outside this repo, at `~/knowledge/workspace-operations/model-sites.md` —
  every actual call site, with the repo, file:line, mechanism, pinned model, the slug it is meant to satisfy,
  and a divergence cell. Nothing in this repo quotes its contents; only its path appears here.

Neither file is a live scan, so both rot the moment somebody changes a model string somewhere else. This
directory is what keeps them honest: a prompt, a runner script, and a `systemd --user` timer that runs the
pair every 14 days.

## What it does

`run-verify.sh` pipes `verify-models.prompt.md` into `claude -p --model sonnet`. That session reads both
files, fans out one read-only subagent per repo in the site inventory, and confirms each row against the
actual code while grepping for call sites nobody has recorded yet.

Then it does the thing the split exists for: it compares every site's **actual** pinned model against the
**recommendation** for that site's use-case slug, and reports every one that has diverged. A site can be
exactly as recorded last cycle and still be running a model its use case no longer recommends — recording
drift alone would never catch that.

Where it finds drift it updates the private file, commits to a branch named `chore/model-inventory-<date>`
in the repo that holds it, and stops. It never pushes, opens a PR, or merges. It never edits a recommendation
in `MODELS.md`, and never commits in this repo: moving a recommendation is a human decision, and the
divergence report is its evidence.

Sonnet, not Fable or Opus: this is a grep-and-diff sweep, which is exactly the periodic work the house
orchestration rules put on the cheaper model.

## What surfaces, and when

A pass that only writes a log file has told nobody anything, so the script decides what the operator sees.
Two of the three outcomes become a **candidate work item in the work tracker**, via `POST /api/items/report`.
A candidate is an ask, not an assignment: it goes on the to-do only if the operator accepts it, and ages out
on the ordinary window if he does not.

| Outcome | What the operator sees |
| --- | --- |
| The pass failed — non-zero exit, or it finished without writing its `MODEL-INVENTORY-REPORT` block, or wrote one that is incomplete (a missing field, a count that is not an integer, an unfilled `<placeholder>`) | An item, "Model inventory verification failed on `<date>`", naming which of those it was, and carrying the exit code and the last 20 log lines. The unit also exits non-zero, so `systemctl --user status` agrees with the item. |
| The pass found drift and committed it to `chore/model-inventory-<date>` | An item, "Model inventory drift found `<date>` — review branch `chore/model-inventory-<date>`", carrying the confirmed/drifted/diverged/new/retired counts. A branch nobody knows about is the same failure class as a silent failure, which is why this one is surfaced at all. |
| The pass ran and nothing drifted | Nothing. The log is the record, and it carries the diverged count. |

The diverged count rides along on the drift item and on the quiet log line rather than minting an item of its
own. Divergence is a standing condition, not an event: a handful of sites are expected to sit away from their
recommendation at any time, and an item per cycle for a condition nobody has decided to change yet is noise.

The mint is idempotent on `(source, sourceId)`, so a retried unit or a resent report converges on the row that
already exists. The failure case and the drift case use **different** `sourceId`s (`model-inventory-verify:`
and `model-inventory-drift:`) deliberately: sharing one key would mean a morning failure silently swallowed
an afternoon re-run's drift report.

Re-running on the same day is the ordinary way to recover from a failed pass, and the log is one file per
date, so a re-run appends beneath the run that failed. The script reads the report block only from the part
of the log **its own run** wrote, never from an earlier one — otherwise a re-run that died without writing a
block would find the earlier run's block still sitting in the file and be surfaced as that run's success. For
the same reason the block is checked for completeness, not merely for presence: a bare marker line, or the
block's own template echoed back with its `<placeholder>` values intact, is enough to make the block look
present, and accepting it would exit 0 and record the inventory as verified for a cycle nobody verified.

If the POST itself fails, that goes in the log and the script exits non-zero, so systemd marks the unit failed
and the journal carries it. A surfacing mechanism that can fail silently is worthless.

## Private configuration

This repo is public, so the deployment facts the runner needs are not in it. They live in
`~/.config/model-inventory/config.env`, which is read at startup and holds:

| Variable | What it is |
| --- | --- |
| `MODEL_INVENTORY_TRACKER_URL` | Base URL of the work tracker the item is posted to. |
| `MODEL_INVENTORY_PROJECT_REF` | The project the item is filed under. |
| `MODEL_INVENTORY_SITES_REPO` | The repo holding the private site inventory, where the drift branch is created. Defaults to this repo if unset, so a missing config degrades to "look here" rather than to a crash. |
| `MODEL_INVENTORY_CF_ID_VAR` / `MODEL_INVENTORY_CF_SECRET_VAR` | The **names** of the Access credential variables to read from `~/.env`. |

No secret is copied into that file. It names which variables to read; `~/.env` still holds the values, and
they are passed to curl through a config file on stdin so they never reach the process table. Override the
config's location with `MODEL_INVENTORY_CONFIG`.

## Where the log is

`~/.local/share/model-inventory/verify-<YYYY-MM-DD>.log`, one per run date. Override with
`MODEL_INVENTORY_LOG_DIR`.

## Trying it without running the model

`--dry-run` skips the `claude` call and the POST entirely, and prints the decision plus the exact curl it
would send with the Access credentials redacted:

```
./tools/model-inventory/run-verify.sh --dry-run 1          # the failure branch
./tools/model-inventory/run-verify.sh --dry-run 0 drift    # the drift branch
./tools/model-inventory/run-verify.sh --dry-run 0          # the quiet branch, surfaces nothing
```

## Installing

**Not installed by default, and installing it is the operator's call.** Two things to know first:

1. `run-verify.sh` runs `claude` with `--dangerously-skip-permissions`. That is required for unattended use —
   there is no human to answer a permission prompt at 05:00 — and it grants the session full tool access with
   no per-call gate. What holds the scope is the prompt's own do-not list (read-only subagents in every target
   repo, no edits to the public map, no push, no PR, no merge), not anything the harness enforces.
2. The tracker route the script posts to, `POST /api/items/report`, may not be live until the tracker is
   deployed. Until then the failure and drift branches get an HTTP 404 and the unit exits non-zero, which is
   at least loud.

```sh
mkdir -p ~/.config/systemd/user
ln -sf ~/repos/agent-tooling/tools/model-inventory/model-inventory-verify.service ~/.config/systemd/user/
ln -sf ~/repos/agent-tooling/tools/model-inventory/model-inventory-verify.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now model-inventory-verify.timer
```

Check it, run it by hand, or stop it:

```sh
systemctl --user list-timers model-inventory-verify.timer
systemctl --user start model-inventory-verify.service   # run one pass now
systemctl --user status model-inventory-verify.service
systemctl --user disable --now model-inventory-verify.timer
```

`systemd --user` does not inherit a login shell's PATH, and `claude`, `node` and `jq` all live in
`~/.local/bin` on this machine. Both the unit and the script prepend it; if you move the Claude install, fix
it in both places.

## Files

| File | What it is |
| --- | --- |
| `verify-models.prompt.md` | The prompt the pass runs. Reads both files, fans out per repo, updates the private one, and ends with a required machine-readable `MODEL-INVENTORY-REPORT` block that the script reads to decide what to surface. |
| `run-verify.sh` | What the unit executes: runs the pass, logs it, decides the outcome, posts the item. |
| `model-inventory-verify.service` | The oneshot unit. |
| `model-inventory-verify.timer` | Every 14 days from the last activation, with a boot catch-up. |
