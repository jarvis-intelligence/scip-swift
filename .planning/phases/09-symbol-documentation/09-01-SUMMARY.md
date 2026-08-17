---
phase: 09-symbol-documentation
plan: 01
subsystem: symbol-documentation
tags: [documentation, swift-syntax, trivia, scip-mapping, hover-parity]
status: complete
requires:
  - "Phase 8 SwiftSyntaxRefiner with the sole Parser.parse call wired into makeDocument"
provides:
  - "SwiftSyntaxRefiner doc map keyed at name-token anchors, built in the same single parse"
  - "SwiftSyntaxRefiner.documentation(line:utf8Column:) lookup mirroring exactEndColumn's contract"
  - "makeDocument sets single-element SymbolInformation.documentation on definition-role hits"
  - "Fixtures/DocumentationFixture full D6 corpus"
affects:
  - "SCIPIndexBuilder.makeDocument"
tech-stack:
  added: []
  patterns:
    - "name-token anchor keying shared with tokenEndColumns convention"
    - "per-file parse-count dictionary guarded by NSLock as the DOCS-03 proof hook"
key-files:
  created:
    - Fixtures/DocumentationFixture/Package.swift
    - Fixtures/DocumentationFixture/Sources/DocumentationFixture/Documented.swift
  modified:
    - Sources/scip-swift/SourceRefinement/SwiftSyntaxRefiner.swift
    - Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift
    - Tests/scip-swiftTests/SwiftSyntaxRefinerTests.swift
    - Tests/scip-swiftTests/IntegrationTests.swift
    - Tests/scip-swiftTests/CacheStoreTests.swift
decisions:
  - "Accessor doc inheritance covers synthesized accessors (shared name-token anchor); explicit accessor bodies anchor at their own get/set keywords and stay uncovered by design — no accessor special-casing in code"
  - "Documented container is a final class, not a struct: deinit is illegal in a Copyable struct and accessor-vars cannot carry initial values"
  - "Symbol lookup fragments anchor past param-suffix USRs with a trailing backtick-dot because sorted symbol lists place global param symbols before their function"
metrics:
  duration: 43m
  completed: 2026-08-17
actuals:
  tokens: 6860
  tasks: 3
  commits: 6
---

# Phase 9 Plan 01: Symbol Documentation Summary

Swift doc comments (`///` and `/** */`) now flow as normalized Markdown into `SymbolInformation.documentation`, extracted from the same single SwiftSyntax parse that powers Phase 8 exact ranges, with non-doc trivia excluded and accessor inheritance by design.

## What Was Built

- **SwiftSyntaxRefiner doc map (DOCS-01)** — a second map built in the existing `init` after `tokenEndColumns`, walking `DeclSyntax` nodes recursively and keying each declaration's doc at its name-token anchor (per-kind: named decls, var/let bindings, init/deinit keywords, extension extended-type first token, enum-case elements). Doc trivia attaches to the decl's first token — attributes intercept it — while IndexStoreDB anchors at name tokens; keying at first tokens would miss every attributed declaration (sanctioned WHY comments at both non-obvious rules).
- **D4 normalization** — line pieces drop the three-slash marker then at most one leading space; block pieces strip `/**`/`*/` wrappers, drop empty artifact edge lines, then per-line leading `*` and one space; consecutive pieces join with newlines; bare markers and blank interior lines survive as empty lines (paragraph breaks).
- **DOCS-02 exclusions** — plain comments drop out of the trivia-kind filter (`lineComment`/`blockComment` are distinct enum cases); the `////` divider needs the explicit text-drop rule because the parser also classifies it as `docLineComment` (second sanctioned WHY comment).
- **makeDocument wiring (D3)** — after `signatureDocumentation`, definition-role occurrences whose `documentation(line:utf8Column:)` lookup hits get `documentation = [doc]` (single-element array, scip-typescript convention). No accessor special-casing: synthesized getter/setter USRs share the property's anchor and inherit its doc.
- **DOCS-03 parse-count hook** — a package-visible static per-file dictionary (`parseCount(forFilePath:)`) incremented at the sole `Parser.parse` call, guarded by `NSLock` for Swift Testing's parallel suites; asserted at unit level (one refiner = one parse) and integration level (fresh run = exactly 1 per document path; cache-hit run adds zero).
- **DocumentationFixture (D6)** — a one-source-file SwiftPM fixture with the full corpus: license header, single/multi-line docs, block doc with parameter + blank paragraph lines, attribute-interleaved declaration, plain noise between doc and decl, trailing statement comment, four-slash divider (all embedding DOCSMARKER), undocumented decls, documented property with accessors, per-case enum docs, and extension/init/deinit/typealias docs.
- **CacheStore round-trip** — documentation is a field of the serialized `Scip_SymbolInformation`, so cached docs round-trip with zero cache changes and no version bump (0.3.0 unreleased; content-hash keying self-heals pre-phase caches). Byte-identical second run asserted.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tracer RED used a wrong display-name lookup**
- **Found during:** Task 1 RED
- **Issue:** Test located symbols by `add(_:_:) -> Swift.Int` — the real demangled display name is `DocumentationFixture.add(Swift.Int, Swift.Int) -> Swift.Int`.
- **Fix:** Corrected lookup to the real demangled name, then confirmed RED for the right reason (documentation empty).

