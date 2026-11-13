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
- **Retired models are not choices.** `gpt-reserve` and `gpt-5.4-mini` were retired on 2026-09-08, and
  `gpt-5.5` stopped being offered to Codex on a ChatGPT account on 2026-10-14. A call site still naming any of
  them is drift.

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
| `interp.contextual.low` | Cheap contextual interpretation and triage | High-volume judgement calls where a wrong answer is cheap to correct and latency matters more than nuance: sorting, first-pass triage, "does this still matter". | gpt-6.1-terra (low) | gpt-6-luna (low) | 2026-11-12 |
| `interp.structured.medium` | Routine structured interpretation | The default lane. Reading structured or semi-structured input and producing a structured answer where correctness matters but the judgement is not contested. | gpt-6.1-sol (medium) | gpt-6.1-terra (medium) or gpt-6.1-sol (low) for cheaper passes | 2026-11-12 |
| `interp.editorial.high` | Editorial or high-judgment synthesis | Work whose output a human will read as a considered opinion: agenda-setting, proposing changes, synthesising an argument from conflicting evidence. Reach for this only when the judgement is genuinely contested — it is the expensive lane. | gpt-6.1-sol (high) | claude-opus-5-5 (high) | 2026-11-12 |
| `interp.command.fast` | Fast command interpretation | Turning a short natural-language instruction into a concrete command or parameter set, in a loop tight enough that the user is waiting on it. | claude-haiku-5-5 (low) | gpt-6-luna (low) | 2026-11-12 |

### Decisions

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `decide.typed.fast` | Typed decision, pre-filter or categorisation | Fixed questions about a text whose answers code acts on: yes or no, one of a fixed set of options, or a point on a scale, each returned with a probability and no prose. Typical jobs: routing a message to the path that handles it, deciding what reaches a bigger model, sorting items into a fixed set of labels. The model answers; it never does the work. Act only above a probability bar, and send everything under it, every error and every late answer to the lane that does the work, so a wrong decision costs time, not correctness. Ask only independent questions, and leave arithmetic, dates, copying text out and anything that needs a written reason to an LLM lane (`interp.contextual.low` when a sentence of reasoning is wanted). When a person is waiting, call the provider directly: a gateway in between added 150 ms or more, and over a second after a quiet minute. TypeSafe runs in the US and publishes no data-retention terms we have found. It is cleared for internal operational data; personal data needs its own decision. | jev-latest (TypeSafe), recording the version that answered with every reading | an exact Jev version, such as jev-1.14.0; gpt-6-luna on OpenAI's Decisions API | 2026-11-12 |

### Conversation and speech

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `chat.conversational` | Low-latency conversational lane | Ordinary back-and-forth with a person, where the reply has to arrive fast enough to feel like a conversation. | gpt-6-luna (medium) | gpt-6.1-terra (low) | 2026-11-12 |
| `chat.turnselect.fast` | Turn selection in a live multi-party conversation | Deciding who speaks next, or whether to speak at all, inside a live exchange. Latency dominates; the decision itself is small. Keep this lane frozen rather than deployment-tunable — it changes conversation state. | mistral-small-latest | gpt-6-luna (low) | 2026-09-29 |
| `transcript.polish` | Transcript polish, lexical only | Casing, punctuation and paragraphing on an existing transcript. The word sequence must survive unchanged, so pair this with a code-enforced lexical invariant after generation — the model is not trusted to respect the constraint on its own. | gpt-6-luna (medium) | gpt-6.1-terra (low) | 2026-11-12 |
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
| `content.mechanical.batch` | Mechanical content transformation at scale | Auditing, repairing or rebuilding a large body of existing content against explicit written criteria, in batches with bounded concurrency. The distinguishing test is what checks the output: a schema, an id set, an enum, a score range — code, not anyone's judgment. The model is being asked for throughput and consistency, so paying for a reasoning tier it cannot use buys nothing. Reviewing that same content and forming an opinion on it is a different use case; send it to `interp.editorial.high`. | gpt-6-luna (medium) | gpt-6-luna (low) for the cheapest passes; claude-haiku-5-5 (medium) where a second provider is wanted; gpt-6.1-terra (low) | 2026-11-12 |

