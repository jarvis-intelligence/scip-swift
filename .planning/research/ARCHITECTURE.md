# Architecture Research

**Domain:** SCIP indexer CLI for Swift (compiler-index → protobuf conversion pipeline)
**Researched:** 2026-08-11
**Confidence:** HIGH

## Current Architecture Baseline

Before designing the v0.2.0 additions, we must anchor on the existing five-stage pipeline.
Every new feature either inserts a new stage or enriches an existing one — none replace the core.

### Existing System (v0.1.2)

```
┌──────────────────────────────────────────────────────────────────────┐
│                         CLI Layer                                      │
│   ScipSwiftCommand (@main) → IndexCommand (default subcommand)        │
├──────────────────────────────────────────────────────────────────────┤
│                      Build Orchestration                               │
│   BuildBackendDetector ──→ SwiftPMBuildRunner / XcodebuildBuildRunner │
│   (both conform to BuildRunner, both via SubprocessRunner)            │
│   Output: IndexStoreBuildResult { indexStorePath }                    │
├──────────────────────────────────────────────────────────────────────┤
│                      Index Access                                      │
│   IndexStoreLoader.open() → IndexStoreDB                              │
│   SwiftFileDiscovery.swiftFiles(underRepoPath:) → [String]            │
├──────────────────────────────────────────────────────────────────────┤
│                      SCIP Mapping (the core)                           │
│   SCIPIndexBuilder.build()                                            │
│     └─ makeDocument() per file                                        │
│          └─ 4 pure-function mappers:                                  │
│             SCIPSymbolFormatter  · SymbolKindMapping                  │
│             SymbolRoleMapping    · PositionMapping                     │
├──────────────────────────────────────────────────────────────────────┤
│                      Output                                            │
│   SwiftProtobuf serializedData() → write to .scip file                │
└──────────────────────────────────────────────────────────────────────┘
```

### Current Component Boundaries

| Component | Responsibility | Key File |
|-----------|---------------|----------|
| `IndexCommand` | Pipeline coordination, temp-dir lifecycle, CLI parsing | `Commands/IndexCommand.swift` |
| `BuildBackendDetector` | Auto-detect `.swiftpm` vs `.xcodebuild` | `Build/BuildBackendDetector.swift` |
| `BuildRunner` (protocol) | Build with indexing enabled, return IndexStore path | `Build/BuildRunner.swift` implementations |
| `IndexStoreLoader` | Open IndexStoreDB via `libIndexStore.dylib` | `IndexStore/IndexStoreLoader.swift` |
| `SwiftFileDiscovery` | Walk repo for `.swift` files, skip build dirs | `IndexStore/SwiftFileDiscovery.swift` |
| `SCIPIndexBuilder` | Main loop: per-file occurrence query → SCIP messages | `SCIPMapping/SCIPIndexBuilder.swift` |
| 4 Pure Mappers | Stateless IndexStoreDB type → SCIP type conversion | `SCIPMapping/*.swift` |

### Critical Design Invariants (must be preserved)

1. **Enum-as-namespace for stateless mappers** — `enum FooMapper { static func ... }`. Signals "no instances." All new mappers follow this.
2. **Exhaustive switches** — compile-time safety if IndexStoreDB adds enum cases. All new mapping switches must be exhaustive.
3. **Single executable target** — no library product. Everything in `Sources/scip-swift/`.
4. **In-memory processing** — no persistent state between runs. This is the invariant v0.2.0 incremental indexing breaks.
5. **Generated protobuf never hand-edited** — `Generated/Scip.pb.swift` is vendored from `sourcegraph/scip`.

---

