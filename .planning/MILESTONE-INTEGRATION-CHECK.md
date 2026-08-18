# Milestone Integration Check — v0.3.0 "Readable Indexes"

**Auditor:** gsd-integration-checker
**Date:** 2026-08-18
**Scope:** Phases 6–9 (REPAIR, SYMBOL, RANGE, DOCS) cross-phase wiring + E2E flow composition
**Base audited:** `main` @ `93b5d30` — which includes ~21 post-v0.3.0 commits from the parallel v1.0 track (02-01..02-04). Post-milestone behavior changes are flagged explicitly below.
**Verdict:** PASSED with warnings — no BLOCKERs. All 4 cross-phase E2E flows complete; 7 warnings (2 are v1.0-track behavior changes against v0.3.0 requirements text).

---

## Wiring Summary

**Connected:** 11 phase exports verified wired end-to-end
**Orphaned:** 1 (pre-existing, not v0.3.0-scoped)
**Missing:** 0

| Export | From → Consumer | Status | Evidence |
|---|---|---|---|
| `produceIndexStore(tool:…destination:)` | Phase 6 → both `indexOneRepo` cache branches | **WIRED** | `IndexCommand.swift:96-122` — single switch-tool helper, called from the persistent-cache build branch and the temp branch; `XcodeIntegrationTests` dispatch tests (temp + `--cache-dir` + derived-data layout) green |
| `XcodebuildBuildRunner.destination` + `-destination` splice | Phase 6 → argv | **WIRED** | `XcodebuildBuildRunner.swift:14,38-41` — inserted immediately before `-derivedDataPath`; nil leaves the list byte-identical (unit test) |
| `BuildError.xcodebuildDestinationFailed` (+ `-showdestinations` hint) | Phase 6 → `produceIndexStore()` | **WIRED** | E2E: bogus destination `platform=bogOS,name=Nope` failed with full output + copyable `xcodebuild -project … -scheme scip-swift-test -showdestinations` hint |
| `SCIPIndexBuilder(demangle:)` seam | Phase 7 → builder displayName assignment | **WIRED** | `SCIPIndexBuilder.swift:26,43,369` — `demangler?.demangledDisplayName(usr:) ?? symbol.name` on non-local symbols; externals via USR side map (`SCIPIndexBuilder.swift:163-172`) |
| `USRDemangler` (dlopen) | Phase 7 → builder | **WIRED** | `Sources/scip-swift/SCIPMapping/USRDemangler.swift`; memoized per-run; `hasPrefix("s:")` gate = SYMBOL-02 fail-soft; 15-test corpus green |
| `ToolchainInfo.libswiftDemangleDylibPath()` | Phase 7 → `USRDemangler.load()` | **WIRED** | `ToolchainInfo.swift:35-49` mirrors the libIndexStore `xcrun --find swift` derivation |
| `--no-demangle` CLI flag | Phase 7 → `run()` → `indexOneRepo(demangle:)` | **WIRED** (caveat W2) | `IndexCommand.swift:35-36,52`; cold-cache run reproduces v0.2.x opaque names (verified E2E) |
| `SwiftSyntaxRefiner` | Phase 8 → `makeDocument` | **WIRED** | `SCIPIndexBuilder.swift:331,358-363` — one refiner per fresh document; `exactEndColumn` feeds `PositionMapping.singleLineRange(exactEndColumn:)`; cache-hit branch skips `makeDocument` entirely |
| `PositionMapping` exact-extent path | Phase 8 → builder → cache | **WIRED** | Exact caret extents confirmed in snapshots (Xcode fixture: `Animal` [6,12), `Foundation` [7,17)); Unicode F4 table + broken-source fallback suites green |
| Refiner doc map + `documentation(line:utf8Column:)` | Phase 9 → `makeDocument` | **WIRED** | `SwiftSyntaxRefiner.swift:46-58,79-83` built in the same `init` parse; `SCIPIndexBuilder.swift:373-381` sets `documentation = [doc]` on definition-role hits |
| Cache doc round-trip | Phase 9 × Phase 3 cache | **WIRED** | Documentation is a field of serialized `Scip_SymbolInformation`; run-pair byte-identical with docs present on both runs (E2E proof below) |