### Classification and summarisation

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `classify.document.nightly` | Nightly document classification opinion | Unattended batch classification over documents, producing an advisory opinion rather than an enforced decision. | gpt-6.1-sol (low), on Batch or Flex where the schedule allows | gpt-6.1-terra (medium); gpt-6-luna (medium) | 2026-11-12 |
| `classify.fallback.overloaded` | Classification fallback when the primary provider is overloaded | The second path, taken only when the primary provider returns capacity errors. It must be a genuinely different provider — a fallback on the same account is not a fallback. | gpt-6.1-terra (medium) | gpt-6.1-terra (low) | 2026-11-12 |
| `classify.session.router` | Session classification and summarisation router | A router that classifies or summarises captured sessions and lets the caller choose the model per request. It still needs a code-owned default: a router whose empty value means "whatever the CLI picks" is the failure this whole file exists to prevent. | claude-haiku-5-5 (medium) | claude-sonnet-5-5 | 2026-11-12 |
| `gather.batch.structured` | Scheduled batch gather over messy sources | A scheduled pass across unstructured personal-operations sources — mail, calendar, chat, meeting notes — deciding what in them is actionable and emitting structured items that the calling code validates and reconciles. The judgment is the filtering, not the writing, and it runs unattended over a mixed and noisy input rather than over one clean corpus. | gpt-6.1-sol (low) | gpt-6.1-terra (medium), or (low) for a cheaper pass | 2026-11-12 |
| `summarize.digest` | Digest and backfill summarisation | Bulk summarisation of a backlog into digest form. Cheap per item, large item count, output read in aggregate. | claude-haiku-5-5 (low) | claude-sonnet-5-5 | 2026-11-12 |
| `summarize.rolling.fold` | Rolling state fold | A scheduled fold of a prior state document plus the events since, into a document that replaces it. Not digest work: there is one document, people read it as the current state of something, and it accumulates, so a confidently invented line survives every later fold. Give this lane no weaker fallback — a skipped fold is free, because the events wait and the next run takes them, while a wrong fold is not. | gpt-6-luna (medium) | — | 2026-11-12 |

### Delegated work

| Slug | Use case | When to use it | Recommended | Acceptable alternatives | Last reviewed |
|---|---|---|---|---|---|
| `investigate.fanout.orchestrator` | In-code investigation pipeline — orchestrator | The orchestrator half of a fan-out that lives inside a program: it decomposes a question into bounded tasks, then combines what the workers return into the answer. Both ends are judgment-heavy, which is why this lane runs high. | gpt-6.1-sol (high) | gpt-6.1-sol (low) where the decomposition is routine | 2026-11-12 |
| `investigate.fanout.worker` | In-code investigation pipeline — worker | One bounded read-only question answered against a repository, returning a finding plus citations that the calling code validates against real files and lines. Reached by a fan-out or by a single call; the unit of work is the same either way. | gpt-6-luna (medium) | gpt-6-luna (low) | 2026-11-12 |
| `investigate.delegated.orchestrator` | Session-delegated investigation — orchestrator | Fan-out delegated from an interactive agent session, such as a rescue run or a second opinion, rather than from an in-code pipeline. A person asked for this, is waiting on it, and will read the result themselves. | gpt-6.1-sol (medium) | gpt-6.1-sol (high) for a genuinely contested question | 2026-11-12 |
| `investigate.delegated.worker` | Session-delegated investigation — worker | The cheap end of the same session-delegated work: one worker, one bounded question, a conclusion rather than a transcript. `gpt-reserve` and `gpt-5.4-mini` were retired on 2026-09-08 and are not choices here. | gpt-6.1-sol (low) | gpt-6.1-terra (medium); gpt-6-luna (low) | 2026-11-12 |
| `code.agentic.interactive` | Interactive agentic coding session | A session a human is watching and steering. The model is chosen at spawn time and the human is the check on it, which is why this is the one lane where an operator-selected default is acceptable. Nothing unattended may use this slug. | claude-opus-5-5 for build and architecture; claude-sonnet-5-5 (medium) for routine work | claude-fable-5-2 for hard, long-horizon problems, at twice Opus 5.5's price per token | 2026-11-12 |
| `code.agentic.worker` | Unattended implementation worker | A coding agent launched to carry one bounded case to done without a human watching each turn: it edits, tests and reports, and a supervisor wakes it when it stalls. The model is named at launch and never defaulted, because nobody is watching to notice a wrong one; reasoning effort defaults to high. Unlike `code.agentic.interactive`, no operator-selected default is acceptable here. | claude-sonnet-5-5 (high) for routine implementation; claude-opus-5-5 (high) for build and architecture | gpt-6.1-sol (high); gpt-6-luna (high) for mechanical work whose output code checks | 2026-11-12 |
| `verify.unattended` | Unattended verification sweep | Scheduled grep-and-diff work: confirm recorded facts against the code, report what moved. Cheap and mechanical, so it belongs on the cheaper model however important the output is. | claude-sonnet-5-5 | — | 2026-11-12 |

## Changelog

