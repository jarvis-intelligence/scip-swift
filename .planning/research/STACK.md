# Stack Research

**Project:** scip-swift v0.2.0
**Domain:** Swift compiler-index → SCIP protobuf CLI indexer
**Researched:** 2026-08-11
**Confidence:** HIGH (grounded in the actual checked-out IndexStoreDB source + canonical scip.proto + Homebrew official docs + real homebrew-core formulae)

---

## Scope of This Document

This STACK.md covers the **four new capability areas** needed for v0.2.0, layered on top of the existing stack (Swift 6.2.4, IndexStoreDB, SwiftProtobuf, ArgumentParser — documented in `.planning/codebase/STACK.md`, unchanged):

1. Homebrew formula distribution for the pre-built macOS binary
2. IndexStoreDB relations API for symbol metadata enrichment (inheritance / conformance / override)
3. Caching / incremental indexing patterns
4. SCIP `external_symbols` + `Relationship` mechanism for cross-repo linking

The existing dependencies (`indexstore-db`, `swift-protobuf`, `swift-argument-parser`) do **not** need version changes. The v0.2.0 work is about using *more of the APIs they already expose*, not adding libraries. This is a key finding: **no new third-party dependencies are required.**

---

## 1. Homebrew Distribution

### Recommendation: Custom Tap with Pre-Built Binary Formula

**Confidence: HIGH** (verified against Homebrew official Formula Cookbook, Taps docs, Bottles docs, and real homebrew-core SwiftLint/SwiftFormat formulae)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Homebrew custom tap | current | Host `scip-swift.rb` formula | **Only viable path** for a macOS-only Swift tool. `homebrew/core` requires Linux support (all formulae must build on both macOS and Linux runners) and autobump compatibility. scip-swift cannot build on Linux (`libIndexStore.dylib` is macOS-only). |
| GitHub Releases tarball | n/a | Binary artifact source | scip-swift already ships arm64 binaries via GitHub Releases (v0.1.2). The formula downloads the release tarball, verifies sha256, and `bin.install`s the executable — no toolchain required at install time. |
| GitHub Actions release workflow | actions/checkout@v5, gh CLI | Automate formula update on tag | `gh release create` + a script that updates the sha256 in the formula file and commits to the tap repo. |

### Why NOT `homebrew/core` (build-from-source formula)

homebrew-core SwiftPM formulae (SwiftLint, SwiftFormat) build from source via `system "swift", "build", *std_swift_args` with BrewTestBot bottles. This pattern is **inapplicable** to scip-swift for two hard blockers:

1. **Linux requirement.** Every homebrew/core formula must produce a `x86_64_linux` and `arm64_linux` bottle. scip-swift has `libIndexStore.dylib` (macOS-only) as a load-bearing runtime dependency. The build cannot even compile on Linux. This is an architectural constraint documented in `Claude.md` and `.planning/PROJECT.md`.
2. **Autobump incompatibility.** homebrew/core uses automated `brew bump-formula-pr` against stable release tags. scip-swift pins `swift-tools-version: 6.2` and requires `Xcode 26` (the CI runs on `macos-26`); BrewTestBot's macOS runners may not yet have this toolchain, and the version pin is load-bearing for USR stability.

### Tap Structure

```
github.com/phuongddx/homebrew-scip-swift/
└── Formula/
    └── scip-swift.rb        # The formula
```

`brew tap phuongddx/scip-swift` clones `https://github.com/phuongddx/homebrew-scip-swift` (Homebrew auto-prepends `homebrew-`). Users then run `brew install scip-swift`.

### Formula Shape (pre-built binary download)

```ruby
class ScipSwift < Formula
  desc "SCIP indexer for Swift — converts IndexStoreDB data to scip.proto"
  homepage "https://github.com/phuongddx/scip-swift"
  url "https://github.com/phuongddx/scip-swift/releases/download/v0.2.0/scip-swift-0.2.0-arm64-macos.tar.gz"
  sha256 "<sha256-of-tarball>"
  version "0.2.0"
  license "MIT"

  depends_on macos: :sonoma  # needs libIndexStore.dylib + Apple SDKs

  def install
    bin.install "scip-swift"
  end

  test do
    assert_match "0.2.0", shell_output("#{bin}/scip-swift --version")
  end
end
```

