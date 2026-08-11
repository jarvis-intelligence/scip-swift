# Codebase Concerns

**Analysis Date:** 2026-08-11

> **Primary reference:** `docs/research-scip-swift-limitations.md` is the authoritative deep-dive. This document summarizes and prioritizes its findings for quick reference during planning.

## Tech Debt

**Relationships (inheritance/conformance/override) silently discarded — HIGH:**
- Issue: `SCIPIndexBuilder.makeDocument()` (`SCIPIndexBuilder.swift:61-112`) never reads `occurrence.relations`. IndexStoreDB fetches them from the compiler but they're thrown away.
- Why: The initial implementation focused on occurrences/symbols; relationships weren't in the original scope.
- Impact: The emitted index **cannot power** "Find implementations", inheritance hierarchy navigation, protocol conformance links, or method override resolution — core code-intelligence features. Peer indexers (scip-typescript) populate these.
- Fix approach: Map IndexStoreDB `.baseOf`/`.extendedBy` → `is_implementation`, `.overrideOf` → `is_reference`, `.childOf` → `enclosing_symbol`. The `scip.proto` `Relationship` message exists for exactly this. Severity: HIGH, Fixability: MEDIUM (API exists, mapping is approximate).

**`documentation` and `signature_documentation` never populated — MEDIUM:**
- Issue: `SCIPIndexBuilder.swift:98-101` sets only `symbol`, `displayName`, `kind` on `Scip_SymbolInformation`. SCIP's `documentation` and `signature_documentation` fields are always empty.
- Why: IndexStoreDB doesn't hand back docstrings directly; full implementation would need source-comment parsing.
- Impact: Hover tooltips in SCIP consumers are bare — no API docs, no signature info.
- Fix approach: Basic signatures (e.g. `func greet(name: String) -> String`) are reconstructible from kind/subKind/name. Full docstrings need source-comment parsing. Fixability: MEDIUM.

**SymbolRole mapping is lossier than necessary — MEDIUM, EASY FIX:**
- Issue: `SymbolRoleMapping.scipRoles()` (`SymbolRoleMapping.swift:9-20`) maps only 4 of ~20 IndexStoreDB roles. Drops `.declaration` (could map to `ForwardDefinition = 0x40`), `.implicit`, and never sets SCIP's own `Generated = 0x10` or `Test = 0x20` bits.
- Why: Initial mapping covered the minimum needed for `scip lint` to pass.
- Impact: Test symbols aren't tagged as tests; generated code isn't tagged as generated; forward declarations aren't distinguished from definitions.
- Fix approach: Pure-function additions to `SymbolRoleMapping`. `SymbolProperty.unitTest` identifies test symbols. Fixability: EASY — no architectural change needed.

**`enclosing_symbol` never set for locals — LOW, EASY:**
- Issue: SCIP's `enclosing_symbol` field is never populated. IndexStoreDB's `.childOf` relation carries exactly this.
- Why: Same as relationships — relations aren't read.
- Fix approach: Set once relationships are read (`.childOf` → `enclosing_symbol`). Fixability: EASY, but blocked by the relationships fix.

**`isSystem` location flag ignored — LOW, EASY:**
- Issue: `SymbolLocation.isSystem` marks Swift-stdlib/system-framework occurrences. The project infers `external_symbols` by heuristic (referenced-but-not-defined) instead.
- Why: The heuristic was simpler and passes `scip lint`.
- Impact: External-symbol classification is heuristic-based, not authoritative.
- Fix approach: Use `isSystem` directly for more correct `external_symbols` classification. Fixability: EASY.

## Known Bugs

No known bugs in the current implementation. The emitted index passes `scip lint` and is functionally correct for the features it supports (symbol resolution, go-to-definition, find-references).

## Security Considerations

**Subprocess execution (build orchestration):**
- Risk: `SubprocessRunner.run()` executes `swift build` and `xcodebuild` with user-provided repo paths and arguments. A malicious repo path could theoretically include shell injection.
- Current mitigation: `SubprocessRunner` uses `Process` with explicit argument arrays (not shell interpolation), so command injection is not possible. Paths are resolved via `URL.standardizedFileURL`.
- Recommendations: Current implementation is adequate for a CLI tool run by developers. No changes needed.

**No secrets handling:**
- Risk: None — the tool doesn't read, store, or transmit secrets. It reads source code and compiler index data only.
- Current mitigation: N/A

## Performance Bottlenecks

**Full rebuild every invocation:**
- Problem: Every `scip-swift` run triggers a full `swift build` or `xcodebuild build` of the target repo from scratch.
- Measurement: Build time dominates — for a small fixture, the integration test takes ~10-30s (mostly `swift build`). For large repos, build time is the bottleneck.
- Cause: The tool doesn't cache or reuse build output; it creates a fresh scratch/derived-data path per run.
- Improvement path: Incremental builds via a persistent scratch path; or an "index-only" mode that skips the build and reads an existing IndexStore. This is an architectural decision (documented in roadmap as future work).

