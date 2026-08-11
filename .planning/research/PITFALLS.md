# Pitfalls Research

**Domain:** Compiler-index-to-SCIP protobuf conversion (IndexStoreDB → SCIP), with incremental indexing, multi-repo merge, metadata enrichment, and Homebrew distribution
**Researched:** 2026-08-11
**Confidence:** HIGH (findings verified against primary sources: `scip.proto` canonical, `scip lint` Go source, IndexStoreDB Swift API source, project codebase)

## Critical Pitfalls

### Pitfall 1: Relationships silently dropped — produces an index that can't power "Find implementations"

**What goes wrong:**
IndexStoreDB's `SymbolOccurrence` carries a `relations: [SymbolRelation]` array populated by the compiler. Each relation has a `SymbolRole` from a set of relation roles: `.childOf`, `.baseOf`, `.overrideOf`, `.extendedBy`, `.accessorOf`, `.containedBy`, `.specializationOf`, `.calledBy`, `.receivedBy`. The current `SCIPIndexBuilder.makeDocument()` (`SCIPIndexBuilder.swift:61-112`) **never reads `occurrence.relations`** — the data is fetched from the compiler and thrown away. The resulting `.scip` index has no `Relationship` entries, so consumers cannot power inheritance hierarchy navigation, protocol conformance links, method override resolution, or "Find implementations." Peer indexers (scip-typescript) populate these.

**Why it happens:**
The initial implementation scoped itself to occurrences/symbols only. The `SymbolOccurrence` init parses relations from the C callback (`indexstoredb_symbol_occurrence_relations`), so they're available — but the builder loop only reads `occurrence.symbol`, `occurrence.roles`, `occurrence.location`. There's no code path that touches `occurrence.relations`.

