# Model use cases

A map from **use case** to **the model we currently recommend for it**. It is deliberately not a list of
systems: code names a use case, and this file says what that use case should currently run on.

That indirection is the point. A call site that hardcodes a model has to be found and edited when the
recommendation moves, and finding them all is exactly the job nobody does. A call site that names a use case
and reads its model from its own config only has to be *re-pointed*, and this file is the one place that says
where to point it.

## How to use this file

- **Code names the use case, not the model.** Each entry below has a stable slug (`interp.structured.medium`,
  `asr.batch`, …). A call site records which slug it satisfies and reads the actual model string from its own
  configuration — a frozen constant, an env var with a code-owned default, or a caller-supplied parameter.
- **This file is the source of truth for what a slug should map to today.** It is not a runtime lookup, and
  nothing reads it at execution time. Changing a recommendation here does not change any running system; it
  records the decision that a re-point should follow.
- **Every call site names its model explicitly.** Never by omission, and never by inheriting a CLI's own
  default. A site that omits the model is drift even when the default it inherits happens to be reasonable,
  because nobody chose it and nothing will tell you when it changes.
- **Alternatives are alternatives, not preferences.** A site running an "acceptable alternative" is fine and
  is not drift. A site running anything else is a decision somebody should re-take.
- **Retired models are not choices.** `gpt-reserve` and `gpt-5.4-mini` were retired on 2026-09-08. A call site
  still naming either is drift.

## How it is maintained

Every 14 days a `systemd --user` timer runs a verification pass over both this file and a private site
inventory that lives outside this repo. The pass checks each recorded call site against the code, updates the
private file, and reports every site whose pinned model has diverged from its use case's recommendation here.

The pass never rewrites a recommendation in this file. Moving a recommendation is a human decision, taken
deliberately, with the divergence report as its evidence. See `tools/model-inventory/README.md`.

## Use cases

### Interpretation

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `interp.contextual.low` | Cheap contextual interpretation and triage | High-volume judgement calls where a wrong answer is cheap to correct and latency matters more than nuance: sorting, first-pass triage, "does this still matter". | gpt-5.6-terra (low) | gpt-6-luna (low) | 2026-09-29 |
| `interp.structured.medium` | Routine structured interpretation | The default lane. Reading structured or semi-structured input and producing a structured answer where correctness matters but the judgement is not contested. | gpt-6.1-sol (medium) | gpt-6.1-sol (low) for cheaper passes; gpt-5.6-terra (medium) | 2026-09-30 |
| `interp.editorial.high` | Editorial or high-judgment synthesis | Work whose output a human will read as a considered opinion: agenda-setting, proposing changes, synthesising an argument from conflicting evidence. Reach for this only when the judgement is genuinely contested — it is the expensive lane. | gpt-6.1-sol (high) | claude-opus-5-5 (high) | 2026-09-30 |
| `interp.command.fast` | Fast command interpretation | Turning a short natural-language instruction into a concrete command or parameter set, in a loop tight enough that the user is waiting on it. | claude-haiku-4-5 | gpt-6-luna (low) | 2026-09-29 |

### Conversation and speech

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `chat.conversational` | Low-latency conversational lane | Ordinary back-and-forth with a person, where the reply has to arrive fast enough to feel like a conversation. | gpt-6-luna (medium) | gpt-5.6-terra (low) | 2026-09-29 |
| `chat.turnselect.fast` | Turn selection in a live multi-party conversation | Deciding who speaks next, or whether to speak at all, inside a live exchange. Latency dominates; the decision itself is small. Keep this lane frozen rather than deployment-tunable — it changes conversation state. | mistral-small-latest | gpt-6-luna (low) | 2026-09-29 |
| `transcript.polish` | Transcript polish, lexical only | Casing, punctuation and paragraphing on an existing transcript. The word sequence must survive unchanged, so pair this with a code-enforced lexical invariant after generation — the model is not trusted to respect the constraint on its own. | gpt-6-luna (medium) | gpt-5.6-terra (low) | 2026-09-29 |
| `asr.batch` | Batch speech-to-text | Transcribing a recording that already exists, where throughput and cost matter and nobody is waiting. | voxtral-mini-latest | — | 2026-09-08 |
| `asr.realtime` | Realtime speech-to-text | Streaming transcription of live audio over a websocket. | voxtral-mini-transcribe-realtime-2602 | — | 2026-09-08 |

### Retrieval

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `embed.ondevice` | On-device embedding | Building a local index with no network round trip and no per-call cost. | nomic-ai/nomic-embed-text-v1.5 (local ONNX) | — | 2026-09-08 |
| `rerank.ondevice` | On-device reranking | Reordering local retrieval candidates before they reach a model. Name the id of the artifact actually loaded, not the id of the upstream model it was exported from — a label naming something the loader never fetches is worse than no label. | Xenova/ms-marco-MiniLM-L-12-v2 (local ONNX) | — | 2026-09-09 |
| `embed.search.hosted` | Hosted search embeddings | Embedding a corpus for search where a hosted API is simpler than shipping a local model. Pin the version explicitly; an unversioned id silently re-embeds against different weights. | text-embedding-3-small (pinned version) | — | 2026-09-08 |

