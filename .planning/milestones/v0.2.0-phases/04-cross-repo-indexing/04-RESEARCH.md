# Phase 4: Cross-Repo Indexing - Research

**Researched:** 2026-08-12
**Domain:** Multi-repo SCIP index generation + protobuf merging + symbol version disambiguation
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CROSS-01 | Add `index-many` subcommand accepting multiple repo paths | ArgumentParser variadic `@Argument([String])` pattern; new `IndexManyCommand` registered alongside `IndexCommand` in `ScipSwiftCommand.subcommands` |
| CROSS-02 | Index each repo independently producing separate `.scip` files | Extract core build+index logic from `IndexCommand.run()` into a reusable function callable in a loop; each repo gets its own temp directory + output path |
| CROSS-03 | Populate the `version` field in SCIP symbol strings to disambiguate same-named modules across repos | Add `version` parameter to `SCIPSymbolFormatter.globalSymbolString()`; replace hardcoded `escapeSpaceField("")` with `escapeSpaceField(version)` |
| CROSS-04 | Optionally merge multiple `.scip` indexes into a single output via a `--merge` flag | New `ScipIndexMerger` that concatenates `documents`, deduplicates `externalSymbols`, and recomputes `metadata`; must handle lint's `duplicateSymbolInfoWarning` and `bothLocalAndExternalSymbolError` rules |
| CROSS-05 | Resolve cross-repo references using SCIP `external_symbols` mechanism | In merge mode, strip external symbols that are defined in any other index; the remaining occurrences resolve via loaded indexes per SCIP spec guidance |
| TEST-05 | Add integration test for multi-repo merge | Two-fixture build → merge → `scip lint` validation pattern following existing `IntegrationTests.swift` no-mocks convention |
</phase_requirements>

## Summary

Phase 4 adds multi-repo indexing to scip-swift. The work is architecturally additive — no existing pipeline stages change behavior; new components wrap the existing build→index→serialize flow. The three new capabilities are: (1) a CLI `index-many` subcommand that indexes N repos independently, (2) a `--merge` flag that combines multiple `.scip` protobufs into one, and (3) populating the `version` field in SCIP symbol strings to prevent same-module-name collisions across repos.

The existing codebase is well-structured for this addition. The `SCIPSymbolFormatter.globalSymbolString()` already has a `version` parameter slot — it's hardcoded to `escapeSpaceField("")` [VERIFIED: Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift:24-29]. The `Scip_Index` protobuf has three top-level fields (`metadata`, `documents[]`, `externalSymbols[]`) that are all plain `var` arrays — no immutable internals, so merging is straightforward concatenation with deduplication [VERIFIED: Sources/scip-swift/Generated/Scip.pb.swift:1096-1120]. The `IndexCommand.run()` body is self-contained (lines 28-73) and can be refactored into a reusable function [VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:28-73].

The hardest part is the merge correctness rules enforced by `scip lint`. The linter checks: (a) no duplicate `SymbolInformation` for the same symbol string in `external_symbols` (`duplicateSymbolInfoWarning`), (b) a symbol cannot appear in both `external_symbols` and any document's `symbols` (`bothLocalAndExternalSymbolError`), and (c) every `Occurrence.symbol` must have a matching `SymbolInformation` somewhere in the index (`missingSymbolForOccurrenceError`) [VERIFIED: scip lint source, github.com/sourcegraph/scip/blob/main/cmd/scip/lint.go, fetched live 2026-08-12]. These rules directly constrain the merge algorithm: when merging indexes, external symbols from RepoA that are now defined in RepoB's documents must be stripped from the merged `externalSymbols` list.

