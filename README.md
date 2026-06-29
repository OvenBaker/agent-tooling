# agent-tooling

Three small tools for running, watching, and searching **fleets of Claude Code and
Codex sessions**. They were built for one person's day-to-day workflow on **WSL +
Windows Terminal**, and they're shared *warts and all* — expect hardcoded
assumptions, WSL-isms, and rough edges. Nothing here is a product; it's a working
setup you're welcome to lift, fork, or cannibalise.

```
                         ┌───────────────────────────┐
   ~/.claude/projects ──▶│      santa  (search)      │  semantic search + resume
   ~/.codex/sessions  ──▶│  indexes every transcript │  over your whole history
                         └────────────┬──────────────┘
                                      │ "resume this session"
                                      ▼
                         ┌───────────────────────────┐
                         │     cockpit  (control)    │  many live sessions in one
                         │  tmux grid of live panes  │  colour-coded tmux grid
                         └────────────┬──────────────┘
                                      │ "open N agents as a workspace"
                                      ▼
                         ┌───────────────────────────┐
                         │ agent-fusion (multi-agent)│ Claude + Codex on one task,
                         │   blind-first, then fuse  │  output fused
                         └───────────────────────────┘
```

They're independently useful, but they compose: **santa** finds and resumes
sessions, **cockpit** is the grid you resume them into, and **agent-fusion**
launches multi-agent runs *as* cockpit workspaces.

## The three repos

| Repo | Language | One-liner |
|------|----------|-----------|
| **[santa](https://github.com/OvenBaker/santa)** | C# / .NET 10 | Local semantic search + browse + resume over all your Claude & Codex transcripts. Embeddings + reranker run fully on-device. |
| **[cockpit](https://github.com/OvenBaker/cockpit)** | Bash + tmux | A control surface that resumes several unfinished sessions into one titled, colour-coded, live-state tmux grid you steer from the keyboard. |
| **[agent-fusion](https://github.com/OvenBaker/agent-fusion)** | Bash + a protocol doc | Runs 2–3 independent agents (Claude/Opus + Codex/GPT) on one task and **fuses** their output. The filesystem is the coordination bus. |

Each repo has its own README with the real detail. This one is just the map.

## Quick start

You don't need all three. Pick what's useful. Rough order of dependencies:
**santa** stands alone → **cockpit** is best with santa → **agent-fusion** wants
cockpit + the `claude`/`codex` CLIs.

```bash
# 1. santa — search your history          (needs the .NET 10 SDK)
git clone https://github.com/OvenBaker/santa && cd santa
./install.sh && santa refresh && santa query "that postgres migration we argued about"

# 2. cockpit — drive many sessions at once (needs tmux ≥3.4, jq, sqlite3)
git clone https://github.com/OvenBaker/cockpit
export PATH="$PWD/cockpit:$PATH" && cockpit

# 3. agent-fusion — multi-agent runs
git clone https://github.com/OvenBaker/agent-fusion && cd agent-fusion
./fusion --mode A <slug> task.md --dry-run    # preview prompts, spawn nothing
```

## Dependencies (consolidated)

| Need | For | Notes |
|------|-----|-------|
| **.NET 10 SDK** | santa build | `install.sh` does a single-file `dotnet publish`. |
| **bash, tmux ≥3.4, jq, sqlite3** | cockpit | Core runtime. |
| **`claude` CLI** | cockpit, agent-fusion | [Claude Code](https://docs.claude.com/en/docs/claude-code). |
| **`codex` CLI** | cockpit, agent-fusion (optional) | Only if you want Codex sessions tracked / fused. |
| **WSL + Windows Terminal** | cockpit (assumed) | The `shim/wt.exe` trick is WSL-specific; see the warts below. |
| **Internet, first run only** | santa | Pulls embed/rerank models (HuggingFace) + the `sqlite-vec` extension (GitHub). All on-device after that. |

## Warts & assumptions (read before you judge it)

- **WSL-centric.** cockpit assumes WSL + Windows Terminal; `shim/wt.exe` is a
  stand-in so santa's resume can hand a session to cockpit. On bare Linux the grid
  still works, but the `wt.exe` integration and a couple of paths will need
  adjusting.
- **agent-fusion is coupled to cockpit for *launching* only.** The protocol
  (`agent-fusion.md`) and the coordination lib (`fusion-lib.sh`) are pure
  filesystem and tmux-agnostic. `--dry-run` prints each agent's prompt so you can
  run a fusion by hand in any N terminals, no cockpit required.
- **agent-fusion's launcher pre-trusts the run dir.** It writes
  `trust`/`hasTrustDialogAccepted` records into `~/.codex/config.toml` and
  `~/.claude.json` so fresh run dirs don't stall on the CLI's "do you trust this
  folder?" prompt. Convenient, but it's a security decision made on your behalf —
  read `fusion` before running it unattended.
- **santa indexes everything you've ever said to Claude/Codex.** The index DB is
  local-only and gitignored; just know it exists and where it lives
  (`~/.local/share/santa/`).
- **GPU is optional.** santa ships CUDA onnxruntime providers but falls back to CPU.
  Embedding a large history on CPU is slower but fine.
- **Hardcoded niceties.** Default model IDs, the `tmux -L cockpit` socket name, the
  `~/agents` fusion home (override with `FUSION_DIR`), `~/.local/share/santa`
  (override with `SANTA_HOME`) — all editable, none parameterised behind a config
  UI. It's personal tooling.
- **No tests, no CI, no license file** (yet). Treat it accordingly.