### Content

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `content.mechanical.batch` | Mechanical content transformation at scale | Auditing, repairing or rebuilding a large body of existing content against explicit written criteria, in batches with bounded concurrency. The distinguishing test is what checks the output: a schema, an id set, an enum, a score range — code, not anyone's judgment. The model is being asked for throughput and consistency, so paying for a reasoning tier it cannot use buys nothing. Reviewing that same content and forming an opinion on it is a different use case; send it to `interp.editorial.high`. | gpt-6-luna (medium) | gpt-6-luna (low) for the cheapest passes; gpt-5.6-terra (low) | 2026-09-29 |

### Classification and summarisation

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `classify.document.nightly` | Nightly document classification opinion | Unattended batch classification over documents, producing an advisory opinion rather than an enforced decision. | gpt-6.1-sol (low), on Batch or Flex where the schedule allows | gpt-6-luna (medium) | 2026-09-30 |
| `classify.fallback.overloaded` | Classification fallback when the primary provider is overloaded | The second path, taken only when the primary provider returns capacity errors. It must be a genuinely different provider — a fallback on the same account is not a fallback. | gpt-5.5 | gpt-5.6-terra (medium) | 2026-09-08 |
| `classify.session.router` | Session classification and summarisation router | A router that classifies or summarises captured sessions and lets the caller choose the model per request. It still needs a code-owned default: a router whose empty value means "whatever the CLI picks" is the failure this whole file exists to prevent. | claude-haiku-4-5 | claude-sonnet-5-5 | 2026-09-29 |
| `gather.batch.structured` | Scheduled batch gather over messy sources | A scheduled pass across unstructured personal-operations sources — mail, calendar, chat, meeting notes — deciding what in them is actionable and emitting structured items that the calling code validates and reconciles. The judgment is the filtering, not the writing, and it runs unattended over a mixed and noisy input rather than over one clean corpus. | gpt-6.1-sol (low) | gpt-5.6-terra (low) | 2026-09-30 |
| `summarize.digest` | Digest and backfill summarisation | Bulk summarisation of a backlog into digest form. Cheap per item, large item count, output read in aggregate. | claude-haiku-4-5-20251001 | claude-sonnet-5-5 | 2026-09-29 |
| `summarize.rolling.fold` | Rolling state fold | A scheduled fold of a prior state document plus the events since, into a document that replaces it. Not digest work: there is one document, people read it as the current state of something, and it accumulates, so a confidently invented line survives every later fold. Give this lane no weaker fallback — a skipped fold is free, because the events wait and the next run takes them, while a wrong fold is not. | gpt-6-luna (medium) | — | 2026-09-29 |

### Delegated work

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `investigate.fanout.orchestrator` | In-code investigation pipeline — orchestrator | The orchestrator half of a fan-out that lives inside a program: it decomposes a question into bounded tasks, then combines what the workers return into the answer. Both ends are judgment-heavy, which is why this lane runs high. | gpt-6.1-sol (high) | gpt-6.1-sol (low) where the decomposition is routine | 2026-09-30 |
| `investigate.fanout.worker` | In-code investigation pipeline — worker | One bounded read-only question answered against a repository, returning a finding plus citations that the calling code validates against real files and lines. Reached by a fan-out or by a single call; the unit of work is the same either way. | gpt-6-luna (medium) | gpt-6-luna (low) | 2026-09-29 |
| `investigate.delegated.orchestrator` | Session-delegated investigation — orchestrator | Fan-out delegated from an interactive agent session, such as a rescue run or a second opinion, rather than from an in-code pipeline. A person asked for this, is waiting on it, and will read the result themselves. | gpt-6.1-sol (medium) | gpt-6.1-sol (high) for a genuinely contested question | 2026-09-30 |
| `investigate.delegated.worker` | Session-delegated investigation — worker | The cheap end of the same session-delegated work: one worker, one bounded question, a conclusion rather than a transcript. `gpt-reserve` and `gpt-5.4-mini` were retired on 2026-09-08 and are not choices here. | gpt-6.1-sol (low) | gpt-6-luna (low) | 2026-09-30 |
| `code.agentic.interactive` | Interactive agentic coding session | A session a human is watching and steering. The model is chosen at spawn time and the human is the check on it, which is why this is the one lane where an operator-selected default is acceptable. Nothing unattended may use this slug. | claude-opus-5-5 for build and architecture; claude-sonnet-5-5 (medium) for routine work | claude-fable-5-1 only where Opus 5.5 at higher effort still fails on a hard, long-horizon problem | 2026-09-29 |
| `verify.unattended` | Unattended verification sweep | Scheduled grep-and-diff work: confirm recorded facts against the code, report what moved. Cheap and mechanical, so it belongs on the cheaper model however important the output is. | claude-sonnet-5-5 | — | 2026-09-29 |