**Primary recommendation:** Implement in three waves — (1) CROSS-03 version field population (foundational, touches existing formatter), (2) CROSS-01/CROSS-02 `index-many` subcommand with logic extracted from `IndexCommand`, (3) CROSS-04/CROSS-05 `--merge` with `ScipIndexMerger` + external symbol resolution, then TEST-05 integration test.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Multi-repo CLI dispatch | CLI (ArgumentParser) | — | New subcommand follows existing `IndexCommand` pattern; argument parsing owns dispatch |
| Per-repo indexing loop | Build/Orchestration | — | Reuse existing build→IndexStore→SCIP pipeline per repo; no IndexStoreDB change |
| Symbol version disambiguation | SCIP Mapping | — | `SCIPSymbolFormatter` is the sole owner of symbol string format; version field lives here |
| `.scip` protobuf merge | SCIP Mapping (new `ScipIndexMerger`) | — | Pure protobuf manipulation; no IndexStoreDB dependency; operates on serialized `Scip_Index` messages |
| External symbol resolution | SCIP Mapping (`ScipIndexMerger`) | — | Deduplication and cross-repo reference resolution happen at merge time using in-memory symbol sets |
| Merge validation | CLI / Integration Test | — | `scip lint` is the external correctness gate; test invokes it as subprocess |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| swift-argument-parser | 1.8.2 (pinned) | CLI subcommand registration + variadic `@Argument` | Already in use; `ParsableCommand` subcommand pattern established [VERIFIED: Package.swift:11, Package.resolved] |
| swift-protobuf | 1.38.1 (pinned) | `.scip` file serialization/deserialization for merge | `Scip_Index(serializedData:)` parses any `.scip` file; `serializedData()` writes merged output [VERIFIED: Package.swift:10, Sources/scip-swift/Generated/Scip.pb.swift] |
| IndexStoreDB | c993f4fb (pinned) | Per-repo index store access | No API changes needed — `index-many` loops the existing build+query flow [VERIFIED: Package.resolved] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| scip CLI (external) | latest from sourcegraph/scip | `scip lint` validation on merged indexes | Integration test gate (TEST-05); not a compile-time dependency |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate `index-many` subcommand | Add `--merge`/`--multi` flags to existing `IndexCommand` | Subcommand is cleaner — `index` stays single-repo (backward compatible); `index-many` is opt-in for multi-repo. Keeps default `scip-swift <repo>` working unchanged. |
| In-process `ScipIndexMerger` | Shell out to `scip convert`/`scip merge` | No such command exists in the scip CLI [VERIFIED: web search, github.com/sourcegraph/scip]. Merge must be done in-process via SwiftProtobuf. |
| Per-repo version from `.swift-version` | Per-repo version from `Package.swift` version field | `.swift-version` is the toolchain version (already validated as cache key in Phase 3); for symbol disambiguation, a repo-level version (package name + git hash) is more appropriate. See CROSS-03 deep-dive. |

**Installation:**
```bash
# No new dependencies to install — all from existing Package.swift
swift build
```

**Version verification:** All packages are already pinned in `Package.resolved`. No version changes needed for Phase 4.

## Package Legitimacy Audit

> No new packages are installed in Phase 4. All work uses existing pinned dependencies.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| swift-argument-parser | SwiftPM | existing | existing | github.com/apple/swift-argument-parser | OK | Already in use |
| swift-protobuf | SwiftPM | existing | existing | github.com/apple/swift-protobuf | OK | Already in use |
| indexstore-db | SwiftPM | existing | existing | github.com/swiftlang/indexstore-db | OK | Already in use |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
CLI Layer
├── scip-swft index <repo>              (existing, unchanged)
│     └── IndexCommand.run()
│           ├── Build → IndexStore → SCIPIndexBuilder → .scip
│           └── (optional cache from Phase 3)
│
├── scip-swift index-many <repoA> <repoB> ...    (NEW: CROSS-01/02)
│     └── IndexManyCommand.run()
│           ├── for each repoPath:
│           │     ├── Build → IndexStore → SCIPIndexBuilder → <outputDir>/<repo>.scip
│           │     └── (reuse extracted indexOneRepo() function)
│           │
│           └── if --merge:                                    (NEW: CROSS-04/05)
│                 ├── ScipIndexMerger.merge([indexA, indexB, ...])
│                 │     ├── Concatenate documents[]
│                 │     ├── Build defined-symbol set from all documents
│                 │     ├── Deduplicate externalSymbols[]
│                 │     ├── Strip external symbols now defined in any doc
│                 │     │     (prevents bothLocalAndExternalSymbolError)
│                 │     └── Set merged metadata.projectRoot
│                 ├── Write merged.scip
│                 └── (validation via scip lint in test)
│
└── SCIPSymbolFormatter.globalSymbolString(version: "abc123")  (MODIFIED: CROSS-03)
      └── version field now populated instead of "."