Key details (verified from Formula Cookbook):
- `depends_on macos: :sonoma` — restricts to macOS 14+ (matches `Package.swift` `.macOS(.v14)`)
- No `bottle do` block needed — for a custom tap serving a pre-built binary, the tarball **is** the bottle. Users get the binary directly; no compilation step runs.
- `sha256` is mandatory; Homebrew refuses to install without a matching checksum.
- The `license` field (SPDX identifier) is required for the formula to pass `brew audit`.

### Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Custom tap (pre-built binary) | homebrew/core (build-from-source) | Never for scip-swift — Linux blocker is architectural |
| Custom tap (pre-built binary) | `brew install --HEAD` from source | For developers only; too slow (full Swift build) for users |
| Custom tap (pre-built binary) | GoReleaser `.rb` generation | Only if scip-swift were Go. Swift has no GoReleaser equivalent; the formula must be hand-maintained or script-updated. |
| GitHub Release binary (current) | Mint (Swift package manager) | Mint builds from source; still needs Xcode + full compile. Homebrew is the standard. |

---

## 2. IndexStoreDB Relations API (Symbol Metadata Enrichment)

### Recommendation: Use `occurrence.relations` + `occurrences(relatedToUSR:roles:)` — both already available

**Confidence: HIGH** (verified by reading the exact checked-out IndexStoreDB source at `.build/checkouts/indexstore-db/Sources/IndexStoreDB/`)

The central finding from the limitations research (`docs/research-scip-swift-limitations.md`, L1): **the compiler's relation data is fetched from IndexStoreDB and silently discarded.** The fix requires zero new dependencies — the API is fully present in the pinned `indexstore-db` revision (`c993f4fb`).

### Available API Surface (verified from source)

#### Inline relations on every `SymbolOccurrence`

```swift
// SymbolOccurrence.swift:18-34 — ALREADY POPULATED by the compiler
public struct SymbolOccurrence {
  public var symbol: Symbol
  public var location: SymbolLocation
  public var roles: SymbolRole
  public var relations: [SymbolRelation]  // ← THIS IS THE DATA
}

// SymbolOccurrence.swift:53-60
public struct SymbolRelation {
  public var symbol: Symbol    // The related symbol (has .usr, .name, .kind)
  public var roles: SymbolRole // HOW it's related (see relation roles below)
}
```

The `relations` array is populated from C: `indexstoredb_symbol_occurrence_relations()` iterates and appends each `SymbolRelation`. This is not optional data — the compiler fills it for every occurrence where a structural relationship exists.

#### Relation roles available (`SymbolRole.swift:32-41`)

```swift
// MARK: Relation roles, from indexstore
public static let childOf: SymbolRole          // enclosing scope (parent type/module)
public static let baseOf: SymbolRole           // this symbol IS a base of the related symbol
public static let overrideOf: SymbolRole       // method override: this overrides related
public static let receivedBy: SymbolRole       // parameter received by related function
public static let calledBy: SymbolRole         // call graph (has no SCIP call bit — drop)
public static let extendedBy: SymbolRole       // extension: this type extended by related
public static let accessorOf: SymbolRole       // getter/setter of related property
public static let containedBy: SymbolRole      // lexical containment
public static let ibTypeOf: SymbolRole         // IBOutlet (irrelevant for Swift CLI tools)
public static let specializationOf: SymbolRole // generic specialization
```

#### Dedicated reverse-lookup query API (`IndexStoreDB.swift:215-232`)

```swift
// For querying relationships FROM a known USR (needed for cross-repo / external symbols)
public func occurrences(relatedToUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence]

// Streaming variant
public func forEachRelatedSymbolOccurrence(
  byUSR usr: String,
  roles: SymbolRole,
  _ body: (SymbolOccurrence) -> Bool
) -> Bool
```

### Mapping to SCIP `Relationship` (verified from `Protos/scip.proto:465-516`)