**Orphaned exports:**
- `SCIPIndexBuilder.symbolVersion` — stored (`SCIPIndexBuilder.swift:12,34`) but never read by `build()`/`makeDocument()`/`makeMetadata()`. `IndexManyCommand.swift:49` passes `repoId` into it with no effect (merge path-prefixing derives `repoIdentifiers` independently). Pre-v0.3.0 seam, not a milestone deliverable — cosmetic dead parameter.

### CLI Flag Coverage (this repo's "API routes")

| Surface | Consumed by | Status |
|---|---|---|
| `index --destination` | xcodebuild argv | CONSUMED (E2E: macOS destination build succeeded; bogus → hint) |
| `index --no-demangle` | builder `demangle:` | CONSUMED (E2E opaque output; caveat W2 on warm cache) |
| `index --cache-dir` | `CacheStore` + build scratch | CONSUMED (run-pair byte identity; thrash caveat W7) |
| `index-many --merge` | `ScipIndexMerger.merge` | CONSUMED (dedup on canonical strings, lint clean) |
| `index --index-only` | SwiftPM `findIndexStore` only | **Xcode-asymmetric**: on an Xcode repo errors with a SwiftPM-shaped expected path — known and deliberately out of Phase-6 scope (documented in 06-01-SUMMARY); still true today |

### Auth Protection

N/A — local CLI, no auth/session surface.

---

## E2E Flow Results

### Flow 1 — Xcode repo × Phase 6 dispatch × Phase 7 demangle × Phase 8 ranges × Phase 9 docs — **COMPLETE**

- `Fixtures/XcodeTestProject` (real `xcodebuild`, ~31s): 1 document, `scip lint` **clean (exit 0)**.
- Demangled display names present: `scip_swift_test.Animal.speak() -> Swift.String`, `…Dog.breed.getter : Swift.String`, etc. (23 display names).
- Exact ranges: snapshot carets land on identifier extents (`Animal` [6,12), `Foundation` [7,17)).
- Docs: the shipped Xcode fixture has **no doc comments** (confirmed — 0 `documentation` entries). Proven instead on a doctored copy of the fixture (`/// A documented animal.` / `/// Makes the animal speak.`): xcodebuild path emits `documentation > A documented animal.` and `> Makes the animal speak.` alongside demangled names and exact carets, `scip lint` clean. All four phases compose in one run.
- Secondary proof (SwiftPM path): `DocumentationFixture` index → `scip lint` clean; 37 `documentation` entries render in `scip snapshot` (class, init, deinit, stored-with-accessors inheritance via `frozen`, enum cases, extension/typealias); excluded comment classes (`//`, license header, `////` divider) carry no docs.

### Flow 2 — `--no-demangle` × `--cache-dir` × `index-many --merge` — **COMPLETE** (with W2/W3 caveats)

- `index-many CrossRepoPackageA CrossRepoPackageB --merge --cache-dir <dir>`: 2 documents, merged externals deduped on canonical strings (`scip-swift swift Swift 6.2.4 String#` exactly once, `String#init().` once), **lint clean**.
- Merge determinism: second `--merge` run over the same warm cache byte-identical to the first.
- `--no-demangle` per-repo with `--cache-dir` (via `index`): document symbols carry v0.2.x-style short display names (`SharedType`, `setter:value`); externals empty — correct.
- Cross-mode: `index-many` (demangle-on default) over a cache written by `--no-demangle` runs produced a **byte-identical** merge to a fresh demangle-on merge — because the repo-global overload-fingerprint invalidation (W7) forces regeneration before the stale docs can serve. Dedup keying never depended on display mode.
- Caveat W3: `index-many` exposes neither `--no-demangle` nor `--destination`; the literal composition "`--no-demangle` + `index-many --merge`" is only expressible as per-repo `index --no-demangle` runs + separate merge, or through the library seam. `IndexManyCommand` compiles via the defaulted `demangle: true` — it always demangles.

### Flow 3 — Cached docs (P9) + exact ranges (P8) round-trip — **COMPLETE**