## Target Architecture (v0.2.0)

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         CLI Layer                                      │
│   ScipSwiftCommand → IndexCommand (+ new options)                     │
│   [+ optional: IndexManyCommand for multi-repo mode]                  │
├──────────────────────┬───────────────────────────────────────────────┤
│   Cache Layer (NEW)  │              Build Orchestration                 │
│   ┌───────────────┐  │   BuildBackendDetector → BuildRunner             │
│   │ CacheStore    │  │   [+ incremental: reuse prior IndexStore]       │
│   │ (file-based)  │  │                                                  │
│   └───────┬───────┘  ├─────────────────────────────────────────────────┤
│           │          │              Index Access                        │
│           ▼          │   IndexStoreLoader → IndexStoreDB               │
│   ┌───────────────┐  │   SwiftFileDiscovery [+ change detection]       │
│   │ ChangeDetector│  │                                                  │
│   │ (mtime + hash)│  ├─────────────────────────────────────────────────┤
│   └───────┬───────┘  │              SCIP Mapping (enriched)            │
│           │          │   SCIPIndexBuilder.build()                       │
│           ▼          │     └─ makeDocument() per changed file           │
│   ┌───────────────┐  │          ├─ 6 mappers (4 existing + 2 new):     │
│   │ Manifest      │  │          │   + RelationshipMapping (NEW)         │
│   │ (cache index) │  │          │   + SignatureMapping (NEW)            │
│   └───────────────┘  │          └─ SymbolRoleMapping (extended)         │
│                      ├─────────────────────────────────────────────────┤
│                      │   Output / Merge                                 │
│                      │   SwiftProtobuf → .scip                          │
│                      │   [+ multi-repo: merge multiple .scip]           │
└──────────────────────┴─────────────────────────────────────────────────┘
```

### Component Responsibilities (v0.2.0 additions)

| Component | Responsibility | Location | New? |
|-----------|---------------|----------|------|
| `CacheStore` | Persist document-level SCIP messages + file metadata between runs | `Cache/CacheStore.swift` | **NEW** |
| `ChangeDetector` | Compare file mtime/hash against cached manifest; return changed file set | `Cache/ChangeDetector.swift` | **NEW** |
| `IndexManifest` | Serializable record of indexed files, their hashes, and toolchain version | `Cache/IndexManifest.swift` | **NEW** |
| `RelationshipMapping` | Map IndexStoreDB `SymbolRelation` → SCIP `Relationship` | `SCIPMapping/RelationshipMapping.swift` | **NEW** |
| `SignatureMapping` | Reconstruct Swift signature string from Symbol kind/subKind/name | `SCIPMapping/SignatureMapping.swift` | **NEW** |
| `MultiRepoMerger` | Merge multiple `Scip_Index` outputs for cross-repo resolution | `Commands/MultiRepoMerger.swift` | **NEW** |
| `SymbolRoleMapping` | Extend to map `.declaration`→`ForwardDefinition`, `.implicit`, test/generated bits | `SCIPMapping/SymbolRoleMapping.swift` | **EXTENDED** |
| `SCIPIndexBuilder` | Integrate relationships, signatures, enclosing symbols; support incremental | `SCIPMapping/SCIPIndexBuilder.swift` | **EXTENDED** |
| `IndexCommand` | New `--cache-dir`, `--incremental` flags; new `index-many` subcommand | `Commands/IndexCommand.swift` | **EXTENDED** |

---

## Feature 1: Incremental Indexing

### What Changes in the Pipeline

The current pipeline is **stateless and full-rebuild by design** — every invocation:
1. Creates a fresh temp dir (`$TMPDIR/scip-swift-<uuid>/`)
2. Builds the entire repo from scratch
3. Opens a new IndexStoreDB at an ephemeral database path
4. Processes every `.swift` file from scratch

Incremental indexing requires **persistent state** across invocations. This is the single biggest architectural shift in v0.2.0.

### Cache Strategy: Document-Level SCIP Message Cache

**Cache what:** Per-document `Scip_Document` protobuf messages, keyed by file path + content hash.

**Why document-level (not occurrence-level):** SCIP documents are self-contained units — a `Scip_Document` holds all occurrences + defined symbols for one file. Caching at this granularity is natural because:
- The current pipeline already processes one document at a time in `makeDocument()`
- Merge is trivial: unchanged document from cache, changed document from fresh processing
- External symbols tracking remains the only cross-document concern

**Cache format:** A `.scip-cache/` directory under the repo root (or `--cache-dir`):
```
.scip-cache/
├── manifest.json          # IndexManifest: file → hash + timestamp
├── docs/                  # Cached Scip_Document protobuf binaries
│   ├── Sources_Greeter.swift.doc
│   └── Sources_Model.swift.doc
└── meta.json              # Toolchain version, scip-swift version, build tool
```

**Invalidation triggers (any of these forces full reindex):**
1. **Toolchain version change** — `.swift-version` differs from cached `meta.json`. USRs are not stable across Swift versions.
2. **scip-swift version change** — output format may have changed.
3. **Build tool change** — `swiftpm` ↔ `xcodebuild` switch invalidates module-name-embedded symbol strings.
4. **File content change** — SHA-256 of file contents differs from manifest.
5. **File deletion** — file in manifest but not on disk; cached document must be dropped.

### Data Flow: Incremental Mode

```
scip-swift <repo> --incremental
    │
    ▼
Load IndexManifest from .scip-cache/manifest.json
    │
    ├─ Toolchain/scip-swift version mismatch? ──→ FULL REINDEX (delete cache)
    │
    ▼
SwiftFileDiscovery.walk(repo) → current file set
    │
    ▼
ChangeDetector.diff(manifest, currentFiles) → (changed, unchanged, deleted)
    │
    ├─ unchanged: Load cached Scip_Document from .scip-cache/docs/<path>.doc
    ├─ changed:   Rebuild with incremental IndexStore build, reprocess via makeDocument()
    └─ deleted:   Drop from output, remove from manifest
    │
    ▼
SCIPIndexBuilder.build() merges cached + fresh documents
    │
    ▼