SCIP's `Relationship` message has 4 boolean fields. IndexStoreDB has 10 relation roles. The mapping is approximate but well-defined:

| IndexStoreDB Relation Role | SCIP `Relationship` Field | Rationale (from proto comments) |
|----------------------------|---------------------------|---------------------------------|
| `.baseOf` / `.extendedBy` | `is_implementation = true` | "Find implementations" — protocol conformance & inheritance. The proto's own example: `Dog implements Animal`. |
| `.overrideOf` | `is_implementation = true, is_reference = true` | Override methods should group with the base for both "find refs" and "find implementations". |
| `.childOf` | `enclosing_symbol` field (not Relationship) | Sets `SymbolInformation.enclosing_symbol` (proto field 8) — places locals in hierarchy. |
| `.specializationOf` | `is_implementation = true` | Generic specializations are implementations of the generic. |
| `.calledBy` / `.receivedBy` | **Drop** | No SCIP call-hierarchy bit exists (spec limitation, documented). |
| `.accessorOf` | **Drop or `is_reference`** | Getters/setters relate to their property; low value, drop for v0.2.0. |
| `.containedBy` / `.ibTypeOf` | **Drop** | Lexical containment is redundant with `childOf`; IB is irrelevant. |

### What This Enables

With relations mapped, the emitted index gains:
- **"Find implementations"** — headline SCIP feature (class B extends A, struct S: Protocol)
- **Inheritance hierarchy navigation** — "Go to type definition" via `is_type_definition`
- **Method override resolution** — `override func` links to superclass method
- **`enclosing_symbol`** — locals appear in symbol hierarchy (currently never set)

### SymbolRole Expansion (also needed — easy, same file)

Current `SymbolRoleMapping.swift` maps only 4 roles. The following additions use roles **already in the IndexStoreDB API** and SCIP bits **already in scip.proto**:

| IndexStoreDB Role/Property | SCIP `SymbolRole` Bit | Status |
|----------------------------|----------------------|--------|
| `.declaration` | `ForwardDefinition = 0x40` | **Unmapped** — add for protocol requirements / forward decls |
| `SymbolProperty.unitTest` | `Test = 0x20` | **Never set** — `unitTests()` API exists; flip `Test` for `@Test` / `XCTestCase` symbols |
| Generated code detection | `Generated = 0x10` | **Never set** — could detect via path heuristic (`.build/` / `DerivedData/`) |

### What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| SwiftSyntax for signature parsing | Heavy dependency (compiles the Swift grammar); `Symbol.kind`/`subKind`/`name` from IndexStoreDB reconstructs a basic signature without it | `Symbol.name` + kind-based formatting (`func \(name)`, `var \(name)`, etc.) |
| A custom USR demangler | Needs the compiler mangling library (not standalone-packaged); deferred to v1.0+ per roadmap | Raw USR (correct but unreadable) — keep for v0.2.0 |
| Source comment parsing for documentation | Complex, fragile, re-lexes source files | Defer; IndexStoreDB has no docstring field |

---

## 3. Caching / Incremental Indexing

### Recommendation: Two-Layer Cache (IndexStoreDB-persistent + per-document SCIP output)

**Confidence: MEDIUM** (the IndexStoreDB APIs are HIGH-confidence from source; the cache architecture is a design recommendation based on those APIs, not a library-validated pattern)

Currently, every `scip-swift` run rebuilds the entire repo from scratch into a fresh temp directory. There are two expensive layers to cache:

### Layer 1: Persist the IndexStoreDB database (the compiler's work)

IndexStoreDB itself supports persistence. The `IndexStoreDB` initializer (`IndexStoreDB.swift:77-90`) accepts `databasePath` and `enableOutOfDateFileWatching`:

```swift
public init(
  storePath: String,          // compiler's index store output
  databasePath: String,       // ← persist this across runs
  library: IndexStoreLibrary?,
  readonly: Bool = false,
  enableOutOfDateFileWatching: Bool = false,  // ← detect stale units
  ...
)
```