**In-memory processing:**
- Problem: All occurrences are loaded into memory before serialization. For very large codebases, this could be memory-intensive.
- Measurement: Not measured — the fixture is tiny.
- Cause: `SCIPIndexBuilder.build()` iterates all files, accumulates all `Scip_Document`s and `referencedSymbols` in memory, then serializes.
- Improvement path: Streaming serialization if memory becomes an issue (not currently a problem for typical repos).

## Fragile Areas

**Toolchain / `libIndexStore.dylib` resolution:**
- Why fragile: The tool shells out to `xcrun --find swift` and resolves `libIndexStore.dylib` relative to the result. If the user has a non-standard toolchain, or `xcrun` returns an unexpected path, the dylib won't be found.
- Common failures: "dylib not found" on systems with multiple Xcode versions, or after an Xcode update that moves the toolchain.
- Safe modification: `ToolchainInfo.libIndexStorePath` is the single point of resolution — changes here affect all IndexStoreDB opening. Test thoroughly.
- Test coverage: No unit test for dylib resolution (would require mocking the toolchain). Integration test implicitly covers it (if the dylib isn't found, the integration test fails).

**IndexStore path discovery (SwiftPMBuildRunner):**
- Why fragile: `SwiftPMBuildRunner.findIndexStore()` scans `<scratch>/<triple>/<config>/index/store` by enumerating directories. The triple directory name depends on the host platform and is not predictable.
- Common failures: If SwiftPM changes its scratch-path layout (has happened across major versions), the index store won't be found, producing `BuildError.indexStoreNotProduced`.
- Safe modification: The directory-walking logic in `findIndexStore()` is the adaptation point for layout changes.
- Test coverage: Integration test covers it against the current SwiftPM version, but not future versions.

**Xcode build path (no `-destination`):**
- Why fragile: `XcodebuildBuildRunner` passes no `-destination` flag, targeting generic "My Mac". The code comment explains: a forced iOS destination breaks macOS-app projects, while no destination means iOS-specific targets may not fully index.
- Common failures: iOS-only projects may not index completely; the trade-off is documented in the code.
- Safe modification: Do NOT add `-destination` without understanding the full trade-off (documented in `XcodebuildBuildRunner.swift:24-31`).
- Test coverage: `XcodebuildBuildRunnerTests` tests argument construction only — no end-to-end Xcode build fixture exists (documented limitation L9).

**Generated protobuf bindings (vendored):**
- Why fragile: `Generated/Scip.pb.swift` is 3190 lines of auto-generated code. Hand-editing it would be silently overwritten on regeneration.
- Common failures: N/A — the file is correct as generated.
- Safe modification: NEVER edit `Generated/Scip.pb.swift`. Edit `Protos/scip.proto` and run `Protos/generate.sh` instead.
- Test coverage: Implicit — the integration test serializes/deserializes protobuf messages, exercising the bindings.

**USR instability across Swift versions:**
- Why fragile: Swift USRs (symbol identifiers) are not guaranteed stable across toolchain versions. The toolchain is pinned to 6.2.4 via `.swift-version`, but CI and local development must use this exact version.
- Common failures: Building/testing with a different toolchain produces different USRs, making symbol comparisons across runs unreliable.
- Safe modification: Do not change `.swift-version` without understanding USR migration implications.
- Test coverage: USR-dependent assertions in `SCIPSymbolFormatterTests` use specific USR strings — these would break if the toolchain changes.

## Comparison with Peer Indexers

| Capability | scip-typescript | scip-rust | **scip-swift** |
|---|---|---|---|
| Human-readable symbol names | ✅ descriptor chains | ✅ descriptor chains | ❌ raw USR (opaque) |
| Inheritance/conformance relationships | ✅ `Relationship` | ✅ `Relationship` | ❌ dropped |
| Documentation/signatures | partial | partial | ❌ none |
| Exact occurrence ranges | ✅ | ✅ | ❌ approximated |
| Cross-platform host | ✅ | ✅ | ❌ macOS-only |

**Biggest gaps (by impact):**
1. **Relationships dropped** (HIGH) — fixable with existing API, no fundamental blocker
2. **Opaque USR symbol names** (HIGH) — hardest gap; needs a demangling library or custom demangler; roadmap defers to v1.0+ (H2 2027)
3. **No documentation/signatures** (MEDIUM) — basic signatures reconstructible from existing data

---

*Concerns analysis: 2026-08-11*
*Primary reference: `docs/research-scip-swift-limitations.md`*
*Update when limitations change or are addressed*