- `DocumentationFixture` run pair through one `--cache-dir`: `run1.scip` vs `run2.scip` **byte-identical** (`cmp` clean).
- Cached run serves identical documents: snapshot diff of `documentation`/`definition`/`display_name` annotations fresh-vs-cached = **empty**; 37 documentation entries on the cached run too.
- One-parse proof intact structurally: exactly one `Parser.parse` site in `Sources/` (`SwiftSyntaxRefiner.swift:29`; the `SCIPIndexBuilder.swift` hits are `USRSymbolParser.parse`, string-level, unrelated). Integration `parseCount` assertions (fresh run = 1 per path; cache run adds 0) green.
- `IncrementalIntegrationTests` "cache-hit second run serves byte-identical exact ranges without re-parsing" green.

### Flow 4 — `--destination` on a SwiftPM repo — **COMPLETE, harmless no-op** (adjacent W5)

- Auto-detect (no `--build-tool`): `MiniSwiftPackage --destination "generic/platform=iOS Simulator"` → detects `.swiftpm`, **ignores the destination silently**, succeeds (1 document). No error, no confusing output.
- Forced `--build-tool xcodebuild` on the SwiftPM repo: fails (exit 1) with `cannotDetectBuildSystem` — correct failure, but **misleading text** (W5): it claims "no Package.swift and no .xcodeproj/.xcworkspace found. Pass --build-tool swiftpm or --build-tool xcodebuild explicitly." while a `Package.swift` exists and the user already passed `--build-tool`.

### Test partitions (all green; union covers the repo's suites)

| Partition | Result |
|---|---|
| XcodeIntegrationTests | 5/5 (real xcodebuild; incl. bogus-destination hint 65s) |
| MultiRepoMergeIntegrationTests | 1/1 |
| IncrementalIntegrationTests | 5/5 |
| ScipCLIGateTests | 11/11 (incl. SchemeFixture goldens + `scip lint` gate) |
| USRDemangler / SwiftSyntaxRefiner / PositionMapping / CacheStore | 53/53 |
| SymbolSchemeGolden / SCIPSymbolFormatter / CanonicalFormatter / USRSymbolParser | 37/37 |
| DeterminismTests | 7/7 (incl. overload-table cache staleness guard) |
| `--filter IntegrationTests` (4 suites incl. base: unicode F4 table, broken source, docs corpus, no-demangle rows) | 20/20 |
| Remaining units (XcodebuildBuildRunner, RelationSpike, IndexManifest, Merger, kind/role/signature/relationship mappers, ContentHasher, DylibCheck) | 84/84 |

---

## Detailed Findings

### BLOCKERs

None.

### Warnings

**W1 — v1.0-track replaced SYMBOL-03's mechanism; the requirement text is now stale in letter (behavior-change flag).**
Commit `ee2f2d2`/`ac18a3d` (02-01) rewrote the Phase-7-era identity guard test from *"canonical symbol string must still embed the raw USR verbatim"* to *"canonical symbol string must be the descriptor-chain form (raw USRs are gone)"*. Current state (`SCIPIndexBuilder.canonicalSymbolString` → `USRSymbolParser`/`USRSymbolMapper`/`CanonicalSymbolFormatter`): parseable USRs emit `scip-swift swiftpm MiniSwiftPackage . Greeter#greet().` — **the raw USR is no longer embedded in the canonical `symbol` field**. Raw USRs survive only as the D-06 fallback for unparseable USRs (escaped term under the canonical module header, e.g. `` scip-swift swiftpm scip_swift_test . `c:@M@Foundation`. `` — observed E2E in the Xcode run). The *spirit* of SYMBOL-03 (stable identity; cache hits and merge dedup unchanged) is preserved and verified: merge dedup keys on the canonical strings (E2E single `String#` external), and `SymbolFormatVersion.current = 2` gates caches (a v0.3.0-era manifest fails decode → wholesale invalidate → regenerate; `IndexManifest.swift:61-68`). **REQUIREMENTS.md SYMBOL-03's literal text ("the wrapped USR stays the canonical `symbol` field") no longer describes the code and should be re-baselined or annotated at milestone sign-off.**

