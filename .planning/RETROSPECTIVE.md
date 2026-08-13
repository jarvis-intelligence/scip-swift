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