Currently `IndexCommand.swift:36` writes the DB to a per-run temp directory (`<workDirectory>/index-db`). To make it persistent:

| API | Purpose | Source Location |
|-----|---------|-----------------|
| `dateOfLatestUnitFor(filePath:)` → `Date?` | **The staleness check.** Returns the latest unit modification timestamp for a file. If `nil`, the file has no index data. If the date predates the file's mtime, it's stale. | `IndexStoreDB.swift:514-525` |
| `pollForUnitChangesAndWait()` | Re-scans the store for unit files changed since last poll. Needed after a rebuild. | `IndexStoreDB.swift:157-162` |
| `enableOutOfDateFileWatching: true` | Background detection of stale units via a delegate. Higher CPU/memory; only for long-running processes. | `IndexStoreDB.swift:85` |

### Layer 2: Cache per-file SCIP `Document` output

Since the pipeline is per-file (`SCIPIndexBuilder.makeDocument` processes one file at a time), cache the **serialized `Scip_Document`** keyed by `(filePath, fileContentHash, toolchainVersion)`:

```
~/.cache/scip-swift/
├── <repo-hash>/
│   ├── index-db/              # persisted IndexStoreDB
│   └── documents/
│       ├── <file-hash>.scipdoc  # serialized Scip_Document protobuf
│       └── manifest.json        # { filePath, contentHash, toolchain, mtime }
```

On re-run: check if `<filePath>` content hash matches cache → reuse cached `Scip_Document`. Only changed files are reprocessed.

### Recommended Architecture

| Component | New File | Responsibility |
|-----------|----------|----------------|
| `CacheStore` | `Sources/scip-swift/Caching/CacheStore.swift` | Manages `~/.cache/scip-swift/<repo>/` directory, document cache read/write, manifest |
| `IncrementalPlanner` | `Sources/scip-swift/Caching/IncrementalPlanner.swift` | Compares file mtimes/content hashes vs cache manifest; returns `(changedFiles, unchangedFiles)` |
| Modified `SCIPIndexBuilder` | existing | Accepts a cache; for unchanged files, loads cached `Scip_Document`; for changed, rebuilds + caches |

### Cache Invalidation Triggers

| Trigger | Detection | Action |
|---------|-----------|--------|
| File content changed | SHA-256 of file content vs manifest | Reprocess that file |
| Swift toolchain changed | `ToolchainInfo.pinnedSwiftVersion` vs cached version | **Full rebuild** (USR stability not guaranteed — `.planning/PROJECT.md` Constraint) |
| `indexstore-db` revision changed | `Package.resolved` revision vs cached | Full rebuild (index format may change) |
| `scip-swift` version changed | `ScipSwiftVersion.version` vs cached | Full rebuild (output format may change) |
| Cache directory missing | Filesystem check | Full rebuild |

### Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Content-hash per-file document cache | mtime-based cache | mtime is unreliable across git operations (checkout, pull reset mtimes); content hash is authoritative |
| Persisted IndexStoreDB (`~/.cache/`) | Rebuild store each time (current) | Current approach is the bottleneck — a full `swift build` per run. Persisting the DB across runs means only changed files trigger re-indexing |
| `enableOutOfDateFileWatching: true` | Manual `pollForUnitChangesAndWait()` | The watching flag uses extra CPU/memory and requires a delegate; for a CLI that runs and exits, a one-shot poll is simpler |

---

## 4. SCIP `external_symbols` + Cross-Repo Linking

### Recommendation: Populate `external_symbols` properly + multi-repo `--link` mode

**Confidence: HIGH** (verified from canonical `Protos/scip.proto` lines 26-39, 253-310, 465-516; and the current `SCIPIndexBuilder.swift` implementation)

### How `external_symbols` Works (verified from proto)

```proto
message Index {
  Metadata metadata = 1;
  repeated Document documents = 2;
  // Symbols referenced from this index but defined in an external package.
  // Leave empty if the external package will get indexed separately.
  repeated SymbolInformation external_symbols = 3;
}
```