Write merged index + update manifest
```

### Change Detection Implementation

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│ IndexManifest│────→│ChangeDetector│────→│ ChangeSet       │
│ (from cache) │     │              │     │ changed: [Path] │
└─────────────┘     │  For each    │     │ unchanged: [P]  │
                     │  .swift file:│     │ deleted: [Path] │
┌─────────────┐     │  1. SHA-256   │     └─────────────────┘
│SwiftFileDisc│────→│  2. Compare   │
│overy (live) │     │     to manifest│
└─────────────┘     └──────────────┘
```

**Decision: SHA-256 hash, not just mtime.** Mtime can be unreliable (git checkout changes mtime but not content; `touch` changes mtime without content change). Content hashing is the source of truth. The hash is cheap relative to the build step it avoids.

### Incremental Build Orchestration

The IndexStore itself supports incremental builds — `swift build` and `xcodebuild` both cache compilation units. The key change: **reuse the scratch path / derived data path across runs** instead of creating a fresh temp dir each time.

Current (always fresh):
```
$TMPDIR/scip-swift-<uuid>/scratch  ← deleted after run
```

Incremental (persistent):
```
<repo>/.scip-cache/build-scratch/  ← reused across runs
```

`SwiftPMBuildRunner` and `XcodebuildBuildRunner` need a `scratchPathReuse: Bool` parameter. When true, the runner reuses the prior scratch path so `swift build` / `xcodebuild` only recompiles changed files.

### IndexStoreDB Integration

IndexStoreDB itself supports incremental updates via `pollForUnitChangesAndWait()` and `processUnitsForOutputPathsAndWait()`. When the IndexStore is updated (incremental build), the database can be refreshed rather than recreated. This means:
- The `databasePath` passed to `IndexStoreLoader.open()` should be persistent (under `.scip-cache/index-db/`), not ephemeral
- After an incremental build, call `pollForUnitChangesAndWait()` before querying

### New Components for Incremental

| Component | Purpose | Key API |
|-----------|---------|---------|
| `CacheStore` | Read/write cached documents + manifest | `loadDocument(path:) -> Scip_Document?`, `saveDocument(_:path:)`, `loadManifest() -> IndexManifest?`, `saveManifest(_:)` |
| `IndexManifest` | Codable struct tracking file hashes + versions | `struct IndexManifest: Codable { var files: [String: FileEntry], var toolchainVersion: String, var converterVersion: String }` |
| `ChangeDetector` | Diff manifest vs filesystem | `detect(manifest:currentFiles:) -> ChangeSet` |
| `ChangeSet` | Result of diff | `struct ChangeSet { changed: Set<String>, unchanged: Set<String>, deleted: Set<String> }` |

### Impact on SCIPIndexBuilder

`build()` currently returns a fresh `Scip_Index` every time. For incremental, it needs:
- Accept pre-built documents from cache (skip `makeDocument()` for unchanged files)
- Still run the `external_symbols` computation across all documents (cached + fresh), since a change in one file can affect which symbols are external

```swift
// Conceptual signature change:
func build(changedDocuments: [Scip_Document], cachedDocuments: [Scip_Document]) throws -> Scip_Index
// OR: keep build() for full mode, add buildIncremental() for cached mode
```

### Anti-Pattern: Cache the Entire Index

**What people do:** Cache the entire `Scip_Index` protobuf and return it on cache hit.
**Why it's wrong:** A single file change requires updating occurrences, external symbols, and relationships across the whole index. Cache invalidation at the index level is all-or-nothing — no benefit over full reindex.
**Do this instead:** Cache per-document. Only recompute changed documents + global external_symbols set.

---

## Feature 2: Multi-Repo Indexing

### SCIP Spec Support for Cross-Repo

The SCIP proto is explicitly designed for multi-repo scenarios. From `scip.proto`:

```proto
message Index {
  repeated SymbolInformation external_symbols = 3;
  // "Symbols that are referenced from this index but are defined in
  // an external package (a separate Index message). Leave this field
  // empty if you assume the external package will get indexed separately."
}
```

And the `Relationship` message:
```proto
message Relationship {
  string symbol = 1;
  bool is_reference = 2;
  bool is_implementation = 3;
  bool is_type_definition = 4;
  bool is_definition = 5;
}
```

**Key insight:** SCIP does NOT define a programmatic merge operation in-proto. Merging multiple `.scip` files is a **consumer-side concern** (Sourcegraph resolves cross-repo references at query time by correlating `external_symbols` across indexes). scip-swift's job is to produce correct individual indexes with proper `external_symbols` — the multi-repo "linking" happens upstream.

### Recommended Approach: Index-Each + Merge (Optional)

Two modes:

