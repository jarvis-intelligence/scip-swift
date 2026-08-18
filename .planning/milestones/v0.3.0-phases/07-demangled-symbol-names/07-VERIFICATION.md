---
phase: 07-demangled-symbol-names
verified: 2026-08-16T17:45:18Z
status: passed
score: 7/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 7: Demangled Symbol Names Verification Report

**Phase Goal:** Users see human-readable symbol names in the index while symbol identity, incremental caching, and cross-repo merges behave unchanged
**Verified:** 2026-08-16T17:45:18Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

Every claim below was verified against first-party evidence produced by this verifier: the CLI was run by the verifier against `Fixtures/MiniSwiftPackage`, output decoded with `protoc --decode=scip.Index`, bytes compared with `cmp`, and both test partitions executed. No SUMMARY.md claim was taken as evidence.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Swift symbols in the generated `.scip` display demangled, human-readable names (SC-1 / SYMBOL-01) | ✓ VERIFIED | Verifier ran `.build/debug/scip-swift index` on the fixture; decoded output contains `MiniSwiftPackage.Greeter.greet() -> Swift.String`, `MiniSwiftPackage.Greeter.name.getter : Swift.String`, `MiniSwiftPackage.Greeter.init(name: Swift.String) -> MiniSwiftPackage.Greeter` in `display_name`. IntegrationTests 14/14 green. |
| 2 | Non-demanglable USRs keep the opaque form and indexing never fails (SC-2 / SYMBOL-02) | ✓ VERIFIED | `USRDemanglerTests` 15/15 green in 0.166s: `c:objc/cs`, `c:@F@printf`, closure, local-decl-suffix, `s:garbage`, empty string all return nil; `init(dylibPath: "/nonexistent")` → nil instance. `s:`-gate at `USRDemangler.swift:43` plus `?? symbol.name` fallback at `SCIPIndexBuilder.swift:183`. No throws anywhere on the path. |
| 3 | Canonical `symbol` field keeps the wrapped USR — identity untouched (SC-3a) | ✓ VERIFIED | Decoded output: every `symbol:` embeds the raw USR verbatim (`scip-swift swiftpm MiniSwiftPackage . \`s:16MiniSwiftPackage7GreeterV5greetSSyF\`.`); `SCIPSymbolFormatter.swift` and its test suite byte-identical to base 815c282 (empty `git diff --stat`). IntegrationTests identity guard asserts the verbatim USR. |
| 4 | Second run over unchanged sources produces byte-identical output (SC-3b) | ✓ VERIFIED | Verifier compared bytes: fresh-cache→fresh-cache run pair `cmp`-identical; cache-hit second run (with and without demangling) `cmp`-identical. `IncrementalIntegrationTests` diff vs base is +60/-0 (additions only — all three pre-existing rows unmodified) and 4/4 green. |
| 5 | Cross-repo merge dedup unchanged (SC-3c) | ✓ VERIFIED | `ScipIndexMergerTests` and `MultiRepoMergeIntegrationTests` byte-identical to base 815c282 (empty diff); merger suites green in the 106-test partition run. |
| 6 | `--no-demangle` reproduces v0.2.x-style opaque output (SC-4 / SYMBOL-04) | ✓ VERIFIED | Verifier ran with `--no-demangle`: display names are exactly `Greeter` / `greet()` / `name` / `init(name:)` / `getter:name` / `setter:name`; external_symbols carry **zero** `display_name` fields (v0.2.x parity). Flag present in `index --help`. Default (no flag) produces demangled names — confirmed by truth 1 runs. |
| 7 | Cache-upgrade: 0.2.1-written caches regenerate demangled documents, never serve stale (SC-3 / D4) | ✓ VERIFIED | `IncrementalIntegrationTests.cacheUpgradeRegeneratesDocuments` green: seeds 0.2.1 manifest + stale short-name doc for an identical-hash file, asserts demangled `MiniSwiftPackage.Greeter` present, short `Greeter` absent, manifest refreshed to 0.3.0. `IndexManifestTests` 8/8 incl. new incompatibility row. |

**Score:** 7/7 truths verified (0 present, behavior-unverified)

### Cache-store invalidation fix (disclosed deviation — evaluated honestly)

The executor disclosed rewriting `CacheStoreTests.invalidateAllRemovesDir`. Verifier's independent assessment: **the fix is real and the new contract is genuinely stronger.**