**2. [Rule 1 - Bug] Doc walk skipped nested declarations**
- **Found during:** Task 2 GREEN
- **Issue:** The recursion only descended into non-decl children, so member decls (init/deinit in a type, enum cases, decls inside code blocks) never visited.
- **Fix:** Recurse into every child regardless of decl-ness. Also fixed `TokenSyntax` access (`.name` IS the token) and the reserved-word `extension` binding.
- **Files modified:** Sources/scip-swift/SourceRefinement/SwiftSyntaxRefiner.swift
- **Commit:** 6a82de1

**3. [Rule 1 - Bug] Block-doc test anchors pointed at line 8 instead of 7**
- **Found during:** Task 2 GREEN
- **Issue:** Miscounted the block-comment lines when writing RED expectations.
- **Fix:** Corrected the two lookups to line 7; net diff vs PHASE_BASE still additive-only (0 deleted lines).

**4. [Rule 1 - Bug] Integration symbol fragments missed real mangling**
- **Found during:** Task 3 GREEN
- **Issue:** Hand-guessed USR fragments were wrong (`7computeySi_SitF` vs real `7computeyS2iF`, `6blockyySi_SitF` vs `6blocky5valueS2i_tF`, `5noisyySitF` vs `5noisySiyF`, `9DocumentedV` vs `10DocumentedC`) and un-anchored fragments matched param symbols sorted before their function.
- **Fix:** Dumped real USRs from the produced index and anchored fragments with a trailing backtick-dot past param-suffix USRs. Fixture expectations unchanged — implementation matched D4 rules throughout.

**5. [Fixture constraint] deinit illegal in Copyable struct; accessor-var cannot initialize**
- **Found during:** Task 3 GREEN
- **Issue:** Swift rejects `deinit` in a `struct` conforming to `Copyable` and rejects initial values on computed-accessor vars.
- **Fix:** Container became `final class`; accessor var has no initializer. Per-kind anchor coverage unchanged (init/deinit/extension/typealias all still asserted).

**6. [Rule 1 - Understanding] Explicit accessor definitions anchor at their own keywords**
- **Found during:** Task 3 GREEN
- **Issue:** Plan asserted getter/setter inheritance on `stored`, but explicit `get`/`set` accessor definitions anchor at the accessor keyword (line 13/14 col 4), not the property name token — only synthesized accessors share the property anchor.
- **Fix:** Inheritance asserted via `frozen`'s synthesized getter AND setter (both verified inheriting in the real index); explicit-accessor coverage stays out by design, consistent with the plan's no-accessor-special-casing rule. Documented in Decisions.

## Verification Evidence

- `swift test --filter SwiftSyntaxRefinerTests` — 23 tests passed (6 pre-existing rows byte-identical + 17 new)
- `swift test --filter IntegrationTests` — 19 tests passed in 4 suites (incl. DocumentationFixture e2e)
- `swift test --filter CacheStoreTests` — 8 tests passed (incl. documentation round-trip)
- `swift test --filter PositionMappingTests` — 5 tests passed (protected)
- Wave gate: `swift test --skip Xcode` — 139 tests in 17 suites passed; `swift test --filter DylibCheckTests` — 3 tests passed (partition union = 142, 0 failures)
- Protected-file gate: `git diff --quiet PHASE_BASE -- IncrementalIntegrationTests ScipIndexMergerTests MultiRepoMergeIntegrationTests SCIPSymbolFormatterTests PositionMapping.swift SCIPSymbolFormatter.swift MiniSwiftPackage UnicodeRangeFixture BrokenSourceFixture` — clean
- Additive-only gate: `grep -c '^-[^-]'` over `SwiftSyntaxRefinerTests` diff vs PHASE_BASE = 0
- One-parse structural gate: `grep -rl 'Parser\.parse' Sources/ | wc -l` = 1

## Known Stubs

None.

## TDD Gate Compliance

Each task followed RED → GREEN with separate commits:

- Task 1: `6b8b563` (test, RED — documentation expectation failed pre-wiring) → `a0c36b5` (feat, GREEN)
- Task 2: `f8bb0d7` (test, RED — suite failed to build on missing `parseCount`, block normalization unimplemented) → `6a82de1` (feat, GREEN)
- Task 3: `c51a625` (test, RED — corpus symbols missing on tracer-only fixture) → `72b4101` (feat, GREEN)

## Commits

- 6b8b563 test(09-01): DocumentationFixture tracer doc expectation fails pre-wiring
- a0c36b5 feat(09-01): doc map in refiner init, wired into makeDocument
- f8bb0d7 test(09-01): full refiner corpus — normalization, exclusions, per-kind anchors, parse hook
- 6a82de1 feat(09-01): complete refiner corpus — block normalization, all decl kinds, parse hook
- c51a625 test(09-01): DocumentationFixture e2e corpus + cache run-pair + protobuf round-trip row
- 72b4101 feat(09-01): full DocumentationFixture corpus green end-to-end

## Self-Check: PASSED

All 7 key files exist; all 6 commit hashes verified in git log.
