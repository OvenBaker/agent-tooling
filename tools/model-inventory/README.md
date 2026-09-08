# Model inventory verification

`MODELS.md` at the repo root is a checked-in map of every place our code invokes an LLM. It is not a live
scan, so it rots the moment somebody changes a model string somewhere else. This directory is what keeps it
honest: a prompt, a runner script, and a `systemd --user` timer that runs the pair every 14 days.

## What it does

`run-verify.sh` pipes `verify-models.prompt.md` into `claude -p --model sonnet`. That session fans out one
read-only subagent per repo in the inventory, each confirming its rows against the actual code and grepping
for call sites nobody has recorded yet. Where it finds drift it updates `MODELS.md`, commits to a branch
named `chore/model-inventory-<YYYY-MM-DD>`, and stops. It never pushes, opens a PR, or merges.

Sonnet, not Fable or Opus: this is a grep-and-diff sweep, which is exactly the periodic work the house
orchestration rules put on the cheaper model.

## What surfaces, and when

A pass that only writes a log file has told nobody anything, so the script decides what the operator sees.
Two of the three outcomes become a **candidate work item in Orbital**, via `POST /api/items/report`. A
candidate is an ask, not an assignment: it goes on the to-do only if the operator accepts it, and ages out on
the ordinary window if he does not.

| Outcome | What the operator sees |
| --- | --- |
| The pass failed — non-zero exit, or it finished without writing its `MODEL-INVENTORY-REPORT` block | An item, "Model inventory verification failed on `<date>`", carrying the exit code and the last 20 log lines. The unit also exits non-zero, so `systemctl --user status` agrees with the item. |
| The pass found drift and committed it to `chore/model-inventory-<date>` | An item, "Model inventory drift found `<date>` — review branch `chore/model-inventory-<date>`", carrying the confirmed/drifted/new/retired counts. A branch nobody knows about is the same failure class as a silent failure, which is why this one is surfaced at all. |
| The pass ran and nothing drifted | Nothing. The log is the record. |

The mint is idempotent on `(source, sourceId)`, so a retried unit or a resent report converges on the row that
already exists. The failure case and the drift case use **different** `sourceId`s (`model-inventory-verify:`
and `model-inventory-drift:`) deliberately: sharing one key would mean a morning failure silently swallowed
an afternoon re-run's drift report.

If the POST itself fails, that goes in the log and the script exits non-zero, so systemd marks the unit failed
and the journal carries it. A surfacing mechanism that can fail silently is worthless.

## Where the log is

`~/.local/share/model-inventory/verify-<YYYY-MM-DD>.log`, one per run date. Override with
`MODEL_INVENTORY_LOG_DIR`. The Orbital base URL can be overridden with `ORBITAL_URL`; it defaults to
`https://orbital.20east.io`.

## Trying it without running the model

`--dry-run` skips the `claude` call and the POST entirely, and prints the decision plus the exact curl it
would send with the Cloudflare Access credentials redacted:

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
   repo, no push, no PR, no merge), not anything the harness enforces.
2. The Orbital route the script posts to, `POST /api/items/report`, is on Orbital's `main` but is **not live
   until Orbital is deployed**. Until then the failure and drift branches will get an HTTP 404 and the unit
   will exit non-zero, which is at least loud.

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
| `verify-models.prompt.md` | The prompt the pass runs. Ends with a required machine-readable `MODEL-INVENTORY-REPORT` block that the script reads to decide what to surface. |
| `run-verify.sh` | What the unit executes: runs the pass, logs it, decides the outcome, posts the item. |
| `model-inventory-verify.service` | The oneshot unit. |
| `model-inventory-verify.timer` | Every 14 days from the last activation, with a boot catch-up. |