- **Bug is real.** Base 815c282 `invalidateAll()` was `removeItem(atPath: cacheDir)` — the whole directory. In `indexOneRepo` the persistent-cache branch builds the index store into `cacheDir/build-scratch` (and opens `cacheDir/index-db`) *before* the manifest compatibility check calls `invalidateAll()`. A version-upgrade run with a persistent cache therefore deleted its own just-built inputs and produced a silent empty index. Any 0.2.1→0.3.0 upgrade user with `.scip-cache` hit this.
- **New contract is stronger, not weaker.** Old test: 1 assertion (dir gone). New test (`invalidateAllRemovesCacheContents`): 5 assertions — docs/ removed, manifest.json removed, cache dir **survives** (guarding the build-scratch ownership boundary), `loadDocument` → nil, `loadManifest` → nil. It also now seeds a manifest, which the old test never exercised. The rewrite corrects the contract to match the bug fix and adds coverage.
- The scope change is minimal and correct: `docs/` + `manifest.json` are `CacheStore`'s own artifacts; `build-scratch/`/`index-db/` belong to the build step.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/scip-swift/SCIPMapping/USRDemangler.swift` | dlopen/dlsym demangler, `s:` gate, memoization, n+1 retry, nil fallback | ✓ VERIFIED | 78 lines; all five behaviors present; WHY comments only at buffer-ownership + load sites (per plan) |
| `Sources/scip-swift/Platform/ToolchainInfo.swift` | `libswiftDemangleDylibPath()` mirroring the IndexStore resolution | ✓ VERIFIED | Lines 36–49; mirrors `libIndexStoreDylibPath` line for line |
| `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` | `demangle: Bool = true` init param; non-local displayName from demangler; externals filled on, empty off | ✓ VERIFIED | Line 21 param, line 183 assignment (`isLocal ? symbol.name : demangler?.… ?? symbol.name`), lines 95–101 externals, `usr(fromCanonicalSymbolString:)` recovery |
| `Sources/scip-swift/Version.swift` | 0.3.0 | ✓ VERIFIED | `static let version = "0.3.0"`; landed in the same commit `d9a028b` as the display change (Pitfall 4 satisfied) |
| `Sources/scip-swift/Commands/IndexCommand.swift` | `@Flag` noDemangle threaded to `indexOneRepo` → builder | ✓ VERIFIED | Lines 33–34 flag, line 53 `demangle: !noDemangle`, line 70 defaulted param, line 158 builder forward |
| `Tests/scip-swiftTests/USRDemanglerTests.swift` | corpus + fallback contract suite | ✓ VERIFIED | 15 tests, 16 `#expect` assertions, 15/15 green |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| IndexCommand `noDemangle` flag | `indexOneRepo(demangle:)` | defaulted param, `!noDemangle` at call site | ✓ WIRED |
| `indexOneRepo` | `SCIPIndexBuilder(demangle:)` | constructor arg, line 158 | ✓ WIRED |
| `ToolchainInfo.libswiftDemangleDylibPath()` | `USRDemangler.load()` | `try?` + nil-on-any-failure (line 33) | ✓ WIRED |
| Builder `build()` | demangler per run | `demangle ? USRDemangler.load() : nil` — single instance shared by makeDocument + externals loop (D6) | ✓ WIRED |
| `ScipSwiftVersion.version` | manifest invalidation | `isCompatibleWith(converterVersion:)` → `invalidateAll()` + fresh manifest, lines 128–139 | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `USRDemangler.demangledDisplayName` | demangled string | live `libswiftDemangle.dylib` C ABI via dlopen (verified: decoded output matches the ABI's real demanglings, e.g. stringInterpolation externals) | ✓ | ✓ FLOWING |
| `makeDocument` displayName | `symbolInformation.displayName` | `demangler?.demangledDisplayName(usr:) ?? symbol.name` — falls back to IndexStoreDB short name, never empty | ✓ | ✓ FLOWING |
| external_symbols displayName | `info.displayName` | same per-run demangler, USR recovered from canonical string (cache-independent) | ✓ | ✓ FLOWING |
| cache invalidation trigger | `manifest.converterVersion` | `ScipSwiftVersion.version` compared per run | ✓ | ✓ FLOWING |

### Behavioral Spot-Checks (all executed by this verifier)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Demangled names in real `.scip` | `scip-swift index` on fixture + `protoc --decode` | 27 `MiniSwiftPackage.Greeter*` display names | ✓ PASS |
| Canonical symbol keeps raw USR | decoded output inspection | `…\`s:16MiniSwiftPackage7GreeterV5greetSSyF\`.` verbatim | ✓ PASS |
| `--no-demangle` = v0.2.x short names | CLI run + decode | exactly `Greeter`/`greet()`/`name`/`init(name:)`/`getter:name`/`setter:name` | ✓ PASS |
| Externals empty when off | decoded externals section | 0 `display_name` fields | ✓ PASS |
| Second-run byte-identity (cache-miss pair) | `cmp run-a.scip index.scip` (identical argv, fresh caches) | identical | ✓ PASS |
| Second-run byte-identity (cache-hit) | `cmp` with/without demangling | identical both modes | ✓ PASS |
| `--help` advertises flag | `scip-swift index --help` | `--no-demangle` + help text present | ✓ PASS |
| `scip lint` on demangled index | `scip lint run1.scip` | exit 0, no output | ✓ PASS |
| Version bump in same commit as display change | `git show --stat d9a028b` | `Version.swift | 2 +-` in d9a028b | ✓ PASS |

### Probe Execution

None declared for this phase — Step 7c not applicable (behavioral spot-checks above cover the runnable surface).

### Test Execution (this verifier, toolchain 6.2.4)

| Partition | Command | Result | Status |
|-----------|---------|--------|--------|
| Enumeration | `swift test --list-tests` | 125 tests | 125 = expected count |
| Demangler unit | `swift test --filter USRDemanglerTests` | 15/15 in 0.166s | ✓ PASS |
| Non-Xcode | `swift test --skip Xcode` | 106 tests / 15 suites | ✓ PASS |
| Xcode | `swift test --filter Xcode` | 19 tests / 3 suites | ✓ PASS |
| Union coverage | 106 + 19 = 125 = enumerated | complete, 0 failures | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SYMBOL-01 | 07-01 | Demangled human-readable names for Swift symbols | ✓ SATISFIED | Truth 1 |
| SYMBOL-02 | 07-01 | Opaque fallback for non-demanglable USRs; never fails | ✓ SATISFIED | Truth 2 |
| SYMBOL-03 | 07-02 | Identity stable: canonical USR; incremental + merge unchanged | ✓ SATISFIED | Truths 3–5, 7 |
| SYMBOL-04 | 07-02 | `--no-demangle` reproduces v0.2.x output | ✓ SATISFIED | Truth 6 |

No orphaned requirements — REQUIREMENTS.md maps exactly SYMBOL-01..04 to Phase 7, all claimed by plans.

**Bookkeeping note:** REQUIREMENTS.md already marks SYMBOL-03/04 Complete but SYMBOL-01/02 `pending`, and ROADMAP.md Phase 7 checkbox is still unchecked `[ ]` while both plans show 2/2 executed. Cosmetic state-lag in planning docs, not a code gap — the verification above proves all four satisfied; the roadmap/requirements tick belongs to the ship/complete flow.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Sources/…/IndexCommand.swift` | 57 | `print(...)` | ℹ️ Info | Pre-existing success message, present identically at base 815c282 — not introduced by this phase |
| `Tests/…/RelationSpikeTests.swift` | 104–126 | `print(...)` | ℹ️ Info | Pre-existing relation-spike diagnostic suite (8 prints at base); only the one planned display-name assertion line changed this phase |

No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER in any phase-modified file. No test skips (`XCTSkip`/`.skip`) anywhere. No debug breakpoints.

### Disclosed-Change Audit (no undisclosed test weakening)

Complete deleted-line audit vs base 815c282 across all test files — every removal accounted for:
1. `CacheStoreTests` invalidateAll row — the disclosed bug-fix contract rewrite (assessed stronger above)
2. `IntegrationTests` 3 short-name expectations — the planned re-baseline to demangled strings
3. `RelationSpikeTests` `"Dog"` — the planned re-baseline to `"RelationSpike.Dog"`

All other test diffs are pure additions (+364 lines, −7 disclosed). Protected guards byte-identical: `SCIPSymbolFormatter.swift`, `SCIPSymbolFormatterTests.swift`, `ScipIndexMergerTests.swift`, `MultiRepoMergeIntegrationTests.swift` (empty diff vs 815c282); `IncrementalIntegrationTests.swift` additions-only (+60/−0).

### Commits Verified

All 11 claimed commits exist and are reachable from HEAD (verified via `git merge-base --is-ancestor`): 565a26b, d9a028b, dfd36a3, 6eb9dd1, 1dee3b9, 4acc0e4, ea9e4a9, 8e5da08, 5e66f00, 9c38bfd, 79c65a4.

### Working Tree

Clean except `PHASE_BASE` (untracked, per plan instruction "Do not commit PHASE_BASE") — expected state.

### Human Verification Required

None. All truths carried behavioral evidence from this verifier's own executions.

### Gaps Summary

No gaps. The phase goal is achieved and independently proven: demangled names land in `display_name` with identity untouched, the fallback contract holds, byte-identity and merge dedup are unchanged (guards byte-identical to base), `--no-demangle` reproduces v0.2.x output exactly, and cache upgrades regenerate rather than serve. The disclosed `invalidateAll` fix addresses a genuine pre-existing bug and its rewritten test asserts a stronger contract. The only observations are informational: pre-existing `print` diagnostics (not phase-introduced) and planning-doc checkboxes not yet ticked for SYMBOL-01/02 (ship-flow bookkeeping).

---

_Verified: 2026-08-16T17:45:18Z_
_Verifier: gsd-verifier_
