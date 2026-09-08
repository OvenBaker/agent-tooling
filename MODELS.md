# Model inventory

Every place our code invokes an LLM (Claude, Codex/GPT, Mistral, or a local ONNX model), as a
task-to-model map. This is not a live scan: it is a checked-in table, kept honest by a periodic
fan-out rather than a script.

## How this is maintained

- **Cadence:** every 14 days, a `systemd --user` timer runs `tools/model-inventory/verify-models.prompt.md`
  through `claude -p --model sonnet`, via `tools/model-inventory/run-verify.sh`. See
  `tools/model-inventory/README.md` for the units, the log location and what the pass surfaces in Orbital.
- **Mechanism:** the prompt spawns one read-only Sonnet subagent per repo listed below. Each
  subagent greps its repo for invocation sites (`codex exec`/`-m`/`--model`, `@anthropic-ai/sdk`,
  `anthropic`/`openai` imports, `claude -p`/`--model`, and literal `gpt-*`/`claude-*`/`mistral*`/
  `nomic*` model strings) and diffs what it finds against this file's rows.
- **No sweep script.** The fan-out *is* the verification; there is no separate automated crawler
  to keep in sync with this document.
- **The `last verified` column** is updated by that fan-out (or by hand, when a human edits a row
  outside the cadence) and should always carry a date, not "recently" or similar.
- **The rule every site here is expected to satisfy:** every LLM call site names its model
  *explicitly*, through a config value the code reads (a frozen constant, an env var with a
  code-owned default, or a caller-supplied parameter) — never by omission. Nothing is allowed to
  silently inherit a CLI's own default model. Rows below marked "bypasses invoker" or listed under
  "Retired / not live" are exactly the exceptions this rule exists to catch.

## Inventory