**W2 — demangle mode is not a cache key; `--no-demangle` × warm cache serves the wrong mode (both directions proven).**
The manifest records toolchain/converter/indexstoreDbRevision/buildToolName/symbolFormatVersion/overloadTableFingerprint — no demangle flag. Display names live inside the cached `Scip_SymbolInformation`:
- demangle-on writes cache → subsequent `--no-demangle` run with the same `--cache-dir` serves **demangled** document names (proven: `DocumentationFixture.Documented…` present under `--no-demangle`).
- `--no-demangle` writes cache → subsequent demangle-on run serves **opaque** names (proven: 0 `CrossRepoPackageA.SharedType` display names on the follow-up default run; cold cache = correct demangled).
Cold-cache runs are correct in both modes. This weakens SYMBOL-04 ("reproduce v0.2.x-style opaque output") whenever a warm cache exists. Externals stay correct in both directions (they're recomputed per run from the side map / canonical strings — only cached *document* symbols are affected). Fix shape: add the flag to `IndexManifest.isCompatibleWith` or to the content-hash key.

**W3 — `index-many` cannot express `--no-demangle` (or `--destination`/`--scheme`).**
Flow 2's composition holds only through the default demangle-on path or per-repo `index` runs. If the milestone's user story is "disable demangling for a merged multi-repo index," the CLI cannot do it in one command (`IndexManyCommand.swift` has no such flag; `indexOneRepo(demangle:)` defaults `true`).

**W4 — user-facing docs never picked up the v0.3.0 flags.**
`docs/CONFIGURATION.md` (flag table for `index`/`index-many`) documents neither `--destination` nor `--no-demangle`; README mentions demangling only incidentally. The flags exist on `--help` and in code. Doc gap only — behavior verified.

**W5 — misleading `cannotDetectBuildSystem` message on the forced-xcodebuild-on-SwiftPM path (Flow 4 adjacent).**
Forcing `--build-tool xcodebuild` on a Package.swift-only repo exits 1 claiming "no Package.swift and no .xcodeproj/.xcworkspace found. Pass --build-tool … explicitly" — both clauses wrong for that invocation (Package.swift exists; the user already chose the tool). Pre-existing (`XcodeProjectLocator.workspaceOrProjectArguments` → `BuildError.swift:38-42`), surfaced by Flow 4. The auto-detect path (the common case) is a verified harmless no-op.

**W6 — new stderr diagnostic from the v1.0-track appears on every run.**
`warning: N symbol(s) emitted via the raw-USR fallback (unparseable USRs); first 5: …` (`SymbolMappingDiagnostics`, 02-02). Harmless to output validity (lint stays clean), but scripts diffing stderr across versions will see it; and it reveals that constructor-parameter `ADL_`-suffixed USRs (e.g. `s:…GreeterV4nameACSS_tcfcADL_SSvp`) still fall back to raw-USR symbols — a mapping-coverage regression relative to full canonical naming, not a v0.3.0 requirement.

**W7 — repo-global overload fingerprint makes a shared `--cache-dir` across repos thrash (correctness preserved).**
`overloadTableFingerprint` invalidates `docs/` whenever the set of definitions changes — including when a *different repo* reuses the cache dir. Proven: A→B→A swaps left exactly 1 doc each time (each swap wipes the other repo's). `index-many --merge --cache-dir` therefore caches nothing across its own repos on a cold dir (each repo's fingerprint invalidates the previous one's docs) — merge output stays correct and deterministic (byte-identical on re-run), only the cache utility degrades. Correctness + determinism verified; flagging the perf/fragility only.

### Broken Flows

None. All four flows complete; every break candidate investigated resolved to wired or to a warning above.

### Requirements Integration Map

| Requirement | Integration Path | Status | Issue |
|---|---|---|---|
| REPAIR-01 | `produceIndexStore` helper → both `indexOneRepo` branches → XcodebuildBuildRunner → builder | **WIRED** | — (E2E flow 1; 3 dispatch tests green) |
| REPAIR-02 | `--destination` CLI → `indexOneRepo` → helper → runner splice → xcodebuild argv | **WIRED** | — (E2E macOS-destination build + SwiftPM no-op) |
| REPAIR-03 | runner failure + `destination != nil` → `xcodebuildDestinationFailed` hint | **WIRED** | — (E2E bogus destination → `-showdestinations` hint) |
| SYMBOL-01 | `USRDemangler.load()` → `makeDocument` displayName → `.scip` | **WIRED** | — (demangled names on Xcode + SwiftPM fixtures) |
| SYMBOL-02 | `hasPrefix("s:")` gate + nil-dylib fail-soft → `?? symbol.name` / raw-USR fallback symbols | **WIRED** | — (fallback symbols observed E2E; indexing never failed; see W6 note) |
| SYMBOL-03 | canonical symbol field → cache manifest gating + merger dedup | **PARTIAL** | W1: mechanism replaced by v1.0-track canonical descriptor chains — raw USR no longer embedded for parseable USRs; stability/dedup/cache-gating all verified, but REQUIREMENTS.md text is stale |
| SYMBOL-04 | `--no-demangle` → `indexOneRepo(demangle:)` → builder | **PARTIAL** | W2: correct cold-cache; warm cache serves the other mode's display names. W3: not expressible on `index-many` |
| RANGE-01 | `SwiftSyntaxRefiner` → `exactEndColumn` → `singleLineRange(exactEndColumn:)` → occurrences (+ cache-hit serve) | **WIRED** | — |
| RANGE-02 | refiner line-start byte table → UTF-8 columns E2E (UnicodeRangeFixture F4 table) | **WIRED** | — |
| RANGE-03 | refiner nil-on-miss → `PositionMapping` approximation fallback (BrokenSourceFixture stale-index E2E) | **WIRED** | — |
| DOCS-01 | refiner doc map (same parse) → `makeDocument` `documentation = [doc]` → `.scip` → snapshot render | **WIRED** | — (37 entries render on DocumentationFixture; Xcode path proven via doctored fixture copy) |
| DOCS-02 | trivia-kind filter + `////` divider text-drop → exclusion corpus | **WIRED** | — |
| DOCS-03 | single `Parser.parse` site + `parseCount` hook asserted at unit and integration level (fresh=1, cache-hit adds 0) | **WIRED** | — |

**Requirements with no cross-phase wiring:** REPAIR-01/02/03 are self-contained within Phase 6's build-orchestration layer (`Build/` + `IndexCommand`) — they have no exports consumed by Phases 7–9, though every downstream E2E flow depends on the dispatch they repaired. This is appropriate containment, not a missing connection.

---

## Post-milestone change ledger (v1.0-track vs v0.3.0 behavior)

| Change | Commit | v0.3.0 impact |
|---|---|---|
| Canonical descriptor symbols replace raw USRs in the `symbol` field | `ee2f2d2`, `ac18a3d` | Contradicts SYMBOL-03's literal text (W1); identity/caching integrity preserved via `symbolFormatVersion: 2` |
| USR side map (`docs/<hash>.usrmap`) replaces Phase-7's `usr(fromCanonicalSymbolString:)` inversion for external display names | `710153f` | External demangling now cache-correct in both fresh/cached runs (improvement); old helper fully removed — no dead code |
| `symbolFormatVersion` manifest gating | `710153f` | Old-format caches fail decode → wholesale invalidate → regenerate (verified safe path) |
| Overload-table fingerprint cache validation | `37b2d42` | Adds W7 shared-cache thrash; adds determinism/byte-identity guarantees (DeterminismTests green) |
| Canonical occurrence ordering/dedup; argv-insensitive ToolInfo | `132d768` | Byte-identity across differing `--output` paths preserved — compatible with Phase-7/9 cache byte-identity tests (green) |
| Raw-USR fallback stderr diagnostic | 02-02 | New output on every run (W6) |
| scip CLI pin + goldens, CI toolchain pin | `1d5a464`, `93b5d30` | No v0.3.0 behavior change; lint gate passes on all audited indexes |

Phase-7/8/9 seams all survived: `demangle:` parameter, `USRDemangler`, `ToolchainInfo.libswiftDemangleDylibPath()`, `SwiftSyntaxRefiner` (+doc map), `PositionMapping(exactEndColumn:)`, `makeDocument` documentation wiring, `invalidateAll` scoping — all present and exercised green on current `main`.

---

## Verification Environment

- Toolchain: Swift 6.2.4 (`.swift-version` pin), macOS; `swift build` green.
- `scip` CLI v0.9.0-dev at `~/.local/bin/scip` (matches engine pin 0.9.0) used for `lint`/`print`/`snapshot`.
- All E2E artifacts under `/tmp/v030-intcheck/` (Xcode fixture copy doctored for the docs leg; original fixtures untouched).
- Test partitions each well under the 280s ceiling (slowest: Xcode integration suite 66s).