**How to avoid:**
When implementing relationships, read `occurrence.relations` in the `makeDocument` loop and map to `Scip_Relationship`:
- `.baseOf` / `.extendedBy` → `is_implementation = true` (protocol conformance / inheritance)
- `.overrideOf` → `is_reference = true` (overrides group with base for Find References)
- `.childOf` → set `enclosing_symbol` on the `SymbolInformation` (not a Relationship — it's a field on `SymbolInformation`)

Validate empirically that Swift symbol provider populates relations at the same depth as Clang before committing to the design. The `SymbolOccurrence.symbolProvider` field (`.swift` vs `.clang`) lets you filter and compare.

**Warning signs:**
- `scip lint` passes but "Find implementations" returns nothing in Sourcegraph
- SCIP output contains zero `relationships` entries across all `SymbolInformation` messages
- Spot-check: index a file with `class B: A {}` and confirm `B` has a relationship to `A`

**Phase to address:**
Metadata Enrichment phase — this is the highest-impact missing feature. Must be the first enrichment implemented because `enclosing_symbol` (Pitfall 7) is blocked by it.

---

### Pitfall 2: Relationship booleans set incorrectly — breaks Find References or Find Implementations

**What goes wrong:**
SCIP's `Relationship` message has 4 booleans: `is_reference`, `is_implementation`, `is_type_definition`, `is_definition`. Getting these wrong has specific consequences:
- Setting `is_reference` on an implementation relationship causes "Find References" on a protocol to return all conforming types — usually wrong for Swift protocols
- Setting `is_implementation` without `is_reference` is correct for pure "Find Implementations" but means Find References won't group them
- `scip lint` enforces at least one boolean must be set (`missingRelationshipFlagError`), and the target `symbol` string must exist in the index (`missingSymbolInRelationshipError`)

The proto's own TypeScript example shows the intended semantics: `Dog implements Animal` → `Dog#` has `{symbol: "Animal#", is_implementation: true}` but **not** `is_reference`. This is because "Find references" on `Animal#` should not return `Dog#` — only "Find implementations" should.

**Why it happens:**
IndexStoreDB's relation roles don't map 1:1 to SCIP's 4 booleans. `.baseOf` could mean inheritance (is_implementation) or protocol conformance (is_implementation), but Swift protocol method requirements vs. implementations need different treatment. The `is_definition` boolean is for overriding "Go to definition" behavior — rarely needed in Swift but semantically distinct from `is_reference`.

**How to avoid:**
Define an explicit mapping table and validate it against the proto's TypeScript example before implementing. For Swift:
- Protocol conformance (`struct S: P`): `is_implementation = true`, `is_reference = false`
- Method override (`override func`): `is_reference = true`, `is_implementation = false`
- Protocol method requirement → implementation: both `is_reference` and `is_implementation`
- Never set `is_type_definition` unless you have actual type-alias / typealias data
- Every `Relationship.symbol` must reference a symbol that exists either in `document.symbols` or `external_symbols` — otherwise `scip lint` errors

**Warning signs:**
- `scip lint` error: `missingRelationshipFlagError` (no booleans set)
- `scip lint` error: `missingSymbolInRelationshipError` (target symbol not in index)
- "Find implementations" returns protocol conforming types in "Find references" results

**Phase to address:**
Metadata Enrichment phase — design the mapping table as the first deliverable before writing any mapping code.

---

### Pitfall 3: Incremental cache invalidated incorrectly — serves stale occurrence data

**What goes wrong:**
IndexStoreDB maintains a **separate database** (at `databasePath`) from the index store itself (at `storePath`). The database is a derived view built from the store. If the underlying store changes (new build produces new index units) but the database is reused without polling for changes, it silently serves stale occurrence data. The `IndexStoreDB` initializer has `listenToUnitEvents` (default `true`) which auto-polls, but if you cache the `IndexStoreDB` instance across runs or open with `readonly: true` + `waitUntilDoneInitializing: false`, you get a frozen snapshot.

Additionally, the current tool creates a **fresh scratch path per run** (`IndexCommand` owns a temp work directory). If incremental indexing reuses a persistent scratch path, SwiftPM's incremental build may skip recompiling files that *did* change if the build system's own dependency graph is stale.

**Why it happens:**
The IndexStoreDB API surface has subtle lifecycle semantics: `pollForUnitChangesAndWait()` must be called if `listenToUnitEvents` is false; `dateOfLatestUnitFor(filePath:)` exposes per-file staleness but is easy to overlook. The `IndexDelegate.unitIsOutOfDate` callback exists for exactly this but requires implementing the `IndexDelegate` protocol. On the build side, SwiftPM's `--scratch-path` reuse is designed for incremental compilation, but an interrupted or partial previous build can leave the scratch directory in an inconsistent state.

**How to avoid:**
- Always open `IndexStoreDB` fresh from the current store path with `waitUntilDoneInitializing: true` (current code does this correctly — preserve it)
- For incremental indexing: use `dateOfLatestUnitFor(filePath:)` to check if a file's index data is newer than your cache entry before reusing cached SCIP output
- Never cache the `IndexStoreDB` instance across invocations — the database is cheap to rebuild
- If reusing a persistent scratch path: validate the build succeeded (exit code 0) before trusting the index store. A failed incremental build may produce a partial store
- Consider a cache key that includes: file mtime + toolchain version (`.swift-version` content) + scip-swift version

**Warning signs:**
- SCIP output references symbols that no longer exist in source after a rename
- Occurrence line numbers drift after code changes
- `scip lint` passes but Sourcegraph shows "go to definition" jumping to old locations
- Integration test becomes flaky when run twice in sequence

**Phase to address:**
Incremental Indexing phase — design the cache invalidation strategy before any caching code. The staleness check must be correct or the feature is worse than no caching.

---

### Pitfall 4: Multi-repo symbol collision — cross-repo references silently break

**What goes wrong:**
When merging or linking indexes across repos, symbol strings must be globally unique and consistent. scip-swift formats symbols as `scip-swift <manager> <moduleName> <version> <usr>.`. Two failure modes:
1. **Module name collision:** If RepoA and RepoB both have a module named `Core`, their symbols produce identical SCIP strings (same manager, same module name, same empty version, potentially same USR pattern). `scip lint` will emit `duplicateSymbolInfoWarning` for external symbols.
2. **USR skew across toolchains:** If RepoA is indexed with Swift 6.2.4 and RepoB with Swift 6.0, the same logical symbol (e.g. `String.count`) may have different USRs, producing different SCIP symbol strings. Cross-repo references silently fail to resolve.

The SCIP spec's `external_symbols` field documentation says: *"Leave this field empty if you assume the external package will get indexed separately."* This means if you plan to merge indexes, you should NOT emit external_symbols for cross-repo dependencies — they'll be resolved when both indexes are loaded together.

**Why it happens:**
The symbol format uses raw USR as the descriptor, and the version field is currently hardcoded empty (`escapeSpaceField("")` in `SCIPSymbolFormatter`). Module name comes from `occurrence.location.moduleName`, which is the Swift module name — not guaranteed globally unique across independent packages.

**How to avoid:**
- For multi-repo mode: require all repos to be indexed with the same Swift toolchain version (validate `.swift-version` match before merging)
- Populate the `version` field in the symbol package to disambiguate same-named modules from different packages (use the SwiftPM package version or a hash of the package URL)
- Before merging, run `scip lint` on the combined index to catch duplicate external symbols
- Consider whether to suppress `external_symbols` emission entirely when operating in multi-repo mode (let the consumer resolve cross-repo refs from loaded indexes)

**Warning signs:**
- `scip lint` warnings about duplicate external symbols after merge
- "Go to definition" for cross-repo symbols resolves to the wrong repo
- Two unrelated symbols from different repos have identical SCIP symbol strings

**Phase to address:**
Multi-Repo / Cross-Repo phase — design the symbol disambiguation strategy before implementing merge logic. Version-field population may need to be retrofitted into `SCIPSymbolFormatter`.

---

### Pitfall 5: Homebrew formula ships a broken binary — libIndexStore.dylib not found at runtime

**What goes wrong:**
`scip-swift` dynamically loads `libIndexStore.dylib` at runtime via `IndexStoreLibrary(dylibPath:)`, resolving the path from `xcrun --find swift` → toolchain root → `lib/libIndexStore.dylib` (`ToolchainInfo.swift:18-30`). This dylib ships **only with Xcode** — it is not part of the CommandLineTools package, and it is not a Homebrew-installable dependency. If the formula installs the binary but the user has only CommandLineTools (no Xcode), or has a non-standard Xcode path, the tool crashes at first run with a dylib-not-found error.

Additionally:
- The binary statically links the Swift runtime (since Swift 5.0+), so no Swift runtime dependency is needed — this is fine
- `IndexStoreDB` itself is statically linked into the binary, so no runtime dependency there
- Gatekeeper may quarantine GitHub Release binaries; Homebrew install bypasses this for `brew install` but not for direct `curl` downloads
- Universal binary (arm64 + x86_64) requires building twice and `lipo`-creating, or using `swift build --arch arm64 --arch x86_64`

**Why it happens:**
Xcode is not a Homebrew package. There's no way to declare `depends_on xcode` in a formula. The dylib lives at a toolchain-specific path that varies across Xcode versions and installations (App Store vs. xip-install, beta vs. release).

**How to avoid:**
- Document the Xcode requirement prominently in the formula `desc` and README
- Add a runtime check in the tool itself: if `libIndexStore.dylib` can't be resolved, print a clear error message instructing the user to install Xcode (not just CommandLineTools) and run `xcode-select --install` or `sudo xcode-select -s /Applications/Xcode.app`
- For the formula: consider using a pre-built bottle from GitHub Releases rather than building from source (faster install, but the dylib dependency is the same)
- For universal binaries: test the x86_64 build on an Intel Mac or via Rosetta before shipping

**Warning signs:**
- Users report `dyld: Library not loaded: libIndexStore.dylib` on first run
- The formula installs successfully but the tool crashes immediately
- Issues filed by users who have only CommandLineTools installed

**Phase to address:**
Homebrew Formula phase — implement the runtime dylib-resolution check and clear error message as part of the formula work, not after.

---

### Pitfall 6: `external_symbols` emits symbols that make merged indexes fail scip lint

**What goes wrong:**
The current `external_symbols` classification uses a heuristic: any symbol that is referenced but never defined in this index goes into `external_symbols` (`SCIPIndexBuilder.swift:41-43`). This is correct for single-repo use. But in multi-repo mode, if RepoA emits `external_symbols` for symbols defined in RepoB, and RepoB's index is loaded alongside RepoA's, the consumer now sees duplicate `SymbolInformation` entries for the same symbol — once as external in RepoA, once as defined in RepoB. The SCIP spec explicitly says: leave `external_symbols` empty if the external package will be indexed separately.

Additionally, `scip lint` has a hard error (`bothLocalAndExternalSymbolError`): a symbol cannot be present in both `external_symbols` and any document's `symbols`. If the heuristic classifies a symbol as external but it's actually defined in a file that SwiftFileDiscovery missed (e.g., a file in a non-standard location), the merged index fails lint.

**Why it happens:**
The heuristic is correct for the single-repo case but doesn't account for multi-repo scenarios. There's no mode flag to suppress external symbol emission. The `isSystem` flag on `SymbolLocation` (which marks Swift stdlib / system framework occurrences) is ignored — it would be a more authoritative signal for true external symbols (`String`, `Int`) vs. project-internal symbols.

**How to avoid:**
- Use `SymbolLocation.isSystem` to classify: system symbols (stdlib, frameworks) → `external_symbols`; non-system referenced-but-undefined → log as potential discovery gap
- Add a `--no-external-symbols` flag for multi-repo mode where the consumer will resolve cross-repo references from loaded indexes
- Validate the heuristic against a multi-module SwiftPM package (where ModuleA references ModuleB — ModuleB symbols should NOT be external if both are in the same repo)

**Warning signs:**
- `scip lint` `bothLocalAndExternalSymbolError` after adding a new file to the repo
- External symbols list contains project-internal symbols after a file-move
- Multi-repo merge produces duplicate symbol warnings

**Phase to address:**
Cross-Repo phase (for the `--no-external-symbols` flag) — but the `isSystem` improvement should be done in the Metadata Enrichment phase since it's independent and improves correctness immediately.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Approximate occurrence ranges from display-name length | Ship without source re-lexing; passes `scip lint` | Drifts for compound names (`greet(name:)`, operators); users see imprecise highlighting | v0.1.x — already accepted; revisit in v1.0 with SwiftSyntax |
| Raw USR as symbol descriptor (no demangling) | Ship without compiler mangling library dependency | Symbol names are opaque (`_$s5Hello...`); poor UX in breadcrumbs/hover vs. scip-typescript | v0.1.x–v0.2.x; deferred to v1.0+ — needs compiler library or custom demangler |
| Empty `version` field in symbol package format | Simplifies formatter; no version-tracking needed | Multi-repo symbol collision when module names match across packages | v0.1.x single-repo only; **must fix before multi-repo mode** |
| Referenced-but-undefined heuristic for `external_symbols` | No need to parse `isSystem` flag; passes `scip lint` | Misclassifies system vs. project symbols; breaks multi-repo merge | v0.1.x — replace with `isSystem`-based classification in enrichment phase |
| `xcodebuild` without `-destination` | Avoids provisioning failures for mixed iOS/macOS projects | iOS-only targets may not fully index; no fixture proves iOS works | v0.1.x — revisit per-project; may need `--destination` flag |
| In-memory accumulation of all documents | Simple; no streaming serialization | Memory pressure on very large codebases (100k+ files) | v0.1.x–v0.2.x; revisit only if measured as a bottleneck |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| IndexStoreDB lifecycle | Caching `IndexStoreDB` instance across runs with a stale store path | Open fresh with `waitUntilDoneInitializing: true`; use `dateOfLatestUnitFor(filePath:)` for staleness checks |
| IndexStoreDB `listenToUnitEvents` | Setting to `false` for "performance" and forgetting to call `pollForUnitChangesAndWait()` | Keep default `true`; only set `false` in controlled test scenarios with explicit polling |
| `xcrun --find swift` resolution | Using plain `PATH` lookup for `swift` (resolves to `/usr/bin/swift` trampoline) | Must use `xcrun --find swift` — the trampoline doesn't point to the real toolchain root |
| SwiftPM `--scratch-path` reuse | Assuming incremental builds always produce complete index stores | Validate build exit code 0 before reading index store; partial builds produce incomplete stores |
| SCIP protobuf serialization | Building entire `Scip_Index` in memory then serializing | Acceptable for typical repos; use streaming only if measured memory issue at 100k+ files |
| `scip lint` as validation gate | Treating "passes lint" as "correct index" | Lint checks structural validity (symbol refs resolve, no duplicates), not semantic correctness (relationships accurate, ranges exact) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full rebuild every invocation | Build time dominates; 10-30s for fixture, minutes for large repos | Persistent scratch path for incremental builds; "index-only" mode that skips build | >1k source files |
| In-memory occurrence accumulation | High memory usage; potential OOM | Streaming protobuf serialization (write documents as completed) | 100k+ files with dense symbol tables |
| `symbolOccurrences(inFilePath:)` loads all occurrences per file | Large files with many occurrences cause memory spikes | Process in batches via `forEachSymbolOccurrence` with early termination | Files with 10k+ occurrences (rare but possible in generated code) |
| Rebuilding IndexStoreDB database from scratch each run | Database init is O(store size); repeated across runs is wasteful | Cache database path alongside store path; only rebuild when store changes | Any repo where you run repeatedly during development |

## "Looks Done But Isn't" Checklist

- [ ] **Relationships:** Often missing — verify by checking `SymbolInformation.relationships` is non-empty for types with inheritance/conformance
- [ ] **`enclosing_symbol` for locals:** Often missing — verify local symbols have `enclosing_symbol` set (currently never populated)
- [ ] **`isSystem` classification:** Often missing — verify `external_symbols` contains only stdlib/system framework symbols, not project-internal ones
- [ ] **`Test` and `Generated` roles:** Often missing — verify test symbols (`@Test`, `XCTestCase`) have `SymbolRole.Test` set; generated code has `Generated` set
- [ ] **Xcode build path end-to-end:** Often only arg-tested — verify a real Xcode project builds and indexes via integration test (not just argument assertions)
- [ ] **Incremental cache correctness:** Often looks fast but serves stale data — verify cache invalidation on file rename, file delete, toolchain change
- [ ] **Multi-repo symbol uniqueness:** Often passes single-repo lint but fails merged lint — verify merged index passes `scip lint` with no duplicate warnings
- [ ] **Homebrew binary on clean machine:** Often works on dev machine (has Xcode) but fails on fresh install — verify on a machine with only CommandLineTools

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Relationships dropped (Pitfall 1) | MEDIUM | Add relation-reading pass to `makeDocument`; map to `Scip_Relationship`; re-run `scip lint` |
| Relationship booleans wrong (Pitfall 2) | LOW | Fix mapping table in pure function; re-index; no data migration needed |
| Stale incremental cache (Pitfall 3) | MEDIUM | Discard all cache entries; rebuild from scratch; add correct staleness checks going forward |
| Multi-repo symbol collision (Pitfall 4) | HIGH | Requires symbol format change (add version field) + full re-index of all repos; breaks existing index compatibility |
| Homebrew dylib not found (Pitfall 5) | LOW | Add runtime check + clear error message; document Xcode requirement; no binary change needed |
| External symbols misclassified (Pitfall 6) | LOW | Switch heuristic to `isSystem`-based; add `--no-external-symbols` flag; re-index |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Relationships dropped (1) | Metadata Enrichment | Index a file with `class B: A {}`; confirm `B` has Relationship to `A` in `.scip` output |
| Relationship boolean semantics (2) | Metadata Enrichment | Validate mapping table against scip.proto TypeScript example; run `scip lint` on enriched index |
| Stale incremental cache (3) | Incremental Indexing | Integration test: index → modify source → re-index → verify changed symbols updated, unchanged symbols preserved |
| Multi-repo symbol collision (4) | Cross-Repo Linking | Index two repos with same-named modules; merge; run `scip lint` on combined index; verify no duplicates |
| Homebrew dylib resolution (5) | Homebrew Formula | Install formula on machine with only CommandLineTools; verify clear error message; install Xcode; verify tool works |
| External symbols misclassified (6) | Metadata Enrichment (isSystem) + Cross-Repo (flag) | Index multi-module package; verify cross-module refs are not in `external_symbols`; verify stdlib types ARE external |
| USR instability across toolchains (see below) | Incremental Indexing (cache key design) | Index same repo with two Swift versions; diff USRs; document cache invalidation policy |

## USR Instability — Cross-Cutting Concern

**What goes wrong:** Swift USRs are compiler-mangled and NOT guaranteed stable across Swift versions. This is a cross-cutting concern affecting three v0.2.0 features:

| Feature | Impact | Mitigation |
|---------|--------|------------|
| Incremental indexing | Cache keys based on USR are invalidated silently on toolchain upgrade | Include `.swift-version` hash in cache key; document that upgrading Swift invalidates cache |
| Cross-repo linking | Same logical symbol has different USR across toolchain versions | Require all repos indexed with same toolchain version; validate before merge |
| Symbol identity persistence | `.scip` indexes from different Swift versions can't reference each other's symbols | Document that `.scip` files are toolchain-version-bound; no workaround without demangling |

**Warning signs:** Integration test USR assertions break after Swift upgrade; cross-repo "go to definition" fails after toolchain change.

**Phase to address:** Incremental Indexing phase (cache key design) — the mitigation is the same regardless of feature.

## Sources

- `scip.proto` canonical: https://github.com/scip-code/scip/blob/main/scip.proto (Relationship, SymbolRole, SymbolInformation, Occurrence, external_symbols semantics)
- `scip lint` Go source: https://github.com/sourcegraph/scip/blob/main/cmd/scip/lint.go (validation rules: missingRelationshipFlagError, missingSymbolInRelationshipError, bothLocalAndExternalSymbolError, nonCanonicalSymbolError)
- SCIP spec docs: https://github.com/scip-code/scip/blob/main/docs/scip.md (Relationship field semantics, external_symbols usage guidance)
- IndexStoreDB `SymbolOccurrence.swift`: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/SymbolOccurrence.swift (relations array, SymbolRelation struct)
- IndexStoreDB `SymbolRole.swift`: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/SymbolRole.swift (full role bitset, relation roles)
- IndexStoreDB `SymbolProperty.swift`: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/SymbolProperty.swift (properties vs roles, access control bitmask)
- IndexStoreDB `IndexStoreDB.swift`: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/IndexStoreDB.swift (lifecycle, pollForUnitChangesAndWait, dateOfLatestUnitFor, occurrences(relatedToUSR:))
- IndexStoreDB `IndexDelegate.swift`: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/IndexDelegate.swift (unitIsOutOfDate callback)
- IndexStoreDB `SymbolLocation.swift`: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/SymbolLocation.swift (isSystem field)
- Project codebase: `SCIPIndexBuilder.swift`, `SymbolRoleMapping.swift`, `SCIPSymbolFormatter.swift`, `PositionMapping.swift`, `ToolchainInfo.swift`, `SwiftPMBuildRunner.swift`, `XcodebuildBuildRunner.swift`
- Project docs: `docs/research-scip-swift-limitations.md` (limitations deep-dive), `.planning/codebase/CONCERNS.md` (tech debt inventory), `docs/project-roadmap.md` (v0.2.0 scope)

---
*Pitfalls research for: Compiler-index-to-SCIP protobuf conversion (scip-swift v0.2.0)*
*Researched: 2026-08-11*