```

### Recommended Project Structure
```
Sources/scip-swift/
├── Commands/
│   ├── IndexCommand.swift          # existing — extract reusable indexOneRepo()
│   └── IndexManyCommand.swift      # NEW — index-many subcommand + --merge
├── SCIPMapping/
│   ├── SCIPSymbolFormatter.swift   # MODIFIED — add version parameter
│   ├── SCIPIndexBuilder.swift      # existing — pass version through
│   └── ScipIndexMerger.swift       # NEW — protobuf merge + external symbol dedup
├── ScipSwiftCommand.swift          # MODIFIED — register IndexManyCommand
└── ... (existing dirs unchanged)
```

### Pattern 1: Variadic @Argument for Multiple Repo Paths
**What:** SwiftPM ArgumentParser collects remaining positional arguments into `[String]`
**When to use:** `index-many` subcommand accepting N repo paths
**Example:**
```swift
// Source: swift-argument-parser docs (verified pattern via web search 2026-08-12)
struct IndexManyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index-many",
        abstract: "Index multiple Swift repos independently, optionally merging results."
    )

    @Argument(help: "Paths to Swift repos to index (two or more).")
    var repoPaths: [String]

    @Flag(name: .long, help: "Merge all indexes into a single .scip output.")
    var merge: Bool = false

    @Option(name: .long, help: "Output directory for individual .scip files.")
    var outputDir: String?

    @Option(name: .long, help: "Output path for merged .scip (requires --merge).")
    var mergedOutput: String?

    func run() throws {
        guard repoPaths.count >= 2 else {
            throw ValidationError("index-many requires at least two repo paths.")
        }
        // ...
    }
}
```

### Pattern 2: Extract Reusable Index Function from IndexCommand
**What:** The body of `IndexCommand.run()` (lines 28-73) is a self-contained pipeline that can be extracted
**When to use:** `IndexManyCommand` needs to call the same pipeline per repo
**Example:**
```swift
// Extracted from IndexCommand.run() — same logic, parameterized
// [VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:28-73 — current run() body]
static func indexOneRepo(
    repoPath: String,
    output: String?,
    buildTool: BuildTool?,
    configuration: BuildConfiguration,
    cacheDir: String?,
    indexOnly: Bool
) throws -> Scip_Index {
    let resolvedRepoPath = URL(fileURLWithPath: repoPath).standardizedFileURL.path
    let tool = try buildTool ?? BuildBackendDetector.detect(repoPath: resolvedRepoPath)
    // ... (existing build + cache + SCIPIndexBuilder logic) ...
    return index
}
```

**Key insight:** `IndexCommand.run()` would then call `indexOneRepo(...)` too, eliminating duplication. The existing `SCIPIndexBuilder` already accepts all needed parameters via its init [VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:8-26].

### Pattern 3: ScipIndexMerger — Pure Protobuf Merge
**What:** A stateless `enum` (following the project's convention for stateless logic) that merges multiple `Scip_Index` messages
**When to use:** `--merge` flag in `IndexManyCommand`
**Example:**
```swift
// Follows project convention: stateless logic as enum namespace with static functions
// [VERIFIED: Claude.md convention — "Stateless mapping logic is an enum namespace"]
enum ScipIndexMerger {
    static func merge(_ indexes: [Scip_Index], projectRoot: String) -> Scip_Index {
        var merged = Scip_Index()

        // 1. Metadata — use first index's tool info, override projectRoot
        var metadata = indexes.first?.metadata ?? Scip_Metadata()
        metadata.projectRoot = projectRoot
        merged.metadata = metadata

        // 2. Concatenate all documents (each keeps its relative path)
        for index in indexes {
            merged.documents.append(contentsOf: index.documents)
        }

        // 3. Build set of all defined symbols (from documents)
        var definedSymbols: Set<String> = []
        for doc in merged.documents {
            for sym in doc.symbols {
                definedSymbols.insert(sym.symbol)
            }
        }

        // 4. Merge external symbols: deduplicate + strip those now defined
        var seenExternal: [String: Scip_SymbolInformation] = [:]
        for index in indexes {
            for extSym in index.externalSymbols {
                if !definedSymbols.contains(extSym.symbol) && seenExternal[extSym.symbol] == nil {
                    seenExternal[extSym.symbol] = extSym
                }
            }
        }
        merged.externalSymbols = seenExternal.values.sorted { $0.symbol < $1.symbol }

        return merged
    }
}
```

### Anti-Patterns to Avoid

- **Anti-pattern: Merging document relative paths naively.** If RepoA and RepoB both have `Sources/Core/Foo.swift`, the merged index has a `duplicateDocumentWarning`. **Fix:** Prefix relative paths with repo name during merge, or require repos to have distinct directory structures. The lint rule `duplicateDocumentWarning` fires on identical `RelativePath` values [VERIFIED: scip lint source, `duplicateDocumentWarning` struct].

- **Anti-pattern: Leaving external symbols that are now locally defined.** If RepoA references `SwiftNIO` as external, and RepoB defines `SwiftNIO`, the merged index triggers `bothLocalAndExternalSymbolError`. **Fix:** Strip external symbols from the merged list when they appear in any document's `symbols` [VERIFIED: scip lint source, `bothLocalAndExternalSymbolError` struct, `addFileForSymbol` checks `st.extSyms[sym]`].

- **Anti-pattern: Hardcoding the version field to a constant.** If every repo gets `version: "1.0"`, same-module-name collision persists. **Fix:** Use a repo-specific value (package name hash, git commit, or user-supplied `--symbol-version` flag).

- **Anti-pattern: Modifying `SCIPIndexBuilder.build()` to support merge mode.** The builder operates on a single IndexStoreDB; merge is a pure protobuf operation. **Fix:** Keep `SCIPIndexBuilder` single-repo; `ScipIndexMerger` handles the multi-repo layer.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| `.scip` file parsing | Custom protobuf reader | `Scip_Index(serializedData:)` from SwiftProtobuf | Already used for serialization; deserialization is the same API, fully tested |
| Symbol string deduplication | Custom string matcher | `Set<String>` + dict lookup | Swift stdlib handles this; lint's own `symTable` uses Go maps the same way |
| `scip lint` validation | Custom validator | External `scip lint` CLI as subprocess in integration test | The linter is the authoritative correctness gate; reimplementing its rules risks drift |

**Key insight:** The merge operation is pure data manipulation on protobuf messages. No compiler interaction, no IndexStoreDB access, no file-system state. This makes it the safest component to build — it's testable without any external dependencies beyond SwiftProtobuf (already pinned).

## Common Pitfalls

### Pitfall 1: Symbol Collision from Empty Version Field
**What goes wrong:** Two repos with a module named `Core` produce identical SCIP symbol strings `scip-swift swiftpm Core . <usr>.`. When merged, `scip lint` emits `duplicateSymbolInfoWarning` for the external symbols.
**Why it happens:** The version field is hardcoded to `escapeSpaceField("")` which renders as `.` — the empty placeholder [VERIFIED: Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift:26].
**How to avoid:** Populate the version field with a repo-specific value before attempting any merge. This is why CROSS-03 is a hard dependency for CROSS-04 (documented in ROADMAP.md Phase 4 risk register).
**Warning signs:** `scip lint` output contains `found repeated SymbolInformation for external symbol` after merge.

### Pitfall 2: bothLocalAndExternalSymbolError After Merge
**What goes wrong:** RepoA references `ModuleX.Symbol` as an external symbol (undefined in RepoA). RepoB defines `ModuleX.Symbol` in a document. After merge, the symbol appears in both `externalSymbols[]` and a document's `symbols[]`, triggering `scip lint` error: `SymbolInformation for '...' is present in both external symbols and document '...'` [VERIFIED: scip lint source, `bothLocalAndExternalSymbolError` struct, `addFileForSymbol` checks `st.extSyms[sym]` before accepting into `st.localSymsMap`].
**Why it happens:** Naive merge concatenates `externalSymbols` without checking if any are now defined in the merged document set.
**How to avoid:** `ScipIndexMerger` must build a `definedSymbols: Set<String>` from all documents across all indexes, then filter external symbols to exclude any in that set.
**Warning signs:** `scip lint` error containing `present in both external symbols and document`.

### Pitfall 3: duplicateDocumentWarning on Same Relative Paths
**What goes wrong:** If RepoA and RepoB both have `Sources/Core/Types.swift`, the merged index has two documents with `relative_path: "Sources/Core/Types.swift"`. The linter emits a warning: `found multiple documents with path '...'` [VERIFIED: scip lint source, `duplicateDocumentWarning` struct and `docMap` construction].
**Why it happens:** Document relative paths are computed from each repo's root independently; identical source tree structures collide.
**How to avoid:** Prefix document relative paths with a repo identifier during merge (e.g., `RepoA/Sources/Core/Types.swift`). Note: this means the merged index's `projectRoot` is a virtual root that doesn't exist on disk — acceptable for Sourcegraph consumption but should be documented.
**Warning signs:** `scip lint` warning containing `found multiple documents with path`.

### Pitfall 4: Relationship Target Symbol Missing After Merge
**What goes wrong:** `scip lint` checks that every `Relationship.symbol` target exists in either `externalSymbols` or some document's `symbols` [VERIFIED: scip lint source, `addRelationship` function — checks `st.extSyms[rel.Symbol]` then `st.localSymsMap[rel.Symbol]`, returns `missingSymbolInRelationshipError` if neither found]. If merging strips an external symbol that was a relationship target, the lint fails.
**Why it happens:** Aggressive external-symbol stripping can remove relationship targets. If RepoA has a relationship pointing to `ModuleX.Symbol` (external), and RepoB defines `ModuleX.Symbol`, stripping it from `externalSymbols` is correct (it's now in a document). But if RepoB does NOT define it and the symbol was in RepoA's external list, stripping it breaks the relationship.
**How to avoid:** Only strip external symbols that are confirmed defined in the merged document set. Never strip external symbols merely because they appear in multiple indexes' external lists — deduplicate them, but keep at least one entry.
**Warning signs:** `scip lint` error: `symbol '...' has a relationship to '...', but couldn't find #2 in external symbols or some other document`.