The proto comment (lines 31-36) is explicit: **`external_symbols` is for symbols that are referenced but not defined in this index, and that will NOT be indexed separately.** If the external package IS indexed separately (the cross-repo linking case), you **leave `external_symbols` empty** — the symbol strings in `Occurrence.symbol` will resolve against the other index.

### Current Implementation (verified in `SCIPIndexBuilder.swift:41-43`)

```swift
index.externalSymbols = referencedSymbols.values
  .filter { !definedSymbolStrings.contains($0.symbol) }
  .sorted { $0.symbol < $1.symbol }
```

This is **correct for the single-repo case**: Swift stdlib types (`String`, `Int`, `Array`) are referenced but never defined in the project index, so they go into `external_symbols` with their `displayName` so consumers can show hover info. The current heuristic (referenced-but-undefined) works because stdlib is never separately indexed.

### What Changes for Cross-Repo Linking

Cross-repo linking means: repo B depends on repo A. Both are indexed separately. When B references a symbol from A, the `Occurrence.symbol` string must match the `SymbolInformation.symbol` string in A's index — **so that when both indexes are loaded by Sourcegraph, cross-references resolve.**

| Requirement | How to Achieve It |
|-------------|-------------------|
| Symbol string consistency across repos | The current USR-based symbol format (`scip-swift swift <module> . <usr>`) is already stable across repos **for the same toolchain version** — the USR is compiler-determined. As long as both repos are indexed with the same Swift toolchain, USRs match. |
| `external_symbols` for dependency symbols | **Leave empty** if the dependency will be indexed separately. The proto says so explicitly. Only populate for truly un-indexed symbols (stdlib, system frameworks). |
| `isSystem` flag for correctness | `SymbolLocation.isSystem` (`SymbolLocation.swift:24`) marks stdlib/framework occurrences. Use this to distinguish "external because it's a system symbol" (→ `external_symbols`) from "external because it's a dependency" (→ leave for separate indexing). Currently ignored (heuristic-based). |

### Multi-Repo `--link` Mode (Recommended Design)

```sh
scip-swift index /path/to/repo-b \
  --link /path/to/repo-a/index.scip  # resolve cross-refs against A's index
```