**Mode A — Index-Each (default, no merge):**
```
scip-swift index-many repoA/ repoB/ repoC/
    │
    ├─ repoA/ → repoA/index.scip
    ├─ repoB/ → repoB/index.scip
    └─ repoC/ → repoC/index.scip
```
Each repo is indexed independently. Each gets its own `external_symbols` for symbols it references but doesn't define. The consumer (Sourcegraph) handles cross-repo linking. This is the simplest and most correct approach.

**Mode B — Index + Merge (optional, `--merge-output`):**
```
scip-swift index-many repoA/ repoB/ --merge-output combined.scip
    │
    ├─ Index each repo independently
    ├─ Merge into single Scip_Index:
    │    ├─ Concatenate documents (adjust relative paths)
    │    ├─ Deduplicate symbols (same USR across repos)
    │    └─ Recompute external_symbols (drop symbols now defined in merged set)
    └─ Write combined.scip
```

### New CLI Surface

```
# New subcommand
scip-swift index-many <repoPaths...> [--merge-output <path>] [--output-dir <dir>]

# Or extend existing command (less clean — IndexCommand takes single repoPath)
# RECOMMENDED: New subcommand for clarity
```

**Rationale for new subcommand:** `IndexCommand` is designed around a single `repoPath` positional argument and creates one temp directory. A multi-repo command has fundamentally different argument structure and lifecycle. Adding `@Argument(parseAllUnrecognized:)` or converting `repoPath` to a variadic would break the existing `scip-swift <repo>` bare invocation.

### MultiRepoMerger Component

```
┌──────────────────────────────────────────────┐
│            MultiRepoMerger                    │
├──────────────────────────────────────────────┤
│ Input: [Scip_Index] (one per repo)           │
│                                               │
│ 1. Merge documents:                           │
│    - Prefix relative_path with repo name      │
│    - E.g. "Greeter.swift" → "repoA/Greeter.swift"│
│    - Or keep separate if project_roots differ │
│                                               │
│ 2. Merge symbols:                             │
│    - Same SCIP symbol string across indexes?  │
│      Keep one (symbols are globally unique)   │
│    - Different display names for same symbol? │
│      Prefer the definition site's name        │
│                                               │
│ 3. Recompute external_symbols:                │
│    - Remove any external symbol now defined   │
│      in the merged document set               │
│    - This is the cross-repo "linking" step    │
│                                               │
│ 4. Metadata:                                  │
│    - Set project_root to common ancestor      │
│    - Or use the first repo's root with a note │
│                                               │
│ Output: Scip_Index                            │
└──────────────────────────────────────────────┘
```

### Challenge: Symbol Consistency Across Repos

Symbols are currently formatted as:
```
scip-swift <buildTool> <moduleName> <version> <usr>.
```

For cross-repo resolution to work, the **same symbol** referenced from different repos must produce the **same SCIP symbol string**. This is currently guaranteed for global symbols because:
- `scheme` is always `scip-swift`
- `packageManager` is `swift` or `xcodebuild` — same for all repos
- `moduleName` comes from the compiler's IndexStore — same module name regardless of which repo references it
- `usr` is compiler-guaranteed unique and stable within a toolchain version

**Risk:** If repoA imports repoB as a SwiftPM dependency, the module name for repoB's symbols will be repoB's package name (e.g., `MyLibrary`). The USR will be the same. So symbol strings will match. **This works.**

**Limitation:** If repos are not in a dependency relationship (e.g., two standalone apps with no shared code), there are no cross-references to resolve — multi-repo mode is a no-op for them.

### Data Flow: Multi-Repo

```
scip-swift index-many repoA/ repoB/ --merge-output combined.scip
    │
    ├─ For each repo:
    │   ├─ BuildBackendDetector.detect(repo)
    │   ├─ BuildRunner.produceIndexStore()
    │   ├─ SCIPIndexBuilder.build() → Scip_Index
    │   └─ (optionally) write per-repo .scip
    │
    ├─ MultiRepoMerger.merge([indexA, indexB])
    │   ├─ Combine documents
    │   ├─ Deduplicate symbols
    │   └─ Recompute external_symbols
    │
    └─ Write combined.scip
```

---

## Feature 3: Symbol Metadata Enrichment

This is the **highest-impact, lowest-risk** feature because the data already exists in IndexStoreDB — it's just not being read. The research report confirms: `SymbolOccurrence.relations` is fetched from the compiler and silently discarded.

### Where Enrichment Happens: `makeDocument()` in SCIPIndexBuilder

All three enrichment sub-features modify the same method. Here's the current code structure and where each addition slots in:

```swift
// SCIPIndexBuilder.swift — current makeDocument() (simplified)
for occurrence in occurrences.sorted() {
    // ── EXISTING: symbol string ──
    let symbolString = SCIPSymbolFormatter.globalSymbolString(...)

    // ── EXISTING: occurrence ──
    var scipOccurrence = Scip_Occurrence()
    scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles)
    // ...

    // ── NEW 1: Relationships ──
    // occurrence.relations is currently IGNORED
    // ADD: RelationshipMapping.scipRelationships(for: occurrence.relations)
    //      → [Scip_Relationship] attached to symbolInformation

    // ── EXISTING: symbol information ──
    var symbolInformation = Scip_SymbolInformation()
    symbolInformation.kind = SymbolKindMapping.scipKind(for: symbol)

    // ── NEW 2: Signature documentation ──
    // ADD: symbolInformation.signatureDocumentation = SignatureMapping.signature(for: symbol)
    //      → Scip_Signature { language: "swift", text: "func greet(name: String) -> String" }

    // ── NEW 3: Enclosing symbol ──
    // ADD: symbolInformation.enclosingSymbol = findEnclosing(from: occurrence.relations, .childOf)

    // ── EXISTING: role tracking ──
    if occurrence.roles.contains(.definition) {
        definedSymbols[symbolString] = symbolInformation
    }
}
```

### Sub-Feature 3a: Relationship Mapping (HIGH priority)

**New mapper: `RelationshipMapping`**

The IndexStoreDB `SymbolRelation` carries a target symbol + role bits. SCIP's `Relationship` uses four booleans. The mapping:

| IndexStoreDB Relation Role | SCIP Relationship Field | Rationale |
|----------------------------|------------------------|-----------|
| `.baseOf` | `is_implementation = true` | "class B inherits A" → B is an implementation of A. Enables "Find implementations." |
| `.extendedBy` | `is_implementation = true` | Extension adds conformance — same "find implementations" semantic |
| `.overrideOf` | `is_reference = true` | Override should be grouped with base for "Find references" |
| `.specializationOf` | `is_reference = true` | Generic specialization grouped with generic origin |
| `.childOf` | → `enclosing_symbol` (not Relationship) | Parent/child is structural containment, not a relationship |

```swift
// Sources/scip-swift/SCIPMapping/RelationshipMapping.swift
enum RelationshipMapping {
    static func scipRelationships(
        for relations: [SymbolRelation],
        symbolFormatter: (Symbol) -> String
    ) -> [Scip_Relationship] {
        relations.compactMap { relation in
            // .childOf → handled by enclosing_symbol, not Relationship
            guard !relation.roles.contains(.childOf) else { return nil }

            var rel = Scip_Relationship()
            rel.symbol = symbolFormatter(relation.symbol)

            if relation.roles.contains(.baseOf) || relation.roles.contains(.extendedBy) {
                rel.isImplementation = true
            }
            if relation.roles.contains(.overrideOf) || relation.roles.contains(.specializationOf) {
                rel.isReference = true
            }

            // Only emit if at least one flag is set
            guard rel.isImplementation || rel.isReference else { return nil }
            return rel
        }
    }
}
```

**Verification needed:** Whether Apple's Swift compiler populates `.relations` for Swift code with the same depth as Clang. The API exists (confirmed in source), but Swift-specific relation population depth should be validated empirically before committing to the full mapping design.

### Sub-Feature 3b: Signature Documentation (MEDIUM priority)

**New mapper: `SignatureMapping`**

IndexStoreDB's `Symbol` carries `kind`, `subKind`, and `name` — enough to reconstruct a basic Swift signature without source parsing. IndexStoreDB does NOT provide docstrings directly; full docstring extraction would need source-comment parsing (deferred).

```swift
// Sources/scip-swift/SCIPMapping/SignatureMapping.swift
enum SignatureMapping {
    static func signature(for symbol: Symbol) -> Scip_Signature? {
        // Reconstruct from kind + name:
        // .instanceMethod "greet" → "func greet(...)"
        // .instanceProperty "name" → "var name"
        // .class "Greeter" → "class Greeter"
        // Note: parameter types and return types are NOT in IndexStoreDB Symbol
        //       — only the display name. Full signatures need source parsing (deferred).
        // For v0.2.0: emit the declaration keyword + name as a minimal signature.
        // This is better than nothing for hover tooltips.
        guard let prefix = declarationPrefix(for: symbol) else { return nil }

        var sig = Scip_Signature()
        sig.language = "swift"
        sig.text = "\(prefix) \(symbol.name)"
        return sig
    }

    private static func declarationPrefix(for symbol: Symbol) -> String? {
        switch symbol.kind {
        case .instanceMethod, .classMethod, .staticMethod: return "func"
        case .instanceProperty: return "var"
        case .classProperty, .staticProperty: return "static var"
        case .class: return "class"
        case .struct: return "struct"
        case .enum: return "enum"
        case .protocol: return "protocol"
        case .function: return "func"
        case .variable: return "var"
        // ... exhaustive
        default: return nil
        }
    }
}
```

**Limitation:** This produces a *minimal* signature (`func greet`) without parameter types or return type. Full signatures would need either source-file parsing or an extended IndexStoreDB query API. This is acceptable for v0.2.0 as an improvement over the current empty state.