### Pitfall 5: Version Field Breaks Backward Compatibility
**What goes wrong:** Existing `.scip` indexes produced with empty version (`.`) have symbol strings like `scip-swift swiftpm MiniSwiftPackage . <usr>.`. If the version field is populated, new indexes have `scip-swift swiftpm MiniSwiftPackage <version> <usr>.`. These are **different symbol strings** — cross-references between old and new indexes silently fail.
**Why it happens:** The version field is part of the symbol identity per the SCIP grammar: `<package> ::= <manager> ' ' <package-name> ' ' <version>` [VERIFIED: Protos/scip.proto:155-160].
**How to avoid:** Treat version field population as a one-way migration. All repos must be re-indexed after the change. Document this in release notes. For single-repo use (no `--merge`), the version field can default to empty (`.`) to maintain backward compatibility with existing indexes.
**Warning signs:** Cross-repo "go to definition" fails after upgrading scip-swift.

## Code Examples

### CROSS-03: Version Field Population in SCIPSymbolFormatter

```swift
// Source: Modified from Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift:23-29
// Current code (line 26): let version = escapeSpaceField("")
// Changed code:
static func globalSymbolString(
    packageManager: String,
    moduleName: String,
    version: String = "",   // NEW parameter, defaults to "" for backward compat
    usr: String
) -> String {
    let manager = escapeSpaceField(packageManager)
    let packageName = escapeSpaceField(moduleName)
    let versionField = escapeSpaceField(version)  // was: escapeSpaceField("")
    let descriptor = "\(escapeIdentifierName(usr))."
    return "\(escapeSpaceField(scheme)) \(manager) \(packageName) \(versionField) \(descriptor)"
}
```