| Component | Responsibility |
|-----------|----------------|
| `ExternalIndexLoader` | Reads a `.scip` file, extracts `(symbol → SymbolInformation)` map, identifies which symbols are "defined externally" |
| Modified `SCIPIndexBuilder` | When a referenced symbol is found in an external index, **omit from `external_symbols`** (it'll resolve via the linked index). When not found in any index and `isSystem`, add to `external_symbols`. |

### Protobuf Merging (SwiftProtobuf)

SwiftProtobuf 1.38.1 (already pinned, `Package.swift:10`) supports everything needed. There is no "merge" primitive needed — the approach is:

1. **Don't merge `.scip` files.** SCIP indexes are per-project-root. Sourcegraph handles multiple indexes.
2. **Read external indexes to build a symbol-resolution set.** `Scip_Index(serializedData: data)` parses any `.scip` file; iterate `index.documents[].symbols[]` to build the external symbol set.
3. **Use the set to decide `external_symbols` membership.** Pure application logic, no protobuf merge.

### What NOT to Do

| Avoid | Why | Do Instead |
|-------|-----|------------|
| Merge multiple `.scip` files into one | SCIP indexes are rooted at `project_root`; merged indexes violate the "all documents under project_root" invariant | Keep separate indexes; Sourcegraph consumes multiple |
| Generate synthetic symbol strings for cross-repo | USRs already match across repos for the same toolchain; inventing a new scheme breaks resolution | Trust USR stability (same toolchain = same USR) |
| Populate `external_symbols` for dependency types when `--link` is used | Proto explicitly says leave empty if the external package will be indexed separately | Only populate for `isSystem` symbols not in any linked index |

---

## Version Compatibility Matrix

| Package | Current (v0.1.2) | v0.2.0 | Change Needed | Notes |
|---------|-------------------|--------|---------------|-------|
| `swift-tools-version` | 6.2 | 6.2 | None | Toolchain pin is load-bearing (USR stability) |
| `indexstore-db` | main @ `c993f4fb` | same | None | Relations API already present at this revision |
| `swift-protobuf` | 1.38.1 | same | None | `Scip_Index` serialization already used |
| `swift-argument-parser` | 1.8.2 | same | None | May add `--link`, `--cache-dir` flags (API supports) |
| `swift-lmdb` (transitive) | main @ `a4bc8780` | same | None | Brought in by indexstore-db |

**Key finding: no dependency version changes are needed for v0.2.0.** All four feature areas are implementable with the current pinned versions.

---

## Installation

### For End Users (v0.2.0 target)

```bash
brew tap phuongddx/scip-swift
brew install scip-swift
```

### For Developers (unchanged)

```bash
git clone https://github.com/phuongddx/scip-swift.git
cd scip-swift
swift build -c release
cp .build/release/scip-swift /usr/local/bin/
```

### For CI Release (new — to be built)

```bash
# 1. Build release binary (macOS arm64)
swift build -c release

# 2. Package as tarball
tar czf scip-swift-0.2.0-arm64-macos.tar.gz -C .build/release scip-swift

# 3. Create GitHub Release
gh release create v0.2.0 scip-swift-0.2.0-arm64-macos.tar.gz

# 4. Update formula sha256 + commit to homebrew-scip-swift tap
shasum -a 256 scip-swift-0.2.0-arm64-macos.tar.gz
# → update Formula/scip-swift.rb in homebrew-scip-swift repo
```

---

## Sources

| Source | What Was Verified | Confidence |
|--------|-------------------|------------|
| `.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexStoreDB.swift` | Relations API (`occurrences(relatedToUSR:roles:)`), `dateOfLatestUnitFor`, `enableOutOfDateFileWatching`, `pollForUnitChangesAndWait` | **HIGH** (exact source the project compiles against) |
| `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolOccurrence.swift` | `relations: [SymbolRelation]` field, `SymbolRelation` struct | **HIGH** |
| `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolRole.swift` | All 10 relation role bits (`.childOf`, `.baseOf`, `.overrideOf`, etc.) | **HIGH** |
| `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolLocation.swift` | `isSystem` flag, single-anchor position (no end column) | **HIGH** |
| `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolProperty.swift` | `unitTest`, `protocolInterface`, access-control bits | **HIGH** |
| `Protos/scip.proto` (vendored from sourcegraph/scip) | `Relationship` message (lines 465-516), `external_symbols` (lines 31-36), `SymbolInformation` fields, `SymbolRole` enum | **HIGH** (canonical schema) |
| `docs/research-scip-swift-limitations.md` | Gap taxonomy, relationship-mapping design, peer comparison | **HIGH** (code-grounded prior research) |
| Homebrew Formula Cookbook (`docs.brew.sh/Formula-Cookbook`) | Formula structure, `bin.install`, `depends_on macos:`, sha256, license, test block, `std_swift_args` | **HIGH** (official docs, fetched live) |
| Homebrew Taps docs (`docs.brew.sh/Taps`) | Tap naming convention (`homebrew-<repo>`), `brew tap user/repo`, trust model | **HIGH** (official docs) |
| Homebrew Bottles docs (`docs.brew.sh/Bottles`) | Bottle DSL, `root_url` for custom taps, `cellar: :any_skip_relocation` | **HIGH** (official docs) |
| `homebrew-core` `swiftlint.rb` (fetched live) | Real SwiftPM build-from-source formula pattern (`std_swift_args`, `bin.install`) | **HIGH** (canonical example) |
| `homebrew-core` `swiftformat.rb` (fetched live) | Confirms SwiftPM formula pattern, `uses_from_macos "swift" => :build` | **HIGH** |
| `homebrew-core` `scip.rb` (fetched live) | Confirms name collision (scip-code/scip is not in homebrew-core; the formula is for SCIP optimization solver) — no namespace conflict for scip-swift | **HIGH** |
| scip-code/scip releases page | Release pattern (tarball per OS/arch), `scip lint` availability, v0.9.0 is latest | **HIGH** |

---
*Stack research for: scip-swift v0.2.0*
*Researched: 2026-08-11*
