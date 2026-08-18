# Retrospective

## Milestone: v0.2.0 — Symbol Enrichment, Incremental, Cross-Repo, Xcode

**Shipped:** 2026-08-13
**Phases:** 5 | **Plans:** 10 | **Tests:** 95 (16 suites)

### What Was Built

- Symbol metadata enrichment: relationships, enclosing symbols, expanded role bits, basic signatures, authoritative external-symbol classification
- Homebrew distribution: formula, universal binary, release CI, dylib guard
- Incremental indexing: persistent DB, content-hash cache, version invalidation, --cache-dir/--index-only
- Cross-repo indexing: index-many subcommand, version disambiguation, ScipIndexMerger, --merge
- Xcode end-to-end test fixture: real xcodebuild integration test

### What Worked

- Stateless pure-function mapper pattern (enum-as-namespace) made each new mapper trivial to add and test in isolation
- Swift Testing (@Suite/@Test) gave clean per-mapper test suites with string descriptions
- Real-build integration tests (no mocks) caught regressions that unit tests alone would miss
- Tracer-first approach (wire one end-to-end path, then expand correctness) validated architecture before deep work
- The safe-resume gate caught uncommitted in-progress work in Phase 4, preventing duplicate executor dispatch

### What Was Inefficient

- REQUIREMENTS.md checkboxes were never updated during execution — all 26 requirements shipped but the traceability table stayed unchecked until milestone close
- Phase 1 used a combined summary (01-02-03-SUMMARY.md) instead of per-plan summaries, which confused the plan-count heuristic until manually verified
- Phase 3 UAT used a non-standard status format (`✅ PASSED` instead of `status: passed`) that the audit parser couldn't recognize
- Plan estimates had `confidence: low` across the board — actuals were consistently faster than estimated

### Patterns Established

- Combined-summary convention for tightly-coupled wave-2 plans (acceptable when plans share a single execution session)
- `indexOneRepo` extraction pattern for subcommand reuse — static function returning the domain object, caller handles serialization
- ScipIndexMerger as stateless enum with path-prefixing + defined-symbol stripping — the three scip-lint rules each map to one merge step

### Key Lessons

- Keep REQUIREMENTS.md traceability table in sync during execution, not at milestone close — the audit depends on it
- Use the GSD canonical status format (`status: passed`) in UAT/VERIFICATION files so automated audits parse correctly
- When plans are `autonomous: false`, the safe-resume gate is critical — always check for uncommitted work before spawning executors
- 95 tests with real builds (including xcodebuild) run in ~16 seconds — fast enough for tight iteration loops

### Cost Observations

- Model mix: primarily general-purpose subagents for execution, orchestrator for coordination
- Sessions: ~3 execution sessions across Phases 4-5
- Notable: subagent execution (write tests + fixtures + debug) completed in 5-8 minutes per plan, well under the 30-minute estimate

---

## Milestone: v0.3.0 — Readable Indexes

**Shipped:** 2026-08-18
**Phases:** 4 | **Plans:** 7 | **Tests:** 216 (26 suites)

### What Was Built

- Xcode indexing restored (dispatch lost in the 0cdefd7 cache rewrite) with opt-in --destination and a -showdestinations failure hint
- Demangled display names via dlopen'd libswiftDemangle — display-only, canonical identity untouched, --no-demangle escape hatch
- Exact occurrence ranges from SwiftSyntax identifier extents; UTF-8/Unicode-correct against hand-computed fixtures; approximation retained as parse-failure fallback
- Symbol documentation (/// and /** */ → Markdown) riding the same single SwiftSyntax parse, mechanically proven via a parse-count hook

### What Worked

- Empirical phase research: three separate "verify before you plan" moments corrected wrong assumptions (swift_demangle ABI, first-token vs name-token doc keying, endPosition trailing-trivia) — each would have been a mid-execution derailment
- The plan-checker loop caught two impossible gates (a grep that couldn't match a correct pin; a hand-computed byte expectation off by one) and a blast-radius miss (RelationSpikeTests)
- Diff-based protected-file gates proved "identity unchanged" mechanically instead of by assertion
- Consolidated UAT against real fixtures with the real CLI found the relative --cache-dir gap that all 158 suite tests missed

### What Was Inefficient

- Provider 503s killed many research/verifier subagents; work survived because results were written incrementally to disk, but replanning cost real wall-clock time
- Bookkeeping drift (STATE/ROADMAP/REQUIREMENTS lagging verified reality) recurred at every phase boundary — always hand-fixed, never root-caused
- Out-of-band v1.0-track work landed mid-milestone, forcing the audit to disentangle scope; the SYMBOL-03 re-baseline should have been a coordinated decision

### Patterns Established

- Milestone research proposes, phase research disposes — never plan directly off milestone-level technical claims
- TDD executor contract with RED-commit evidence and disclosed-deviation culture (every deviation documented, judged by the verifier, never silently absorbed)
- Empirical verification as the default: scratch-compile probes, live xcodebuild runs, byte-level fixture hexdumps before writing expectations

### Key Lessons

- Hand-computed expected values need a second independent recomputation before entering a plan (the F4 off-by-one)
- Pipes mask exit codes — set -o pipefail everywhere a verify command matters
- Upstream behavior (IndexStoreDB's TMPDIR anchoring of relative paths) can turn a "trivial flag" into a real bug; root-cause in the dependency source, not just our code

### Cost Observations

- Sessions: planning loops (research→planner→checker×2) ran 15–45 min per phase; executors 20–75 min per plan; verifiers 8–22 min
- Notable: one 4.6-hour executor run (07-01) included the SubprocessRunner deadlock diagnosis