### Sub-Feature 3c: Extended SymbolRole Mapping (EASY, MEDIUM priority)

`SymbolRoleMapping.scipRoles` currently maps only 4 roles. The SCIP proto has bits that are never set:

| SCIP Role Bit | Value | IndexStoreDB Source | Status |
|---------------|-------|---------------------|--------|
| `Definition` | `0x1` | `.definition` | ✓ Mapped |
| `Import` | `0x2` | — | N/A (Swift uses module imports, not symbol-level) |
| `WriteAccess` | `0x4` | `.write` | ✓ Mapped |
| `ReadAccess` | `0x8` | `.reference`, `.read` | ✓ Mapped |
| `Generated` | `0x10` | heuristic (filename in `.build/` or generated paths) | **NEW: easy** |
| `Test` | `0x20` | `SymbolProperty.unitTest` | **NEW: easy** |
| `ForwardDefinition` | `0x40` | `.declaration` | **NEW: easy** |

```swift
// Extended SymbolRoleMapping
static func scipRoles(for indexStoreRoles: SymbolRole, symbol: Symbol) -> Int32 {
    var roles: Int32 = 0
    if indexStoreRoles.contains(.definition) {
        roles |= Int32(Scip_SymbolRole.definition.rawValue)
    }
    if indexStoreRoles.contains(.declaration) {
        roles |= Int32(Scip_SymbolRole.forwardDefinition.rawValue)
    }
    if indexStoreRoles.contains(.write) {
        roles |= Int32(Scip_SymbolRole.writeAccess.rawValue)
    } else if indexStoreRoles.contains(.reference) || indexStoreRoles.contains(.read) {
        roles |= Int32(Scip_SymbolRole.readAccess.rawValue)
    }
    if symbol.properties.contains(.unitTest) {
        roles |= Int32(Scip_SymbolRole.test.rawValue)
    }
    return roles
}
```

**Note:** This changes the function signature to accept `Symbol` (for `.unitTest` property). The caller in `makeDocument()` already has `occurrence.symbol`, so this is a one-line change at the call site.

### Sub-Feature 3d: Enclosing Symbol (LOW priority, easy)

```swift
// In makeDocument(), when processing occurrence.relations:
if let childOfRelation = occurrence.relations.first(where: { $0.roles.contains(.childOf) }) {
    symbolInformation.enclosingSymbol = SCIPSymbolFormatter.globalSymbolString(
        packageManager: buildToolName,
        moduleName: occurrence.location.moduleName,
        usr: childOfRelation.symbol.usr
    )
}
```

### Sub-Feature 3e: isSystem for External Symbols (LOW priority, correctness)

Currently, `external_symbols` is computed heuristically: referenced-but-not-defined. `SymbolLocation.isSystem` provides a more authoritative signal for distinguishing Swift stdlib / system framework symbols. This is a correctness improvement, not a structural change.

```swift
// In makeDocument(), track system symbols separately:
if occurrence.location.isSystem && !occurrence.roles.contains(.definition) {
    // This is a true external symbol (Swift stdlib, system framework)
    systemSymbols[symbolString] = symbolInformation
}
```

---

## Feature 4: Homebrew Formula & Release Pipeline

### Current Release State

- No release workflow exists (only `ci.yml`)
- Binaries are cut manually from tagged commits
- Only arm64 binary published to GitHub Releases
- No universal binary support

### Recommended Release Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                   Release Workflow (NEW)                     │
│                   .github/workflows/release.yml             │
├─────────────────────────────────────────────────────────────┤
│  Trigger: git tag v*                                         │
│                                                              │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │ Build arm64     │    │ Build x86_64    │                 │
│  │ (macos-26 runner)│   │ (macos-13 runner)│                │
│  │ swift build -c  │    │ swift build -c  │                 │
│  │   release       │    │   release       │                 │
│  └────────┬────────┘    └────────┬────────┘                 │
│           └────────┬────────────┘                           │
│                    ▼                                         │
│           ┌────────────────┐                                │
│           │ lipo -create   │  (universal binary)            │
│           │ arm64 + x86_64 │                                │
│           └───────┬────────┘                                │
│                   ▼                                          │
│           ┌────────────────┐    ┌──────────────────────┐   │
│           │ GitHub Release │───→│ Homebrew Formula      │   │
│           │ (universal bin)│    │ (generated from RB)  │   │
│           └────────────────┘    └──────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Universal Binary Build

```bash
# Build both architectures
swift build -c release --arch arm64
swift build -c release --arch x86_64

# Create universal binary
lipo -create \
  .build/arm64-apple-macosx/release/scip-swift \
  .build/x86_64-apple-macosx/release/scip-swift \
  -output scip-swift

# Verify
file scip-swift
# Expected: Mach-O universal binary with 2 architectures: [x86_64:...] [arm64:...]
```