**Propagation:** `SCIPIndexBuilder` calls `globalSymbolString` in `makeDocument()` [VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:132-136]. The builder needs a `symbolVersion: String` property added to its init, defaulting to `""` for single-repo mode. `IndexCommand` passes it through; `IndexManyCommand` supplies a per-repo value.

### CROSS-04: ScipIndexMerger Loading .scip Files

```swift
// Source: SwiftProtobuf API — Scip_Index(serializedData:) is the standard init
// [VERIFIED: Sources/scip-swift/Generated/Scip.pb.swift:1090 — Scip_Index is Sendable struct]
func loadIndex(from scipPath: String) throws -> Scip_Index {
    let data = try Data(contentsOf: URL(fileURLWithPath: scipPath))
    return try Scip_Index(serializedData: data)
}
```

### CROSS-05: External Symbol Resolution During Merge

```swift
// The scip lint rule (addFileForSymbol) checks:
//   if _, ok := st.extSyms[sym]; ok {
//       return bothLocalAndExternalSymbolError{sym, path}
//   }
// So we must ensure no external symbol is also in any document's symbols.
// [VERIFIED: scip lint source, addFileForSymbol function]

// Merge logic to prevent bothLocalAndExternalSymbolError:
static func resolveExternalSymbols(
    allDocuments: [Scip_Document],
    inputExternals: [Scip_SymbolInformation]
) -> [Scip_SymbolInformation] {
    var defined: Set<String> = []
    for doc in allDocuments {
        for sym in doc.symbols {
            defined.insert(sym.symbol)
        }
    }
    var seen: [String: Scip_SymbolInformation] = [:]
    for ext in inputExternals {
        if !defined.contains(ext.symbol) && seen[ext.symbol] == nil {
            seen[ext.symbol] = ext
        }
    }
    return seen.values.sorted { $0.symbol < $1.symbol }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Empty version field (`.`) in symbol strings | Populated version field for multi-repo disambiguation | Phase 4 (this phase) | Symbol strings change — requires full re-index of all repos for cross-repo features |
| Single-repo only (`index` subcommand) | Multi-repo `index-many` subcommand | Phase 4 (this phase) | No backward incompatibility — `index` unchanged |
| No merge capability | `--merge` flag with `ScipIndexMerger` | Phase 4 (this phase) | Purely additive; existing single-repo output unaffected |

**Deprecated/outdated:**
- Hardcoded `escapeSpaceField("")` for version field — being replaced in CROSS-03

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A repo-specific version value (e.g., package name + git hash) is the right disambiguator for the version field | Standard Stack / CROSS-03 | If the user expects a SwiftPM package version or a user-supplied `--symbol-version` flag instead, the default disambiguation strategy may not match their needs. LOW risk — the parameter is configurable. |
| A2 | Document relative paths should be prefixed with repo name during merge | Pitfalls / Pitfall 3 | If the consumer expects unprefixed paths, navigation breaks. MEDIUM risk — depends on how Sourcegraph resolves paths from merged indexes. |
| A3 | The `index-many` subcommand should produce individual `.scip` files even without `--merge` | CROSS-01/02 | If the user expects `index-many` to always merge, the UX is wrong. LOW risk — `--merge` is an explicit flag, and separate files are more flexible. |
| A4 | `scip lint` is available as a binary on the CI machine for TEST-05 | Validation Architecture | If not available, the integration test needs a Go build step to compile it. MEDIUM risk — documented as an environment dependency. |

## Open Questions (RESOLVED)

1. **What value should populate the version field by default?**
   - What we know: The field is currently empty (`.`). It must be repo-specific to prevent collisions. Options: (a) SwiftPM package name + version from `Package.swift`, (b) git commit hash, (c) user-supplied `--symbol-version` flag, (d) hash of repo URL.
   - What's unclear: Which is most natural for the scip-swift use case. scip-python uses `--project-name`/`--project-namespace` [CITED: .planning/research/STACK.md L296]. scip-typescript doesn't use the version field (relies on npm package scoping).
   - RESOLVED: Default to empty for single-repo index (backward compat); repo directory basename for index-many. Planner decision — no git hash dependency or user flag required. for single-repo `index` (backward compat); require `--symbol-version` or auto-derive from git hash for `index-many`. Let the planner decide the exact default.

2. **Should the merged index set `projectRoot` to a virtual path?**
   - What we know: `scip lint` doesn't validate that `projectRoot` exists on disk — it only uses it for metadata [VERIFIED: scip lint source — projectRoot is not checked in lint logic].
   - What's unclear: Whether Sourcegraph handles a virtual/empty projectRoot gracefully in a merged index.
   - RESOLVED: Set projectRoot to output directory path. Pragmatic default, planner can adjust. to the output directory path (where the merged `.scip` is written). This is a pragmatic default the planner can adjust.

3. **Should `index-many` support `--cache-dir` and `--index-only` per repo?**
   - What we know: Phase 3 added these flags to `IndexCommand`. The extracted `indexOneRepo()` function accepts them.
   - What's unclear: Whether per-repo cache directories are needed, or a shared cache root with repo subdirectories.
   - RESOLVED: Support --cache-dir as parent with per-repo subdirectories. Planner decision. as a parent directory, with `<cache-dir>/<repo-name>/` per repo. Planner decides.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift 6.2.4 toolchain | Build + test | ✓ | 6.2.4 | — |
| Xcode (for libIndexStore.dylib) | Indexing each repo | ✓ | Xcode 26 | — |
| `scip` CLI (`scip lint`) | TEST-05 integration test validation | Needs check | latest from sourcegraph/scip | If unavailable, test can assert structural properties (no duplicate symbols, no bothLocalAndExternal) in-process instead |

**Missing dependencies with no fallback:**
- None that block implementation. `scip lint` has a fallback for TEST-05 (in-process structural validation).

**Missing dependencies with fallback:**
- `scip` CLI: If not installed on the dev/CI machine, TEST-05 can validate merge correctness by asserting the same rules `scip lint` checks (no duplicate external symbols, no bothLocalAndExternal, all occurrence symbols have SymbolInformation) in Swift, without invoking the external binary. This is less authoritative but unblocks development.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Suite`/`@Test`/`#expect`/`#require`) — built into Swift 6.2.4 toolchain |
| Config file | None — Swift Testing requires no config file |
| Quick run command | `swift test --filter SCIPSymbolFormatter` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CROSS-03 | Version field populated in symbol string | unit | `swift test --filter "SCIPSymbolFormatter/version"` | ❌ Wave 0 (modify existing `SCIPSymbolFormatterTests.swift`) |
| CROSS-01 | `index-many` accepts multiple paths | unit | `swift test --filter IndexManyCommand` | ❌ Wave 0 |
| CROSS-02 | Each repo indexed independently | integration | `swift test --filter "IndexMany/independent indexes"` | ❌ Wave 0 |
| CROSS-04 | Merged index passes lint | integration | `swift test --filter "Merge/merged index"` | ❌ Wave 0 |
| CROSS-05 | Cross-repo external symbols resolved | integration | `swift test --filter "Merge/cross-repo reference"` | ❌ Wave 0 |
| TEST-05 | Multi-repo merge integration test | integration | `swift test --filter "MultiRepoMerge"` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `swift test --filter <SuiteName>` (narrow, < 30s for unit; 10-30s per integration test)
- **Per wave merge:** `swift test` (full suite)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `Tests/scip-swiftTests/ScipIndexMergerTests.swift` — unit tests for merge logic (dedup, external symbol stripping, document path prefixing)
- [ ] `Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift` — integration test for TEST-05 (two fixtures → merge → validate)
- [ ] `Fixtures/CrossRepoFixtureA/` — second fixture package for cross-repo testing (existing `MiniSwiftPackage` can serve as one repo; need a second with a dependency relationship or same module name)
- [ ] Modify `Tests/scip-swiftTests/SCIPSymbolFormatterTests.swift` — update existing tests for new `version` parameter (backward-compat test with default empty version + new test with non-empty version)