| Task | Repo | File:line | Mechanism | Model (effort) | Pinned via | Last verified | Notes |
|---|---|---|---|---|---|---|---|
| Routine project-knowledge interpretation | orbital | `src/config/sources.mjs:242-246` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `PROJECT_INTERPRETATION`, not env-overridable | 2026-09-07 (read) | |
| Day-plan ordering (advisory) | orbital | `src/config/sources.mjs:312-316` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `DAY_PLAN_INTERPRETATION` | 2026-09-07 (read) | |
| Brief-pause TUI-tail read (2nd fallback) | orbital | `src/config/sources.mjs:323-327` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `BRIEF_PAUSE_INTERPRETATION` | 2026-09-07 (read) | |
| Session-overseer ambiguous-fact fallback | orbital | `src/config/sources.mjs:332-336` | codex exec via invoker | gpt-5.6-luna (low) | frozen const `SESSION_OVERSEER_INTERPRETATION` | 2026-09-07 (read) | |
| Item triage ("Triage with agent") | orbital | `src/config/sources.mjs:343-347` | codex exec via invoker | gpt-5.6-terra (low) | frozen const `ITEM_TRIAGE_INTERPRETATION` | 2026-09-07 (read) | |
| Gargoyle: ask judge (what reaches the list) | orbital | `src/config/sources.mjs:358-362` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `SLACK_ASK_INTERPRETATION` | 2026-09-07 (read) | raised from low after eval, 2026-09-05 |
| Gargoyle: moot judge (what comes off the list) | orbital | `src/config/sources.mjs:369-373` | codex exec via invoker | gpt-5.6-terra (low) | frozen const `MOOT_INTERPRETATION` | 2026-09-07 (read) | chosen on false-positive rate, not raw accuracy |
| Gargoyle: convergence judge (same ask or new) | orbital | `src/config/sources.mjs:382-386` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `SLACK_CONVERGE_INTERPRETATION` | 2026-09-07 (read) | |
| Orb context-card expansion | orbital | `src/config/sources.mjs:405-409` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `ORB_CARD_INTERPRETATION` | 2026-09-07 (read) | |
| Voice field-fill (spoken → form fields) | orbital | `src/config/sources.mjs:413-417` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `VOICE_FILL_INTERPRETATION` | 2026-09-07 (read) | |
| Transcript polish (casing/punctuation only) | orbital | `src/config/sources.mjs:421-425` | codex exec via invoker | gpt-5.6-luna (medium) | frozen const `TRANSCRIPT_POLISH_INTERPRETATION` | 2026-09-07 (read) | code-enforced lexical invariant after generation |
| Common conversational lane | orbital | `src/config/sources.mjs:427-432` | codex exec via invoker | gpt-5.6-luna (medium) | frozen const `CONVERSATION_INTERPRETATION` | 2026-09-07 (read) | service tier separately configurable (fast/standard) |
| Choir agenda prep — evidence normalization | orbital | `src/config/sources.mjs:436-439` | codex exec via invoker | gpt-5.6-terra (medium) | frozen const `CHOIR_PREPARATION.evidence` | 2026-09-07 (read) | |
| Choir agenda prep — editorial agenda judgment | orbital | `src/config/sources.mjs:436-439` | codex exec via invoker | gpt-5.6-sol (high) | frozen const `CHOIR_PREPARATION.agenda` | 2026-09-07 (read) | |
| Choir evidence-origin change proposer | orbital | `src/config/sources.mjs:446-450` | codex exec via invoker | gpt-5.6-sol (high) | frozen const `CHOIR_EVIDENCE_REVIEW_INTERPRETATION` | 2026-09-07 (read) | **zero live consumers** — see Open items |
| Orderly: general drafting run | orbital | `tools/orderly/run.mjs:46,96` | codex exec, bypasses invoker | gpt-5.6-terra | const default, env `ORBITAL_ORDERLY_MODEL` overrides | 2026-09-07 (read) | |
| Orderly: extraction run | orbital | `tools/orderly/extract.mjs:45,96` | codex exec, bypasses invoker | gpt-5.6-sol | const default, env `ORBITAL_EXTRACTION_MODEL` overrides | 2026-09-07 (read) | |
| Investigation service — plan stage | orbital | `src/investigation/service.mjs:41` | codex exec, bypasses invoker | gpt-5.6-sol (high) | hardcoded literal per call | 2026-09-07 (read) | |
| Investigation service — investigate stage | orbital | `src/investigation/service.mjs:46` | codex exec, bypasses invoker | gpt-5.6-luna | hardcoded literal per call | 2026-09-07 (read) | effort not set at this call |
| Investigation service — synthesize stage | orbital | `src/investigation/service.mjs:48` | codex exec, bypasses invoker | gpt-5.6-sol (high) | hardcoded literal per call | 2026-09-07 (read) | |
| Conversation API — "blacksmith" investigate stage | orbital | `src/api/conversations.mjs:77` | codex exec, bypasses invoker | gpt-5.6-luna (medium) | hardcoded literal | 2026-09-07 (read) | |
| Voice transcription (batch ASR) | orbital | `src/voice/transcribe.mjs` + `src/config/sources.mjs:848-853` | Mistral audio API, raw fetch | mistral voxtral-mini-latest | const default, env `ORBITAL_VOICE_MODEL` | 2026-09-07 (read) | provider/model likewise env-overridable here (not code-frozen like the interpretation tiers) |
| Voice transcription (realtime) | orbital | `src/config/sources.mjs:857-872` | Mistral audio websocket | mistral voxtral-mini-transcribe-realtime-2602 | frozen const `VOICE_REALTIME`, not env-overridable | 2026-09-07 (read) | |
| Choir Herald (low-latency turn selector) | orbital | `src/choir/herald-provider.mjs` + `src/config/sources.mjs:904-910` | Mistral chat completions, raw fetch | mistral-small-latest | frozen const `CHOIR_HERALD`, not env-overridable | 2026-09-07 (read) | changes conversation state, deliberately not deployment-tunable |
| Nightly document-plot opinion pass | shepherd | `src/Shepherd.Core/Opinion/CodexOpinionProvider.cs:20,24,48` | `codex exec --ephemeral` | gpt-5.6-terra (medium) | const `DefaultModel`, env `SHEPHERD_CODEX_MODEL` overrides; binary path via `SHEPHERD_CODEX_PATH` | 2026-09-07 (read) | invoked nightly via crontab `30 5 * * *` → `tools/nightly-refresh.sh` (confirmed in crontab) |
| Local embedding (shepherd's own index) | shepherd | `src/Shepherd.Core/Embedding/EmbedderConfig.cs:19` | local ONNX | nomic-ai/nomic-embed-text-v1.5 | hardcoded `ModelId` | 2026-09-07 (read) | |
| Local reranking (shepherd's own index) | shepherd | `src/Shepherd.Core/Embedding/RerankerConfig.cs:16` | local ONNX | cross-encoder/ms-marco-MiniLM-L12-v2 | hardcoded `ModelId` | 2026-09-07 (read) | see Open items — santa's copy uses a different HF org for the same model |
| Session summaries / non-agent classification (fallback when Claude overloaded) | santa | `src/Santa.Core/Classify/CodexCliRunner.cs:23-24` | `codex exec --ephemeral -m` | gpt-5.5 (default) | const default, env `SANTA_CODEX_MODEL` overrides | 2026-09-07 (read) | comment notes gpt-5.5-mini/-fast not offered on this ChatGPT account |
| Agent classification / summarization router | santa | `src/Santa.Core/Classify/ClaudeCliRunner.cs:46-47` | `claude -p --model` | caller-supplied (no default in this file) | router env `SANTA_SUMMARIZER` picks the value passed in | 2026-09-07 (read) | `--model` flag only added `if (!string.IsNullOrEmpty(req.Model))` — an empty/unset value silently omits `--model`, i.e. falls through to the `claude` CLI's own default; see Open items |
| Local embedding (santa's own index) | santa | `src/Santa.Core/Embedding/EmbedderConfig.cs:19` | local ONNX | nomic-ai/nomic-embed-text-v1.5 | hardcoded `ModelId` | 2026-09-07 (read) | |
| Local reranking (santa's own index) | santa | `src/Santa.Core/Embedding/RerankerConfig.cs:16` | local ONNX | Xenova/ms-marco-MiniLM-L-12-v2 | hardcoded `ModelId` | 2026-09-07 (read) | **differs from shepherd's `cross-encoder/...` id** for what is meant to be the same model — see Open items |
| cos-aide refresh runner (live orderly) | cos-aide (`~/repos/gareth-agentic/cos-aide`) | `runtime/refresh-runner.mjs:11-12,66-68` | `codex exec` | gpt-5.6-sol (low) | hardcoded const `MODEL`/`REASONING` | 2026-09-07 (read) | THE live orderly runner; symlinked as `~/tools/orderlies`, hosted in herdr session `rook`, run by `cos-aide-refresh.timer` (confirmed active in `systemctl --user list-timers`) |
| Investigation orchestrator | orbital-voice-prototype (`~/repos/gareth-agentic/orbital-voice-prototype`) | `investigation.py`, `local_api.py`, `openai_responses.py`, `local_agent.py` | OpenAI Responses API | gpt-5.6-sol orchestrator / gpt-5.6-luna worker / claude-sonnet-5 / mistral-small-2603 | env `INVESTIGATION_ORCHESTRATOR_MODEL`, `AGENT_MODEL` | 2026-09-07 (survey) | experimental; not independently re-read this pass |
| Terminal-command interpretation | real-term (`~/repos/gareth-agentic/real-term`) | `TermInterpretation.cs:355-423` | Anthropic REST | claude-haiku-4-5 (default) | config key `Anthropic:Model` (`RealTermConfig.cs:101`) | 2026-09-07 (survey) | not independently re-read this pass |
| Luna worker call | lavalamp | `src/worker/luna.ts:69-88` | raw fetch to OpenAI-compatible endpoint | gpt-5.6-luna | hardcoded, `OPENAI_API_KEY` | 2026-09-07 (survey) | not independently re-read this pass |
| Embeddings for search | coursenado (`~/repos/stream-ai-sites/coursenado`) | `processor/src/index.ts` | OpenAI embeddings API | text-embedding-3-small | hardcoded, **version unpinned** | 2026-09-07 (survey) | see Open items |
| Audit/rebuild/repair scripts | coursenado | (scripts, not individually re-verified) | codex exec | gpt-5.6-luna | not fully verified | 2026-09-07 (survey) | |
| Digest backfill | cosmo-agentic | `worker/services/digest-backfill.ts` | `@anthropic-ai/sdk` | claude-haiku-4-5-20251001 | hardcoded | 2026-09-07 (survey) | not independently re-read this pass |
| Provider templates (caller-supplied) | lean-runner | `providers/codex.json`, `providers/claude.json` | codex/claude CLI via template | `{{model}}` — caller-supplied at call time | template placeholder, no code-owned default | 2026-09-07 (survey) | conforms to the "explicit, never inherited" rule only if every caller actually fills the template — not verified here |
| Session recipe (legacy, superseded) | lean-runner | `internal/loom/session/recipe.go:37-39` | claude CLI | opus/sonnet/fable — **unspecified default** | none; falls through to CLI default | 2026-09-07 (survey) | legacy path, superseded; violates the explicit-model rule but is not live — confirm superseding path before removing |
| Interactive pane spawn | cockpit | `cockpit-spawn`, `cockpit-seed-exec` | codex/claude CLI | unspecified → each CLI's own default | operator-chosen at spawn time | 2026-09-07 (survey) | interactive, human in the loop each time; treated as acceptable unless the operator says otherwise |
| Codex reconnect probe (test literal) | lean/rookery | `probes/codex/probe-reconnect.mjs` | codex exec | gpt-5.6-sol | hardcoded test literal | 2026-09-07 (survey) | test/probe code, not a production call site |

## Known defaults

`~/.codex/config.toml` sets the bare-CLI default model to **gpt-6-astra**, medium effort. As of
2026-09-07, nothing *live* inherits this default — every production call site above either names
its model explicitly or reads a code-owned constant/env var. The two places that *would* inherit
it are dead (see Retired / not live) or legacy-and-unconfirmed (`lean-runner`'s `recipe.go`, above).

The house default for **delegated investigation fan-outs** is **gpt-5.6-terra at medium effort**, dropping to
**gpt-5.6-sol at low effort** for the cheap end of the same work. `gpt-reserve` and `gpt-5.4-mini` were retired
on 2026-09-08 and neither is a valid choice for new work; a call site still naming either is drift, not a
deliberate exception.

## Retired / not live

- `cp-core/orderlies-implementation/runtime/brief-codex-loop:38` and `orderly-codex-run-once:35` — called
  `codex` with **no model**, so they would have silently inherited gpt-6-astra. They lived in a frozen
  2026-07-21 sandbox clone that was invoked by nothing. **Gone as of 2026-09-08:** the sandbox was archived to
  `~/archive/cp-core-sandbox-frozen-2026-07-21.20260908.tgz` and the working copy deleted, so there is no
  longer a checkout on this machine that would inherit the CLI default. Kept here as history, not as a live
  exception; the verify pass should not go looking for these paths.
- `codex-cache-refresh.timer` — a 12-hour `rm` of `~/.codex/models_cache.json`, workaround for a
  codex 0.147.0 cache bug. Installed codex is 0.153.4 (= npm latest as of the survey). Candidate
  for removal; the verify fan-out should re-check `codex --version` each run and flag this once
  confirmed stale for a full cycle.

## Open items

- `CHOIR_EVIDENCE_REVIEW_INTERPRETATION` (orbital) has zero live consumers. Either wire it up or
  remove it — a frozen, unused model policy is a maintenance trap.
- Two orbital tools (`tools/orderly/run.mjs`, `tools/orderly/extract.mjs`) bypass the invoker
  entirely and read their model from a plain env var with a hardcoded fallback, rather than from
  `src/config/sources.mjs`. Worth deciding whether that's intentional (orderlies are meant to be
  independently configurable) or drift.
- coursenado's `text-embedding-3-small` call has no pinned model version.
- santa's reranker (`Xenova/ms-marco-MiniLM-L-12-v2`) and shepherd's reranker
  (`cross-encoder/ms-marco-MiniLM-L12-v2`) use **different Hugging Face org names** for what both
  comments describe as the same model. Confirm whether these actually resolve to the same weights
  before assuming the two tools are consistent.
- santa's `ClaudeCliRunner.cs:46-47` only appends `--model` when `req.Model` is non-empty; an
  empty/unset caller value silently falls through to the `claude` CLI's own default, which is the
  exact failure mode the "always name it explicitly" rule exists to catch. Worth checking whether
  `SANTA_SUMMARIZER` (the router env this file's doc-comment references) can ever produce an empty
  value.
- lean-runner's `recipe.go:37-39` legacy default path was not independently re-confirmed as dead
  this pass — verify no caller still reaches it before deleting.
- `~/.codex/config.toml`'s `[tui.model_availability_nux]` lists only gpt-5.5/gpt-5.6-sol/gpt-6-astra,
  though terra and luna are used pervasively above. This looks like stale UI metadata, not an
  access restriction — terra and luna both work in practice — but is worth a one-line fix so the
  TUI's own model picker isn't misleading.