**Note:** SwiftPM supports `--arch` flag for cross-compilation. The `macos-26` runner provides arm64; x86_64 builds either need a `macos-13` (Intel) runner or cross-compilation from arm64 (which SwiftPM supports via `--arch x86_64`).

### Homebrew Formula

```ruby
# Formula/scip-swift.rb
class ScipSwift < Formula
  desc "Converts a Swift repo's IndexStoreDB into a SCIP protobuf index"
  homepage "https://github.com/phuongddx/scip-swift"
  url "https://github.com/phuongddx/scip-swift/releases/download/v0.2.0/scip-swift-universal.tar.gz"
  sha256 "<computed-sha256>"
  version "0.2.0"

  # macOS-only — depends on Xcode toolchain being present
  depends_on :macos
  depends_on :xcode

  def install
    bin.install "scip-swift"
  end

  test do
    assert_match "scip-swift", shell_output("#{bin}/scip-swift --version")
  end
end
```

**Tap setup:**
1. Create `homebrew-tap` repo (`phuongddx/homebrew-tap`)
2. Place formula in `Formula/scip-swift.rb`
3. Users install via: `brew tap phuongddx/tap && brew install scip-swift`
4. Release workflow auto-updates formula SHA + URL on tag push

### Formula Automation

The release workflow should:
1. Build universal binary
2. Create tarball
3. Upload to GitHub Release
4. Update `homebrew-tap` repo's formula with new URL + SHA256
5. Commit to tap repo via GitHub Actions bot

**GitHub Action for formula update:** Use `mislav/bump-homebrew-formula-action` or equivalent. The formula references the release tarball URL, so SHA256 must be computed after upload.

---

## Suggested Build Order (Phase Dependencies)

### Dependency Graph

```
Phase 1: SymbolRole Extension (3c)
    │  No dependencies. Pure-function change to existing mapper.
    │  ~1-2 hours. Immediate value, zero risk.
    │
    ├──→ Phase 2: Relationship Mapping (3a)
    │       Depends on: SymbolRole extension patterns (Phase 1)
    │       Needs: empirical validation that Swift compiler populates .relations
    │       ~4-8 hours. HIGH value (enables Find Implementations).
    │
    ├──→ Phase 3: Signature + Enclosing (3b, 3d, 3e)
    │       Depends on: nothing (independent of relationships)
    │       Can run in parallel with Phase 2
    │       ~4-6 hours. MEDIUM value (hover tooltips, correctness).
    │
Phase 4: Homebrew + Release Pipeline
    │  Depends on: nothing (independent of mapping changes)
    │  Can run in parallel with Phases 1-3
    │  ~4-6 hours. Enables distribution.
    │
Phase 5: Incremental Indexing
    │  Depends on: Phase 2-3 (mapping enrichment must be stable before caching)
    │  WHY: cached documents must include relationships/signatures. If you
    │  cache documents from Phase 1 and then add relationships in Phase 2,
    │  all caches are invalidated anyway. Build enrichment first.
    │  ~12-20 hours. Largest scope.
    │
Phase 6: Multi-Repo Indexing
    │  Depends on: Phase 5 (incremental caching benefits multi-repo builds)
    │  Depends on: Phase 2 (relationships needed for cross-repo linking to work)
    │  ~8-12 hours. New CLI subcommand + merger.
```

### Phase Ordering Rationale

1. **SymbolRole extension first** — zero-risk, zero-dependency, immediate value. Establishes the pattern for extending existing mappers.

2. **Relationship mapping second** — highest user-impact feature. Must validate empirically that the Swift compiler populates `.relations` before building. This is the riskiest item to research (see PITFALLS).

3. **Signatures/enclosing in parallel** — independent of relationships. Can be developed alongside Phase 2. Low risk, medium value.

4. **Homebrew in parallel** — completely independent of mapping changes. Pure infrastructure. Ship as soon as ready.

5. **Incremental indexing fifth** — MUST come after mapping enrichment is stable. Otherwise cached documents are immediately invalidated by the next mapping improvement. Also the largest architectural change (breaks the stateless invariant).

6. **Multi-repo last** — depends on both relationships (for cross-repo linking value) and incremental (for practical multi-repo builds). Highest complexity, lowest marginal value (SCIP spec already handles cross-repo at consumer level).

---

## Anti-Patterns

### Anti-Pattern 1: Cache at IndexStore Level

**What people do:** Cache the raw IndexStoreDB database and reuse it across runs.
**Why it's wrong:** IndexStoreDB is a secondary index over the compiler's `.indexstore` files. Caching the database doesn't help — you still need to rebuild the `.indexstore` via `swift build`. The bottleneck is the build, not the database open.
**Do this instead:** Cache at the document level (`Scip_Document` protobuf). This skips both the build AND the mapping for unchanged files.

### Anti-Pattern 2: Merge Indexes by Concatenation