- **2026-11-12 — new lane `decide.typed.fast`, on TypeSafe's Jev.** Jev (released 2026-09-15) is a decision
  model, not a text model. It answers typed questions (yes or no, choose one, a point on a scale) with
  probabilities and writes no prose, for $0.042 per million input tokens with output free. Decisions had no lane
  of their own, so a site making one had to borrow `interp.contextual.low`, which is priced and specified for
  prose. Jev is called through its own API, not a chat endpoint, so moving a site onto this lane means rewriting
  the call, not re-pointing a model string. That is why it is a lane and not an alternative on an existing one.

  The evidence is our own workload: routing a chat assistant's incoming messages into five routes. On 167
  labelled items, with no tuning, Jev chose correctly on 99.4% and OpenAI's Decisions API on gpt-6-luna on
  98.8%. Neither sent a message that needed work down the chat path. Median latency was 337 ms against 422 ms
  through the same gateway; called directly, Jev answered in 170 to 190 ms on a fresh connection. A decision
  cost about $0.000035 against $0.00006. A replay of 400 cases at the chosen bar again read no work message as
  chat. Two limits came out of the same tests. Only 15 of the 167 items needed no work, so one item moves the
  chat figures by 7 points. And the pipelines in which Jev, paired with a model that copied text out, made the changes
  themselves rather than only routing were confidently wrong far more often than the 1-in-200 limit. That is
  why the lane forbids it to do the work. Independent
  reviewers also report run-to-run variation and some sensitivity to the order of options, so set bars with
  margin. Cloudflare's `clef-flash` was tested on the same items and is not listed: it scored 96.4% and was
  twice as slow.

  The recommendation is the `jev-latest` alias, as with this table's other `-latest` names, and every reading
  records the version that answered, so a release that moves readings shows up as a new version value. A site
  that cannot accept a silent upgrade, such as one whose probability bars were set on one version, pins an exact
  version, which is the first listed alternative.

- **2026-11-12 — Haiku 5.5, GPT-6.1 Terra and Fable 5.2 replaced their predecessors, and gpt-5.5 left.**
  Each change is a successor swap within one tier.

  claude-haiku-5-5 (released 2026-10-07) costs $0.10/$0.50 per MTok for prompts up to 100K tokens ($0.50/$2.50
  above), a tenth of claude-haiku-4-5's $1/$5. Artificial Analysis scores it 26 Intelligence Index points above
  Haiku 4.5. The three Haiku lanes (`interp.command.fast`, `classify.session.router`, `summarize.digest`) moved
  to it. Each names its effort, because Haiku 5.5 thinks by default and its default effort is medium: low for
  the fast and digest lanes, medium for the router. It is also now a second-provider alternative on
  `content.mechanical.batch`, the one change here backed by our own workload: at medium effort it agreed with
  gpt-6-luna on 96% of 387 items. claude-haiku-4-5 is not retired. It is dropped here, so sites still on it
  report as drift.

  gpt-6.1-terra (released 2026-10-26) replaces gpt-5.6-terra at $1/$5 per MTok against $2/$12. On Intelligence
  Index v5.0.1 it scores 29 at low effort ($0.07 per task) and 38 at medium ($0.17), which beats gpt-6.1-sol
  (low) at 35 ($0.16). `interp.contextual.low` moved to it. Every lane that listed gpt-5.6-terra as an
  alternative now names gpt-6.1-terra at the same effort. OpenAI has not set a shutdown date for gpt-5.6-terra.
  It is dropped here, not retired, so sites still on it report as drift.

  `classify.fallback.overloaded` recommended gpt-5.5, which Codex stopped offering on a ChatGPT account on
  2026-10-14. A site on this lane failed silently for three weeks before it was re-pointed. The lane now
  recommends gpt-6.1-terra (medium).

  claude-fable-5-2 (released 2026-11-09) costs $8/$40 per MTok, against Fable 5.1's $10/$50. On Anthropic's
  launch table it leads claude-opus-5-5 on every row but one: FrontierSWE v2 69.9% vs 62.3%, Terminal-Bench-Science
  74.6% vs 58.7%, Remote Labor Index 41.3% vs 21.3%. Opus 5.5 keeps a slightly higher AA-Briefcase Elo, 1800 vs
  1785. Fable was held to a last-resort escalation because Opus 5.5 beat 5.1 everywhere, and that reason is gone.
  `code.agentic.interactive` therefore lists Fable 5.2 for hard, long-horizon work, not only where Opus 5.5 has
  already failed. Opus 5.5 stays the default at half the price per token.

  Checked and unchanged: the Sol, Luna and Sonnet lanes. gpt-6.1-sol beats gpt-6.1-terra at medium and high
  effort for the money (46 vs 42 at Sol medium against Terra high). At the bottom, gpt-6.1-terra (medium) edges
  gpt-6.1-sol (low), 38 against 35 at about the same cost per task. That margin is too small to re-point the three
  Sol-low lanes, so Terra is listed as their alternative instead. On the Luna lanes, Haiku 5.5 roughly ties
  gpt-6-luna at equal cost per task (19 at low against Luna's 18 at medium, both $0.04), which is not a reason to
  move. Speech was not changed (no Voxtral release since 2026-09). Embeddings and `chat.turnselect.fast` were not re-checked. The evidence is public
  benchmarks and the vendors' own launch tables, apart from the one Haiku measurement above.

- **2026-10-07 — new lane `code.agentic.worker`.** Unattended implementation workers had no lane: the nearest,
  `code.agentic.interactive`, admits an operator-selected default only because a human watches the session, and
  says nothing unattended may use it. The new lane requires the model to be named at every launch and defaults
  effort to high. Recommendations follow the interactive lane's Claude split; Sol and Luna are alternatives.

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