*Note: The existing integration test pattern in `IntegrationTests.swift` and `IncrementalIntegrationTests.swift` provides the exact template: real `swift build` against fixtures, no mocks, `defer` cleanup of temp dirs and `.build` directories [VERIFIED: Tests/scip-swiftTests/IntegrationTests.swift, Tests/scip-swiftTests/IncrementalIntegrationTests.swift].*

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No authentication in CLI tool |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | CLI runs with user's filesystem permissions — no additional access control needed |
| V5 Input Validation | yes | ArgumentParser validates repo paths; file reads use `Data(contentsOf:)` which throws on invalid paths |
| V6 Cryptography | no | No crypto operations |

### Known Threat Patterns for Swift CLI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via repo path | Tampering | ArgumentParser resolves paths; `URL(fileURLWithPath:).standardizedFileURL` normalizes |
| Malicious `.scip` file (protobuf deserialization bomb) | Denial of Service | SwiftProtobuf has built-in size limits; merge only operates on trusted local files |

## Project Constraints (from CLAUDE.md)

The following CLAUDE.md directives constrain this phase:

1. **macOS-only:** Don't try to make the build/test pipeline pass on Linux. `libIndexStore.dylib` is macOS-only.
2. **2-space indentation** throughout.
3. **Stateless mapping logic is an `enum` namespace with `static` functions** — `ScipIndexMerger` should follow this convention.
4. **Never hand-edit `Generated/Scip.pb.swift`** — it's vendored from upstream.
5. **Swift Testing (`@Suite`/`@Test`)** — not XCTest. New tests must follow this pattern.
6. **No mocks in integration tests** — `IntegrationTests.swift` shells out to real `swift build` against `Fixtures/`. `MultiRepoMergeIntegrationTests.swift` must do the same.
7. **Toolchain pinned to 6.2.4** (`.swift-version`) — don't test/build with a different toolchain.
8. **`@testable import scip_swift`** for accessing internal types in tests.
9. **Exhaustive `BuildError`** — if new error cases are needed for multi-repo failures, follow the existing exhaustive enum pattern.