**What people do:** For multi-repo, concatenate all `documents` and `external_symbols` from multiple `Scip_Index` messages.
**Why it's wrong:** Symbol collisions (same USR defined in two repos) create duplicate `SymbolInformation` entries. External symbols that are now defined in the merged set must be removed. Document relative paths collide if two repos have `Sources/Main.swift`.
**Do this instead:** Use `MultiRepoMerger` that deduplicates by symbol string, recomputes external_symbols against the merged definition set, and prefixes document paths with repo name.

### Anti-Pattern 3: Parse Source Files for Signatures

**What people do:** To get `func greet(name: String) -> String`, open the `.swift` file and parse the function declaration.
**Why it's wrong:** scip-swift's architectural decision is "compiler-as-index-source" — no custom parsing. Adding a Swift parser is a massive scope expansion, fragile against language evolution, and redundant with IndexStoreDB data.
**Do this instead:** Reconstruct minimal signatures from IndexStoreDB `Symbol.kind` + `Symbol.name`. Accept the limitation that full type signatures need source parsing (defer to v1.0+ with SwiftSyntax).

### Anti-Pattern 4: Persistent IndexStoreDB Connection Across CLI Invocations

**What people do:** Run scip-swift as a daemon with a persistent IndexStoreDB connection for incremental updates.
**Why it's wrong:** scip-swift is a CLI tool. A daemon mode is a fundamentally different product. The temp-directory lifecycle, error handling, and process model are all designed for one-shot execution.
**Do this instead:** Cache on disk (manifest + documents). Open IndexStoreDB fresh each run with a persistent database path (under `.scip-cache/`). IndexStoreDB's own initialization is fast (~seconds); the bottleneck is the build, not the DB open.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| `scip` CLI (`scip lint`) | Produce standard `.scip` protobuf | Must continue passing after all enrichment changes |
| Sourcegraph | Upload `.scip` via SCIP API | Cross-repo resolution handled by Sourcegraph, not scip-swift |
| Homebrew | Formula in `homebrew-tap` repo | Auto-update on release tag; universal binary |
| GitHub Releases | Attach universal binary tarball | Release workflow triggered by `v*` tags |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Cache Layer ↔ SCIP Mapping | CacheStore provides `Scip_Document`; builder merges | Cache must not leak IndexStoreDB types — documents are pure protobuf |
| Build Runner ↔ Cache Layer | Runner reuses scratch path when incremental | Runner needs `scratchPathReuse` flag; doesn't know about cache |
| RelationshipMapping ↔ SCIPSymbolFormatter | Relationship targets need symbol string formatting | Reuse `SCIPSymbolFormatter.globalSymbolString` for relation target USRs |
| MultiRepoMerger ↔ Scip_Index | Merger operates on pure protobuf, no IndexStoreDB | Keeps merger testable without compiler dependencies |

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| <100 files | Current pipeline is fine. No caching needed. Build dominates time. |
| 100-1000 files | Incremental caching starts to matter. Cache hit on unchanged files saves minutes. |
| 1000-10000 files | Incremental is essential. Consider parallel document processing (per-file). Memory: large indexes need streaming serialization (deferred). |
| 10000+ files | Multi-repo mode for monorepo splitting. Streaming protobuf output. Parallel mapping (Swift `async let` per file). Currently out of scope for v0.2.0. |

### Scaling Priorities

1. **First bottleneck: Build time.** A full `swift build` on a large repo can take 10+ minutes. Incremental IndexStore builds (reusing scratch path) address this. scip-swift can't control Swift compilation speed, only avoid re-triggering it.

2. **Second bottleneck: Memory for large indexes.** The entire `Scip_Index` is built in memory. For 10k+ files, this could be gigabytes. Streaming serialization (writing documents one at a time) is the fix — deferred to v1.0+ per the roadmap.

3. **Third bottleneck: Mapping CPU.** Currently negligible (build dominates). Parallel processing would help for very large repos but is premature for v0.2.0.

---

## Sources

- IndexStoreDB source (compiled-against checkout): `SymbolOccurrence.swift`, `SymbolRole.swift`, `SymbolProperty.swift`, `Symbol.swift`, `SymbolLocation.swift`, `IndexStoreDB.swift` — fetched from `github.com/swiftlang/indexstore-db` main branch. **Confidence: HIGH** (primary source, verified against actual API)
- Canonical SCIP proto: `github.com/sourcegraph/scip/blob/main/scip.proto` — fetched raw. **Confidence: HIGH** (canonical spec)
- scip-typescript README: `github.com/sourcegraph/scip-typescript` — confirms `--no-global-caches` in-memory caching approach and OOM mitigation patterns. **Confidence: HIGH**
- scip-swift codebase: all 5 mappers, builder, command, build detectors, CI config. **Confidence: HIGH** (ground truth)

---
*Architecture research for: scip-swift v0.2.0*
*Researched: 2026-08-11*
