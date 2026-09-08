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
| `interp.contextual.low` | Cheap contextual interpretation and triage | High-volume judgement calls where a wrong answer is cheap to correct and latency matters more than nuance: sorting, first-pass triage, "does this still matter". | gpt-5.6-terra (low) | gpt-5.6-luna (low) | 2026-09-08 |
| `interp.structured.medium` | Routine structured interpretation | The default lane. Reading structured or semi-structured input and producing a structured answer where correctness matters but the judgement is not contested. | gpt-5.6-terra (medium) | gpt-5.6-sol (medium) | 2026-09-08 |
| `interp.editorial.high` | Editorial or high-judgment synthesis | Work whose output a human will read as a considered opinion: agenda-setting, proposing changes, synthesising an argument from conflicting evidence. Reach for this only when the judgement is genuinely contested — it is the expensive lane. | gpt-5.6-sol (high) | gpt-6-astra (high) | 2026-09-08 |
| `interp.command.fast` | Fast command interpretation | Turning a short natural-language instruction into a concrete command or parameter set, in a loop tight enough that the user is waiting on it. | claude-haiku-4-5 | gpt-5.6-luna (low) | 2026-09-08 |

### Conversation and speech

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `chat.conversational` | Low-latency conversational lane | Ordinary back-and-forth with a person, where the reply has to arrive fast enough to feel like a conversation. | gpt-5.6-luna (medium) | gpt-5.6-terra (low) | 2026-09-08 |
| `chat.turnselect.fast` | Turn selection in a live multi-party conversation | Deciding who speaks next, or whether to speak at all, inside a live exchange. Latency dominates; the decision itself is small. Keep this lane frozen rather than deployment-tunable — it changes conversation state. | mistral-small-latest | gpt-5.6-luna (low) | 2026-09-08 |
| `transcript.polish` | Transcript polish, lexical only | Casing, punctuation and paragraphing on an existing transcript. The word sequence must survive unchanged, so pair this with a code-enforced lexical invariant after generation — the model is not trusted to respect the constraint on its own. | gpt-5.6-luna (medium) | gpt-5.6-terra (low) | 2026-09-08 |
| `asr.batch` | Batch speech-to-text | Transcribing a recording that already exists, where throughput and cost matter and nobody is waiting. | voxtral-mini-latest | — | 2026-09-08 |
| `asr.realtime` | Realtime speech-to-text | Streaming transcription of live audio over a websocket. | voxtral-mini-transcribe-realtime-2602 | — | 2026-09-08 |

### Retrieval

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `embed.ondevice` | On-device embedding | Building a local index with no network round trip and no per-call cost. | nomic-ai/nomic-embed-text-v1.5 (local ONNX) | — | 2026-09-08 |
| `rerank.ondevice` | On-device reranking | Reordering local retrieval candidates before they reach a model. Use the exact model id given here: two ids that differ only by publisher are not known to be the same weights. | cross-encoder/ms-marco-MiniLM-L12-v2 (local ONNX) | — | 2026-09-08 |
| `embed.search.hosted` | Hosted search embeddings | Embedding a corpus for search where a hosted API is simpler than shipping a local model. Pin the version explicitly; an unversioned id silently re-embeds against different weights. | text-embedding-3-small (pinned version) | — | 2026-09-08 |

### Classification and summarisation

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `classify.document.nightly` | Nightly document classification opinion | Unattended batch classification over documents, producing an advisory opinion rather than an enforced decision. | gpt-5.6-terra (medium) | gpt-5.6-luna (medium) | 2026-09-08 |
| `classify.fallback.overloaded` | Classification fallback when the primary provider is overloaded | The second path, taken only when the primary provider returns capacity errors. It must be a genuinely different provider — a fallback on the same account is not a fallback. | gpt-5.5 | gpt-5.6-terra (medium) | 2026-09-08 |
| `classify.session.router` | Session classification and summarisation router | A router that classifies or summarises captured sessions and lets the caller choose the model per request. It still needs a code-owned default: a router whose empty value means "whatever the CLI picks" is the failure this whole file exists to prevent. | claude-haiku-4-5 | claude-sonnet-5 | 2026-09-08 |
| `summarize.digest` | Digest and backfill summarisation | Bulk summarisation of a backlog into digest form. Cheap per item, large item count, output read in aggregate. | claude-haiku-4-5-20251001 | claude-sonnet-5 | 2026-09-08 |

### Delegated work

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `investigate.fanout.orchestrator` | Delegated investigation — orchestrator | The session that plans an investigation, fans work out to workers and synthesises what comes back. | gpt-5.6-terra (medium) | gpt-5.6-sol (high) for a genuinely contested question | 2026-09-08 |
| `investigate.fanout.worker` | Delegated investigation — worker | The cheap end of the same work: one worker, one bounded question, a conclusion rather than a transcript. | gpt-5.6-sol (low) | gpt-5.6-luna (low) | 2026-09-08 |
| `code.agentic.interactive` | Interactive agentic coding session | A session a human is watching and steering. The model is chosen at spawn time and the human is the check on it, which is why this is the one lane where an operator-selected default is acceptable. Nothing unattended may use this slug. | claude-opus-5 for build and architecture; claude-sonnet-5 for routine work | claude-fable-5-1 where the judgement genuinely warrants it | 2026-09-08 |
| `verify.unattended` | Unattended verification sweep | Scheduled grep-and-diff work: confirm recorded facts against the code, report what moved. Cheap and mechanical, so it belongs on the cheaper model however important the output is. | claude-sonnet-5 | — | 2026-09-08 |

## Known CLI defaults

The bare `codex` CLI on this machine defaults to **gpt-6-astra at medium effort**. Nothing unattended may
inherit it. That is not a judgement about the model — it is that an inherited default is a model nobody chose,
which will change under us without a commit, a review or a signal.

`code.agentic.interactive` is the single exception, and only because a human picks the model at spawn and is
watching the result. Every other lane names its model.

One legacy launch recipe still falls through to a CLI default. It is believed superseded and not live, and is
tracked privately rather than here.

## Where the sites live

The list of actual call sites — repo, file, mechanism, pinned model, and which slug each is meant to satisfy —
is private and lives outside this repo, at `~/knowledge/workspace-operations/model-sites.md`. Nothing in this
repo quotes its contents; the verification pass reads both files and reports divergence between them.
