# Milestones

## v0.3.0 Readable Indexes (Shipped: 2026-08-18)

**Phases completed:** 4 phases, 7 plans, 5 tasks

**Key accomplishments:**

- 1. [Rule 1 - Bug] SubprocessRunner deadlocks parallel swift-testing runs
- 1. [Rule 1 - Bug] invalidateAll destroyed the freshly-built index store on version upgrade
- 1. [Rule 1 - Bug] Tracer USR filter and hand-computed error-node expectations corrected
- 1. [Rule 1 - Bug] 名前 USR mangling corrected in symbol-fragment filters
- 1. [Rule 1 - Bug] Tracer RED used a wrong display-name lookup

**Stats:** 4 phases, 7 plans, 216 tests across 26 suites, 94 commits, 91 files (+12,638/−1,006), 4 days (2026-08-15 → 2026-08-18). Consolidated UAT 12/12 passed; milestone audit passed after W2 fix (demangle mode joined cache manifest key) and SYMBOL-03 re-baseline. Range note: includes ~21 out-of-band v1.0-track commits (USR parser/mapper stack, OverloadTable, symbolFormatVersion 2, SchemeFixture goldens, CI toolchain pin) that landed on main after the phases closed — flagged in v0.3.0-MILESTONE-AUDIT.md.

**Deferred to v1.0 track (audit W3–W7):** index-many lacks --no-demangle/--destination; CONFIGURATION.md doesn't document v0.3.0 flags; forced --build-tool xcodebuild --destination on SwiftPM errors misleadingly; shared --cache-dir across repos thrashes (repo-global overload fingerprint).

---

## v0.2.0 Symbol Enrichment, Incremental, Cross-Repo, Xcode (Shipped: 2026-08-13)

**Phases completed:** 5 phases, 10 plans, 7 tasks

**Key accomplishments:**

- Symbol metadata enrichment: relationships (inheritance, conformance, override), enclosing symbols, expanded role bits (Test, Generated, ForwardDefinition), basic signatures, and authoritative external-symbol classification via `SymbolLocation.isSystem`
- Homebrew distribution: formula in `homebrew-scip-swift` tap, universal binary (arm64 + x86_64) build, release CI workflow on `v*` tags, runtime dylib resolution guard
- Incremental indexing: persistent IndexStoreDB database, content-hash caching of per-file `Scip_Document` protobufs, version-based invalidation, `--cache-dir` and `--index-only` CLI flags
- Cross-repo indexing: `index-many` subcommand with variadic repo paths, SCIP version field disambiguation, `ScipIndexMerger` with document path prefixing and external-symbol stripping/dedup, `--merge` flag
- Xcode end-to-end test fixture: minimal `.xcodeproj` with real `xcodebuild` → IndexStore → SCIPIndexBuilder integration test, closing the last test-coverage gap

**Stats:** 5 phases, 10 plans, 95 tests across 16 suites, ~6000 LOC Swift, 48 commits, 19 days (2026-07-25 → 2026-08-13)

---
