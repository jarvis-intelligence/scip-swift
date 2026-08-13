# Phase 1: Symbol Metadata Enrichment - Pattern Map

**Mapped:** 2026-08-11
**Files analyzed:** 10 (4 new, 5 modified, 1 new fixture)
**Analogs found:** 10 / 10

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Sources/scip-swift/SCIPMapping/RelationshipMapping.swift` (NEW) | mapper (enum namespace) | transform | `SymbolKindMapping.swift` | exact |
| `Sources/scip-swift/SCIPMapping/SignatureMapping.swift` (NEW) | mapper (enum namespace) | transform | `SymbolKindMapping.swift` | exact |
| `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` (MODIFIED) | orchestrator (struct) | request-response | `SCIPIndexBuilder.swift` (self) | exact |
| `Sources/scip-swift/SCIPMapping/SymbolRoleMapping.swift` (MODIFIED) | mapper (enum namespace) | bitfield transform | `SymbolRoleMapping.swift` (self) | exact |
| `Tests/scip-swiftTests/RelationshipMappingTests.swift` (NEW) | test | unit | `SymbolRoleMappingTests.swift` | exact |
| `Tests/scip-swiftTests/SignatureMappingTests.swift` (NEW) | test | unit | `SymbolKindMappingTests.swift` | exact |
| `Tests/scip-swiftTests/SymbolRoleMappingTests.swift` (MODIFIED) | test | unit | `SymbolRoleMappingTests.swift` (self) | exact |
| `Tests/scip-swiftTests/IntegrationTests.swift` (MODIFIED) | test | integration | `IntegrationTests.swift` (self) | exact |
| `Fixtures/RelationSpikeFixture/` (NEW) | fixture | file-I/O | `Fixtures/MiniSwiftPackage/` | exact |
| `Tests/scip-swiftTests/RelationSpikeTests.swift` (NEW, META-06) | test | integration (diagnostic) | `IntegrationTests.swift` | role-match |

## Pattern Assignments

### `Sources/scip-swift/SCIPMapping/RelationshipMapping.swift` (mapper, transform)

**Analog:** `Sources/scip-swift/SCIPMapping/SymbolKindMapping.swift`

This is a new stateless pure-function mapper converting IndexStoreDB `SymbolRelation[]` to SCIP `Scip_Relationship[]`. It follows the exact same structural pattern as every other mapper in the SCIPMapping layer.

**Enum-as-namespace pattern** (`SymbolKindMapping.swift:8-9`):
```swift
enum SymbolKindMapping {
  static func scipKind(for symbol: Symbol) -> Scip_SymbolInformation.Kind {
```
New file uses `enum RelationshipMapping { static func scipRelationships(...) }` — no `struct`, no `class`, no `init`.

**File-level doc comment pattern** (`SymbolKindMapping.swift:1-6`):
```swift
import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion — `Symbol.kind` mapping (task 3.4).
///
/// SCIP's `SymbolInformation.Kind` enum is a superset covering many languages; where Swift has no
/// exact counterpart (e.g. `destructor`, `conversionFunction`, C++-only `using`) this maps to the
/// closest reasonable kind rather than `unspecifiedKind`, except where nothing reasonable exists.
enum SymbolKindMapping {
```
New file starts with `import IndexStoreDB`, then a `///` doc comment referencing the requirement (META-01) and explaining the mapping rationale (which IndexStoreDB roles map to which SCIP booleans, and why `.childOf` is excluded).

**Exhaustive role handling** — `SymbolKindMapping` uses exhaustive `switch` over `symbol.kind`. For relationships, the analog is checking each `SymbolRole` bit via `.contains()` (same as `SymbolRoleMapping` does). Relationship mapping uses `compactMap` to filter out dropped relations (`.childOf`, `.calledBy`, etc.) — the `compactMap` returning `nil` pattern mirrors `SCIPIndexBuilder.makeDocument()` returning `nil` for empty-occurrence files.

**Error handling:** None — pure-function mappers never `throw`. Return empty array or filter via `compactMap` for unmappable relations.

---

### `Sources/scip-swift/SCIPMapping/SignatureMapping.swift` (mapper, transform)

**Analog:** `Sources/scip-swift/SCIPMapping/SymbolKindMapping.swift`

Another new stateless pure-function mapper. Converts `Symbol` → `Scip_Signature?` using `Symbol.kind`/`subKind`/`name`. The optional return mirrors `SCIPIndexBuilder.makeDocument()` returning `Scip_Document?`.

**Exhaustive switch pattern** (`SymbolKindMapping.swift:20-69`):
```swift
switch symbol.kind {
case .unknown, .using, .commentTag:
  return .unspecifiedKind
case .module:
  return .module
case .namespace, .namespaceAlias:
  return .namespace
// ... exhaustive over all IndexSymbolKind cases
```
New file uses the same exhaustive `switch symbol.kind` to determine the declaration prefix (`func`, `var`, `class`, etc.), returning `nil` for kinds that don't get signatures (`.parameter`, `.module`).

**Private static helper** (`PositionMapping.swift:27-29`):
```swift
private static func approximateTokenLength(displayName: String) -> Int {
  displayName.prefix(while: { $0 != "(" }).utf8.count
}
```
New file uses `private static func declarationPrefix(for symbol: Symbol) -> String?` as a private helper — same visibility pattern as `PositionMapping.approximateTokenLength`.

**File header** (`SymbolKindMapping.swift:1-6`): Same `import IndexStoreDB` + `///` doc comment referencing requirement META-05 and explaining the limitation (minimal signatures without parameter/return types).

---

### `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` (orchestrator, MODIFIED)

**Analog:** Self — modifications to the existing occurrence loop

This is the integration point. The existing occurrence loop at lines 75-110 is the pattern for where each new feature slots in. The research doc's "Modified makeDocument()" code example (RESEARCH.md lines 610-680) shows the exact insertion points.

**Current occurrence loop** (`SCIPIndexBuilder.swift:77-109`):
```swift
for occurrence in occurrences.sorted() {
  let symbol = occurrence.symbol
  let isLocal = symbol.properties.contains(.local)
  let symbolString = /* ... */

  var scipOccurrence = Scip_Occurrence()
  scipOccurrence.symbol = symbolString
  scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles)
  scipOccurrence.singleLineRange = PositionMapping.singleLineRange(
    location: occurrence.location,
    displayName: symbol.name
  )
  document.occurrences.append(scipOccurrence)

  var symbolInformation = Scip_SymbolInformation()
  symbolInformation.symbol = symbolString
  symbolInformation.displayName = symbol.name
  symbolInformation.kind = SymbolKindMapping.scipKind(for: symbol)

  if occurrence.roles.contains(.definition) {
    definedSymbols[symbolString] = symbolInformation
  } else if !isLocal, referencedSymbols[symbolString] == nil {
    referencedSymbols[symbolString] = symbolInformation
  }
}
```

**Delegation to mappers** — each new feature adds one line calling a pure mapper:
- META-01: `symbolInformation.relationships = RelationshipMapping.scipRelationships(...)` (after `symbolInformation.kind` assignment, only for `.definition` occurrences)
- META-02: `symbolInformation.enclosingSymbol = ...` (after kind assignment, only for `isLocal` symbols with `.childOf` relation)
- META-03: Change `SymbolRoleMapping.scipRoles(for: occurrence.roles)` → `SymbolRoleMapping.scipRoles(for: occurrence.roles, symbol: symbol)` (signature change)
- META-05: `symbolInformation.signatureDocumentation = SignatureMapping.signature(for: symbol)` (after kind assignment)

**External symbols classification** (`SCIPIndexBuilder.swift:40-43`):
```swift
index.externalSymbols = referencedSymbols.values
  .filter { !definedSymbolStrings.contains($0.symbol) }
  .sorted { $0.symbol < $1.symbol }
```
META-04 changes this: split `referencedSymbols` into `systemReferencedSymbols` and non-system, using `occurrence.location.isSystem` as the discriminator during the occurrence loop. The post-processing `.filter` + `.sorted` pattern remains identical.

**Variable accumulation pattern** (`SCIPIndexBuilder.swift:27-28`):
```swift
var referencedSymbols: [String: Scip_SymbolInformation] = [:]
var definedSymbolStrings: Set<String> = []
```
META-04 adds `var systemReferencedSymbols: [String: Scip_SymbolInformation] = [:]` following the same `var <name>: [String: Scip_SymbolInformation] = [:]` pattern.

---

### `Sources/scip-swift/SCIPMapping/SymbolRoleMapping.swift` (mapper, MODIFIED)

**Analog:** Self — extending the existing bitfield mapper

**Current pattern** (`SymbolRoleMapping.swift:8-20`):
```swift
enum SymbolRoleMapping {
  static func scipRoles(for indexStoreRoles: SymbolRole) -> Int32 {
    var roles: Int32 = 0
    if indexStoreRoles.contains(.definition) {
      roles |= Int32(Scip_SymbolRole.definition.rawValue)
    }
    if indexStoreRoles.contains(.write) {
      roles |= Int32(Scip_SymbolRole.writeAccess.rawValue)
    } else if indexStoreRoles.contains(.reference) || indexStoreRoles.contains(.read) {
      roles |= Int32(Scip_SymbolRole.readAccess.rawValue)
    }
    return roles
  }
}
```

META-03 adds three new `if ... { roles |= ... }` blocks in the same style:
- `.declaration` → `Scip_SymbolRole.forwardDefinition`
- `symbol.properties.contains(.unitTest)` → `Scip_SymbolRole.test`
- Generated path heuristic → `Scip_SymbolRole.generated`

**Signature change:** The function parameter changes from `(for indexStoreRoles: SymbolRole)` to `(for indexStoreRoles: SymbolRole, symbol: Symbol)` to access `symbol.properties`. This is the ONLY existing function whose signature changes in Phase 1.

**Defensive guard for ForwardDefinition/Definition collision** (per RESEARCH.md Pitfall 4): The `.declaration` check must be guarded so it doesn't fire when `.definition` is also present:
```swift
if indexStoreRoles.contains(.declaration), !indexStoreRoles.contains(.definition) {
  roles |= Int32(Scip_SymbolRole.forwardDefinition.rawValue)
}
```

**File header doc comment** (`SymbolRoleMapping.swift:1-7`): Update the `///` comment to mention the expanded role set.

---

### `Tests/scip-swiftTests/RelationshipMappingTests.swift` (test, unit — NEW)

**Analog:** `Tests/scip-swiftTests/SymbolRoleMappingTests.swift`

**Test structure pattern** (`SymbolRoleMappingTests.swift:1-8`):
```swift
import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("SymbolRoleMapping")
struct SymbolRoleMappingTests {
```
New file: `@Suite("RelationshipMapping") struct RelationshipMappingTests`.

**Test method pattern** (`SymbolRoleMappingTests.swift:8-19`):
```swift
@Test(".definition maps to SCIP Definition")
func definitionRole() {
  let roles = SymbolRoleMapping.scipRoles(for: .definition)
  #expect(roles == Int32(Scip_SymbolRole.definition.rawValue))
}
```
Each `@Test` has a string description, a `func` body, and uses `#expect` for assertions. New tests follow the same `@Test("description") func name() { ... #expect(...) }` pattern.

**Constructing test inputs** — `SymbolRoleMappingTests` constructs `SymbolRole` directly from option set literals (`.definition`, `[.reference, .write]`). For relationship tests, construct `SymbolRelation` and `Symbol` test fixtures. Follow the `makeSymbol` helper pattern from `SymbolKindMappingTests.swift:7-13`:
```swift
private func makeSymbol(
  kind: IndexSymbolKind,
  subKind: IndexSymbolSubKind = .none
) -> Symbol {
  Symbol(usr: "s:fake", name: "fake", kind: kind, subKind: subKind, language: .swift)
}
```

**Relationship test cases** (per RESEARCH.md mapping table):
- `.overrideOf` → `isReference == true && isImplementation == true`
- `.baseOf` → `isImplementation == true && isReference == false`
- `.extendedBy` → `isImplementation == true`
- `.childOf` → excluded (returns nil in `compactMap`, no Relationship emitted)
- `.calledBy` / `.accessorOf` / `.containedBy` / `.ibTypeOf` → dropped (nil)

---

### `Tests/scip-swiftTests/SignatureMappingTests.swift` (test, unit — NEW)

**Analog:** `Tests/scip-swiftTests/SymbolKindMappingTests.swift`

**Test structure** — same `@Suite` / `@Test` / `#expect` pattern. Uses `makeSymbol` helper from `SymbolKindMappingTests.swift:7-13` to construct `Symbol` fixtures.

**Test cases** (per RESEARCH.md Pattern 5):
- `.function` → signature text starts with `"func"`
- `.instanceMethod` → `"func"`
- `.classMethod` / `.staticMethod` → `"static func"`
- `.instanceProperty` → `"var"`
- `.class` → `"class"`
- `.struct` → `"struct"`
- `.parameter` → `nil` (no signature)
- `.module` → `nil`

---

### `Tests/scip-swiftTests/SymbolRoleMappingTests.swift` (test, unit — MODIFIED)

**Analog:** Self — extending existing test suite

Add new `@Test` cases to the existing `@Suite("SymbolRoleMapping")` struct. The signature change in the mapper (adding `symbol:` parameter) means **all existing test calls must be updated** from:
```swift
SymbolRoleMapping.scipRoles(for: .definition)
```
to:
```swift
SymbolRoleMapping.scipRoles(for: .definition, symbol: makeSymbol(kind: .function))
```

Follow the `makeSymbol` helper pattern from `SymbolKindMappingTests.swift:7-13` to add a private helper to `SymbolRoleMappingTests`.

**New test cases** (META-03):
- `.declaration` (without `.definition`) → `forwardDefinition` bit set
- `.declaration` AND `.definition` together → only `definition` bit set (collision guard)
- `symbol.properties.contains(.unitTest)` → `test` bit set
- Generated path heuristic (if implemented) → `generated` bit set

---

### `Tests/scip-swiftTests/IntegrationTests.swift` (test, integration — MODIFIED)

**Analog:** Self — extending existing integration test

**Existing structure** (`IntegrationTests.swift:8-48`):
```swift
@Suite("Integration: build -> IndexStore -> SCIP")
struct IntegrationTests {
  @Test("full pipeline produces a valid SCIP index for the fixture package")
  func fullPipeline() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    // ... builds, runs SCIPIndexBuilder, asserts on document properties
  }
}
```

**Fixture path resolution** (`IntegrationTests.swift:52-57`):
```swift
private static func fixtureRepoPath() -> String {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return repoRoot.appendingPathComponent("Fixtures/MiniSwiftPackage").path
}
```

**Temp directory pattern** (`IntegrationTests.swift:21-22, 58-63`):
```swift
let workDirectory = try Self.makeTemporaryDirectory()
defer { try? FileManager.default.removeItem(atPath: workDirectory) }
// ...
private static func makeTemporaryDirectory() throws -> String {
  let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("scip-swift-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
  return path
}
```

META-04 additions: Add assertions that `index.externalSymbols` are classified via `isSystem` — verify that stdlib types (referenced by the fixture) appear in `externalSymbols`. The `#expect` assertion style follows the existing pattern.

---

### `Fixtures/RelationSpikeFixture/` (fixture — NEW)

**Analog:** `Fixtures/MiniSwiftPackage/`

**Package.swift pattern** (`Fixtures/MiniSwiftPackage/Package.swift`):
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "MiniSwiftPackage",
  targets: [
    .target(name: "MiniSwiftPackage")
  ]
)
```
New fixture: `name: "RelationSpikeFixture"`, target `"RelationSpike"`. Same `swift-tools-version: 6.2` (matches `.swift-version` pin).

**Source file** — `Greeter.swift` is a simple public struct with no inheritance. The spike fixture (`Spike.swift`) adds the patterns from RESEARCH.md lines 500-535: class inheritance with `override`, protocol conformance, protocol conformance via extension, protocol inheritance, and local variables in function scope.

**Directory layout** (`Fixtures/MiniSwiftPackage/`):
```
Fixtures/RelationSpikeFixture/
├── Package.swift
└── Sources/
    └── RelationSpike/
        └── Spike.swift
```

---

### `Tests/scip-swiftTests/RelationSpikeTests.swift` (test, diagnostic — NEW, META-06)

**Analog:** `Tests/scip-swiftTests/IntegrationTests.swift`

This is the META-06 spike diagnostic test. It follows the `IntegrationTests` pattern (shells out to real `swift build`, opens IndexStoreDB, queries occurrences) but instead of asserting SCIP output, it dumps relation data.

**Build + IndexStoreDB open pattern** (`IntegrationTests.swift:20-33`):
```swift
let runner = SwiftPMBuildRunner(
  repoPath: fixtureRepoPath,
  configuration: .debug,
  scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
)
let buildResult = try runner.produceIndexStore()

let builder = SCIPIndexBuilder(
  repoPath: fixtureRepoPath,
  indexStorePath: buildResult.indexStorePath,
  databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
  buildToolName: BuildTool.swiftpm.rawValue,
  converterVersion: "test"
)
```
The spike test uses the same `SwiftPMBuildRunner` + `produceIndexStore()` to build the spike fixture, then opens IndexStoreDB via `IndexStoreLoader.open(storePath:databasePath:)`.

**Diagnostic dump pattern** (RESEARCH.md lines 558-572):
```swift
@Test("META-06: Dump relation population for spike fixture")
func dumpRelations() throws {
  // ... open IndexStoreDB ...
  let occurrences = indexStoreDB.symbolOccurrences(inFilePath: spikeFilePath)
  for occ in occurrences.sorted() {
    print("SYMBOL: \(occ.symbol.name) [\(occ.symbol.usr)]")
    print("  ROLES: \(occ.roles)")
    for rel in occ.relations {
      print("  RELATION: \(rel.symbol.name) [\(rel.symbol.usr)]")
      print("    REL ROLES: \(rel.roles)")
    }
  }
}
```

**Fixture path** — uses the same `URL(fileURLWithPath: #filePath).deletingLastPathComponent()` chain but navigates to `Fixtures/RelationSpikeFixture`.

## Shared Patterns

### Enum-as-Namespace for Stateless Mappers

**Source:** `Sources/scip-swift/SCIPMapping/SymbolKindMapping.swift:8`, `SymbolRoleMapping.swift:8`, `PositionMapping.swift:14`, `SCIPSymbolFormatter.swift:22`
**Apply to:** `RelationshipMapping.swift`, `SignatureMapping.swift`

```swift
enum RelationshipMapping {
  static func scipRelationships(...) -> [Scip_Relationship] { ... }
}
```
Using `enum` (not `struct`) signals "no instances, no constructor" — the strongest convention signal in this codebase. Never add `private init()` — the `enum` without cases already prevents instantiation.

### Import Organization

**Source:** All source files
**Apply to:** All new source files

```swift
import IndexStoreDB
```
For test files:
```swift
import IndexStoreDB
import Testing

@testable import scip_swift
```
External imports alphabetically sorted, then blank line, then `@testable import`. No internal imports (single-target module).

### File-Level Doc Comments

**Source:** Every source file in `SCIPMapping/`
**Apply to:** `RelationshipMapping.swift`, `SignatureMapping.swift`

```swift
import IndexStoreDB

/// Requirement: <requirement name and task ID>.
///
/// <2-4 sentences explaining what this maps, why, and any approximation or limitation>
enum FooMapping {
```
Every file starts with a `///` doc comment referencing the requirement (e.g., "META-01") and explaining the design rationale. Comments explain WHY (design decisions, limitations), never WHAT.

### Pure-Function Mapper — No Throwing

**Source:** `SymbolKindMapping.swift:9`, `SymbolRoleMapping.swift:9`, `PositionMapping.swift:15`
**Apply to:** `RelationshipMapping.swift`, `SignatureMapping.swift`

All mappers use `static func` with direct returns — never `throws`. Unmappable inputs return a default/nil/empty result:
- `SymbolKindMapping` → `.unspecifiedKind` for unknown kinds
- `RelationshipMapping` → `compactMap` returning `nil` for dropped relations
- `SignatureMapping` → `nil` for kinds without signatures

### SCIP Protobuf Message Construction

**Source:** `SCIPIndexBuilder.swift:88-100`
**Apply to:** `SCIPIndexBuilder.swift` modifications (META-01, META-02, META-05)

```swift
var symbolInformation = Scip_SymbolInformation()
symbolInformation.symbol = symbolString
symbolInformation.displayName = symbol.name
symbolInformation.kind = SymbolKindMapping.scipKind(for: symbol)
```
Pattern: declare `var`, set fields via property assignment. New fields follow the same `symbolInformation.<field> = <value>` style:
```swift
symbolInformation.relationships = RelationshipMapping.scipRelationships(...)
symbolInformation.enclosingSymbol = ...
symbolInformation.signatureDocumentation = SignatureMapping.signature(for: symbol)
```

### Swift Testing Conventions

**Source:** All test files
**Apply to:** All new and modified test files

- `@Suite("Descriptive Name")` on the test struct
- `@Test("behavior description")` on each test function
- `#expect(condition)` for assertions, `#require(value)` for unwrapping with failure
- `@testable import scip_swift` for access to internal types
- No XCTest — Swift Testing only

### Fixture Package Structure

**Source:** `Fixtures/MiniSwiftPackage/Package.swift`
**Apply to:** `Fixtures/RelationSpikeFixture/`

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "<FixtureName>",
  targets: [
    .target(name: "<ModuleName>")
  ]
)
```
`swift-tools-version: 6.2` matches the pinned toolchain in `.swift-version`. Minimal target declaration — no dependencies, no products.

## No Analog Found

All 10 files have strong analogs in the existing codebase. No files require falling back to RESEARCH.md patterns alone.

## Metadata

**Analog search scope:**
- `Sources/scip-swift/SCIPMapping/` (5 files — all mappers + builder)
- `Sources/scip-swift/Build/` (2 files — error enum + detector)
- `Tests/scip-swiftTests/` (5 files — all existing test suites)
- `Fixtures/MiniSwiftPackage/` (2 files — existing fixture)

**Files scanned:** 14 source/test/fixture files
**Pattern extraction date:** 2026-08-11