## Changelog

- **2026-09-30 — GPT-6.1 Sol replaced both gpt-6-sol and gpt-6-astra.** gpt-6.1-sol (released 2026-09-29;
  $2/$10 per MTok, cached input $0.10) beats gpt-6-sol by 4 to 8 Intelligence Index points at every effort
  for equal or lower cost per task, so every gpt-6-sol lane moved to it at the same effort. It also ties
  gpt-6-astra at high effort on the Intelligence Index (50 vs 51) and GDPval-AA (1486 vs 1485) at about a
  fifth of the cost per task ($0.32 vs $1.73), so `interp.editorial.high` moved to it too; Astra keeps a
  36-point lead on AA-Briefcase and is no longer listed. claude-opus-5-5 (high) stays the editorial
  alternative. Neither gpt-6-sol nor gpt-6-astra is deprecated by OpenAI; they are dropped here, not retired,
  so sites still on them report as drift. The evidence is public benchmarks, not our own workload.

- **2026-09-29 — GPT-6 Sol replaced gpt-5.6-sol and most Terra lanes; editorial moved to GPT-6 Astra.**
  gpt-6-sol ($2/$10 per MTok) beats gpt-5.6-sol ($4/$20) at every effort level for half the cost per task,
  and gpt-6-sol at low effort outscores gpt-5.6-terra at medium, so the structured, gather, classification and
  investigation lanes moved to it. Sonnet 5.5 is the stronger model outright but writes two to three times the
  tokens per task, so it stays only on interactive coding, now pinned to medium effort. `interp.editorial.high`
  moved to gpt-6-astra (high), a same-mechanism swap for its Codex call sites; claude-opus-5-5 (high) led it on
  the nearest benchmarks (GDPval-AA, AA-Briefcase) and is the alternative, pending a blind evaluation on stored
  Choir agendas. gpt-5.6-sol (high) stays an alternative there until that evaluation runs. The evidence is public
  benchmarks, not our own workload.

- **2026-09-29 — the mechanical tier moved to gpt-6-luna, and Opus 5.5 replaced Opus 5.** gpt-6-luna
  (released 2026-09-22) costs $0.10/$0.50 per MTok against $0.20/$1.20 for gpt-5.6-luna, at the same measured
  intelligence, so it is now the only recommendation for every lane whose output is checked by code:
  `chat.conversational`, `transcript.polish`, `content.mechanical.batch`, `summarize.rolling.fold` and
  `investigate.fanout.worker`. gpt-5.6-luna is deliberately not kept as an alternative, so every site still on
  it reports as drift. Lanes that list Luna only as an alternative now name gpt-6-luna. Judgement lanes stay on
  Terra: GPT-6 has no Terra tier, and Luna scores below it. On the Claude side, `claude-opus-5-5` beats
  `claude-fable-5-1` on every published benchmark at under half the price, so Opus 5.5 is the build default and
  Fable is kept only as the escalation for problems Opus 5.5 still fails at higher effort. Stale
  `claude-sonnet-5` ids now read `claude-sonnet-5-5`. Nothing in any repository changed.

- **2026-09-09 — the investigation lanes were split in two.** A single pair of slugs was covering two
  different kinds of work, and its recommendation described only one of them. Five independent
  implementations of the *in-code* pipeline had all settled away from that recommendation and toward each
  other, which is evidence about the default rather than about the five. The in-code slugs now record what
  those implementations do, and the session-delegated pair keeps the original recommendation for the work it
  always described. Nothing in any repository changed.

- **2026-09-09 — `rerank.ondevice` now names the ONNX export, not the upstream model.** Two tools were
  recorded as using different publishers' ids for the same reranker, which read as an inconsistency to
  resolve. Both were in fact loading the identical export, verified by hash and by one tool's model directory
  symlinking to the other's. The export is a re-export of `cross-encoder/ms-marco-MiniLM-L12-v2`
  (Apache-2.0); the export repository carries no license file of its own. The recommendation was wrong, not
  the code, and it was the recommendation that changed.

## Known CLI defaults

The bare `codex` CLI on this machine defaults to **gpt-6.1-sol at high effort** (set in `~/.codex/config.toml`; the model's own built-in Codex default is low). Nothing unattended may
inherit it. That is not a judgement about the model — it is that an inherited default is a model nobody chose,
which will change under us without a commit, a review or a signal.

`code.agentic.interactive` is the single exception, and only because a human picks the model at spawn and is
watching the result. Every other lane names its model.

## Where the sites live

The list of actual call sites — repo, file, mechanism, pinned model, and which slug each is meant to satisfy —
is private and lives outside this repo, at `~/knowledge/workspace-operations/model-sites.md`. Nothing in this
repo quotes its contents; the verification pass reads both files and reports divergence between them.