## Sources

### Primary (HIGH confidence)
- `Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift` — version field hardcoded at line 26; `globalSymbolString` signature at lines 23-29
- `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` — `globalSymbolString` call sites at lines 132-136 and 162-166; external symbol computation at lines 81-92
- `Sources/scip-swift/Commands/IndexCommand.swift` — `run()` body at lines 28-73 (extraction target)
- `Sources/scip-swift/ScipSwiftCommand.swift` — subcommand registration at line 9
- `Sources/scip-swift/Generated/Scip.pb.swift` — `Scip_Index` struct at lines 1090-1120 (documents, externalSymbols as mutable arrays)
- `Protos/scip.proto` — symbol grammar at lines 155-180; `external_symbols` semantics at lines 31-36; `Metadata.project_root` at lines 47-49
- scip lint Go source (`cmd/scip/lint.go` from github.com/sourcegraph/scip) — fetched live 2026-08-12: `duplicateSymbolInfoWarning`, `bothLocalAndExternalSymbolError`, `missingSymbolForOccurrenceError`, `duplicateDocumentWarning`, `addFileForSymbol`, `addRelationship`, `addOccurrence` rules verified
- `.planning/research/STACK.md` — Section 4 (external_symbols + cross-repo linking); scip-python `--project-name` pattern
- `.planning/research/PITFALLS.md` — Pitfall 4 (symbol collision), Pitfall 6 (external symbols in merge)
- `.planning/research/SUMMARY.md` — Phase 5 multi-repo rationale, `MultiRepoMerger` component description

### Secondary (MEDIUM confidence)
- swift-argument-parser variadic `@Argument` pattern — verified via web search; standard ArgumentParser API
- SwiftProtobuf `Scip_Index(serializedData:)` — standard SwiftProtobuf API, already used for serialization in the project

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already pinned and in use; no new dependencies
- Architecture: HIGH — additive design following existing patterns; code structure verified from source
- Pitfalls: HIGH — lint rules verified from authoritative Go source; merge constraints directly traceable to lint checks
- CROSS-03 version field: HIGH — exact code location and change identified
- Merge algorithm: HIGH — lint rules constrain the algorithm precisely; all failure modes mapped

**Research date:** 2026-08-12
**Valid until:** 2026-09-12 (30 days — stable codebase, no external API changes expected)
