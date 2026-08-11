# Phase 1: Symbol Metadata Enrichment - Research

**Researched:** 2026-08-11
**Domain:** IndexStoreDB → SCIP protobuf symbol metadata enrichment (relationships, enclosing symbols, roles, signatures, external-symbol classification)
**Confidence:** HIGH

## Summary

Phase 1 enriches the emitted `.scip` index with relationship data (inheritance, conformance, override), enclosing symbols for locals, expanded SymbolRole bits, basic signatures, and authoritative external-symbol classification. Every piece of data this phase maps is **already fetched from IndexStoreDB** — the current `SCIPIndexBuilder.makeDocument()` loop reads `occurrence.symbol`, `occurrence.roles`, and `occurrence.location` but **discards `occurrence.relations`** entirely. No new dependencies are required; all APIs needed are verified present in the pinned `indexstore-db` revision (`c993f4fb`).

The single biggest unknown is **META-06**: whether the Swift compiler populates `occurrence.relations` with the same depth and direction as Clang. The IndexStoreDB C layer (`indexstoredb_symbol_occurrence_relations` callback in `SymbolOccurrence.swift:71-78`) [VERIFIED: `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolOccurrence.swift:71-78`] does iterate and append relations for every occurrence — the plumbing exists. But whether the Swift frontend actually fills `.baseOf`/`.overrideOf`/`.extendedBy` for Swift source code, and critically **which direction** the roles flow (base→derived or derived→base), determines the entire relationship mapping architecture. The spike must run first.

The `scip lint` validation rules are verified from the canonical Go source (`cmd/scip/lint.go`). Three rules directly constrain the relationship implementation: `missingRelationshipFlagError` (at least one boolean must be set), `missingSymbolInRelationshipError` (the target symbol must exist in the index), and `bothLocalAndExternalSymbolError` (a symbol cannot be both defined and external). These rules mean every `Relationship.symbol` must point to a symbol that exists somewhere in the index — requiring a cross-document accumulator if relationships reference symbols in other files.

**Primary recommendation:** Run the META-06 spike as Wave 0 to determine relation direction and depth, then implement META-03 (role expansion — zero-risk) in parallel with META-01/META-02 (relationships + enclosing), followed by META-04 (isSystem) and META-05 (signatures).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| META-01 | Map IndexStoreDB relationships (inheritance, conformance, override) into SCIP `Relationship` fields | Mapping table in Architecture Patterns section; IndexStoreDB `SymbolRelation` API verified from source; spike design determines role direction |
| META-02 | Populate `enclosing_symbol` for locals using `.childOf` relation data | `.childOf` relation role verified in `SymbolRole.swift:32`; `Scip_SymbolInformation.enclosingSymbol` field verified in `Scip.pb.swift:1509` |
| META-03 | Expand `SymbolRoleMapping` to set `ForwardDefinition`, `Generated`, and `Test` bits | Current mapper at `SymbolRoleMapping.swift:9-20`; `SymbolProperty.unitTest` verified at `SymbolProperty.swift:24`; SCIP bits verified at `scip.proto:533-544` |
| META-04 | Use `SymbolLocation.isSystem` to correctly classify `external_symbols` | `SymbolLocation.isSystem` verified at `SymbolLocation.swift:24`; current heuristic at `SCIPIndexBuilder.swift:41-43` |
| META-05 | Populate `signature_documentation` with basic signatures from kind/subKind/displayName | `Scip_Signature` struct verified at `Scip.pb.swift:1418-1438`; `Symbol.kind`/`subKind`/`name` verified at `Symbol.swift:77-86` |
| META-06 | Empirically validate IndexStoreDB relation population depth for Swift (spike before full mapping) | Spike design in dedicated section below; C callback plumbing verified, Swift frontend depth is the unknown |
| TEST-02 | Add unit tests for `RelationshipMapping` (new mapper) | Test patterns section; existing test conventions in `SymbolRoleMappingTests.swift` |
| TEST-03 | Add unit tests for expanded `SymbolRoleMapping` cases | Test patterns section; existing tests at `SymbolRoleMappingTests.swift` |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **macOS-only** — do not try to make the build/test pipeline pass on Linux
- **Swift Testing framework** (`@Suite`/`@Test` with string descriptions), not XCTest — `Tests/scip-swiftTests/*.swift` is the pattern
- **2-space indentation** throughout
- **Enum-as-namespace for stateless mappers** — `enum FooMapper { static func ... }`, not struct/class
- **Exhaustive switches** on IndexStoreDB enums — compile-time safety if new cases are added
- **Generated/Scip.pb.swift is never hand-edited** — regenerate via `Protos/generate.sh` instead
- **IntegrationTests.swift shells out to real `swift build`** — no mocks
- **Toolchain pinned to 6.2.4** via `.swift-version` — USR stability not guaranteed across versions

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Relationship mapping (META-01) | SCIP Mapping Layer | — | Pure-function mapper converts IndexStoreDB `SymbolRelation` → SCIP `Relationship`; wired into `SCIPIndexBuilder.makeDocument()` |
| Enclosing symbol (META-02) | SCIP Mapping Layer | — | Extracted from `.childOf` relation in same occurrence loop; sets `enclosingSymbol` on `Scip_SymbolInformation` |
| Role expansion (META-03) | SCIP Mapping Layer | — | Pure-function addition to existing `SymbolRoleMapping`; needs `Symbol` parameter for `SymbolProperty.unitTest` access |
| External-symbol classification (META-04) | SCIP Mapping Layer | — | `SymbolLocation.isSystem` read in occurrence loop; replaces heuristic in `build()` post-processing |
| Signature documentation (META-05) | SCIP Mapping Layer | — | New `SignatureMapping` mapper reconstructs from `Symbol.kind`/`subKind`/`name` |
| Relation validation spike (META-06) | Test Infrastructure | SCIP Mapping Layer | Empirical fixture + diagnostic dump; determines if relationship mapping scope is full or reduced |

## Standard Stack

### Core

No new dependencies. All APIs are already present in the pinned versions.

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| IndexStoreDB | main @ `c993f4fb` | Relations API, `SymbolProperty.unitTest`, `SymbolLocation.isSystem` | Already pinned in `Package.swift`; all needed APIs verified present in source [VERIFIED: `.build/checkouts/indexstore-db/Sources/IndexStoreDB/`] |
| SwiftProtobuf | 1.38.1 | SCIP protobuf serialization (`Scip_Relationship`, `Scip_Signature`, `Scip_SymbolInformation.enclosingSymbol`) | Already pinned; generated bindings verified at `Scip.pb.swift` [VERIFIED: `Sources/scip-swift/Generated/Scip.pb.swift:1418-1438, 1509, 2010-2070`] |
| swift-argument-parser | 1.8.2 | CLI framework (no new flags needed for Phase 1) | Already pinned; no changes needed |

### Supporting

No supporting libraries needed. Phase 1 is pure mapping enrichment.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| IndexStoreDB relations API | SwiftSyntax for relationship extraction | Heavyweight dependency; IndexStoreDB already provides the data — no need for AST parsing |
| Kind/name-based signature reconstruction | Source-file parsing for full signatures | Violates the compiler-as-index-source invariant; deferred to v1.0+ per roadmap |
| `isSystem` for external classification | Keep referenced-but-undefined heuristic | Heuristic misclassifies project-internal cross-module symbols; `isSystem` is authoritative |

**Installation:**
```bash
# No new packages to install. All dependencies already resolved.
swift build  # verify current build passes before starting Phase 1
```

**Version verification:** No version checks needed — Phase 1 uses only APIs already present in pinned versions. Verified by reading the checked-out source.

## Package Legitimacy Audit

Phase 1 installs **zero** external packages. No audit needed.

## Architecture Patterns

### System Architecture Diagram

```
                        ┌─────────────────────────┐
                        │   SCIPIndexBuilder       │
                        │   .build()               │
                        └──────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   For each .swift file:     │
                    │   makeDocument()            │
                    └──────────────┬──────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
          ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│ Occurrence Loop │───▶│ NEW: Read            │    │ NEW: Read         │
│ (existing)      │    │ occurrence.relations │    │ symbol.properties │
│                 │    │ (currently discarded)│    │ (for .unitTest)   │
└────────┬────────┘    └──────────┬──────────┘    └────────┬─────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│ SymbolRole      │    │ RelationshipMapping │    │ SymbolRole       │
│ Mapping         │    │ (NEW mapper)        │    │ Mapping          │
│ (EXTENDED)      │    │ .baseOf/.overrideOf │    │ (EXTENDED)       │
│ +ForwardDef     │    │  → is_implementation│    │ +Test bit        │
│ +Test           │    │ .childOf            │    │                  │
│ +Generated      │    │  → enclosing_symbol │    │                  │
└────────┬────────┘    └──────────┬──────────┘    └────────┬─────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Scip_SymbolInformation                             │
│  .symbol (existing)                                                   │
│  .displayName (existing)                                              │
│  .kind (existing)                                                     │
│  .symbolRoles (EXTENDED with new bits)                                │
│  .relationships (NEW — populated from relations)                      │
│  .enclosingSymbol (NEW — populated from .childOf)                     │
│  .signatureDocumentation (NEW — populated from kind/subKind/name)     │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Scip_Document → Scip_Index                         │
│                                                                       │
│  NEW: external_symbols computed using SymbolLocation.isSystem        │
│       instead of referenced-but-undefined heuristic                  │
│                                                                       │
│  NEW: Cross-document relationship accumulation                       │
│       (relationships may target symbols in other files)              │
└─────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
Sources/scip-swift/SCIPMapping/
├── SCIPIndexBuilder.swift         # MODIFIED — reads relations, properties, isSystem
├── SCIPSymbolFormatter.swift      # UNCHANGED — symbol string formatting (reused by relationships)
├── SymbolKindMapping.swift        # UNCHANGED (kind mapping already covers what signatures need)
├── SymbolRoleMapping.swift        # EXTENDED — add ForwardDefinition, Test, Generated bits
├── PositionMapping.swift          # UNCHANGED
├── RelationshipMapping.swift      # NEW — SymbolRelation[] → Scip_Relationship[]
└── SignatureMapping.swift         # NEW — Symbol → Scip_Signature?

Tests/scip-swiftTests/
├── RelationshipMappingTests.swift # NEW (TEST-02)
├── SymbolRoleMappingTests.swift   # EXTENDED (TEST-03)
├── SignatureMappingTests.swift    # NEW
├── SCIPSymbolFormatterTests.swift # UNCHANGED
├── SymbolKindMappingTests.swift   # UNCHANGED
└── IntegrationTests.swift         # EXTENDED — verify relationships in fixture output

Fixtures/
├── MiniSwiftPackage/              # EXISTING — simple struct (no inheritance)
└── RelationSpikeFixture/          # NEW (META-06) — inheritance/conformance/override patterns
```

### Pattern 1: RelationshipMapping (New Stateless Mapper)

**What:** Maps IndexStoreDB `SymbolRelation` array to SCIP `Scip_Relationship` array
**When to use:** Inside `makeDocument()` for every occurrence with `.definition` role
**Key constraint:** Every `Relationship.symbol` must reference a symbol that exists in the index (documents + external_symbols), or `scip lint` errors with `missingSymbolInRelationshipError` [VERIFIED: `cmd/scip/lint.go:addRelationship()` — `if _, ok := st.extSyms[rel.Symbol]; !ok { if _, ok := st.localSymsMap[rel.Symbol]; !ok { return missingSymbolInRelationshipError{...} } }`]

```swift
// Sources/scip-swift/SCIPMapping/RelationshipMapping.swift
// Source: mapping table validated against scip.proto:465-516 TypeScript example
import IndexStoreDB

enum RelationshipMapping {
    /// Maps IndexStoreDB SymbolRelation[] to SCIP Relationship[].
    /// Only relations with roles that have SCIP equivalents are emitted.
    /// .childOf is excluded — it maps to enclosing_symbol, not a Relationship.
    static func scipRelationships(
        for relations: [SymbolRelation],
        symbolFormatter: (Symbol) -> String
    ) -> [Scip_Relationship] {
        relations.compactMap { relation in
            guard !relation.roles.contains(.childOf) else { return nil }

            var rel = Scip_Relationship()
            rel.symbol = symbolFormatter(relation.symbol)

            // .baseOf / .extendedBy → is_implementation (enables "Find implementations")
            // .overrideOf → is_reference + is_implementation (groups overrides with base for both queries)
            // .specializationOf → is_implementation (generic specialization is an implementation)
            if relation.roles.contains(.baseOf) || relation.roles.contains(.extendedBy) || relation.roles.contains(.specializationOf) {
                rel.isImplementation = true
            }
            if relation.roles.contains(.overrideOf) {
                rel.isReference = true
                rel.isImplementation = true
            }

            guard rel.isImplementation || rel.isReference || rel.isTypeDefinition || rel.isDefinition else {
                return nil
            }
            return rel
        }
    }
}
```

### Relationship Role Mapping Table

The IndexStoreDB relation roles and their SCIP `Relationship` field mappings, validated against the proto's own TypeScript example at `scip.proto:465-516`:

| IndexStoreDB Relation Role | Role Direction | SCIP Field(s) | Rationale |
|----------------------------|----------------|---------------|-----------|
| `.overrideOf` | occurrence = overriding method, relation = overridden method | `is_reference = true, is_implementation = true` | Proto example: `Dog#sound()` has `{symbol: "Animal#sound()", is_implementation: true, is_reference: true}` — overrides group with base for both Find References and Find Implementations [CITED: `scip.proto:478-482`] |
| `.baseOf` | **AMBIGUOUS — SPIKE MUST RESOLVE** | `is_implementation = true` (if on derived) or reverse-lookup needed (if on base) | Proto example: `Dog#` has `{symbol: "Animal#", is_implementation: true}` (NOT `is_reference`) — "Find references" on Animal should NOT return Dog; only "Find implementations" should [CITED: `scip.proto:475-476, 496-500`] |
| `.extendedBy` | **AMBIGUOUS — SPIKE MUST RESOLVE** | `is_implementation = true` (if on extended type) | Protocol conformance via extension; same semantics as `.baseOf` |
| `.specializationOf` | occurrence = specialization, relation = generic origin | `is_implementation = true` | Generic specialization is an implementation of the generic |
| `.childOf` | occurrence = child, relation = parent | → `enclosing_symbol` (NOT a Relationship) | Structural containment, not inheritance. Sets `Scip_SymbolInformation.enclosingSymbol` |
| `.calledBy` / `.receivedBy` | — | **DROP** | No SCIP call-hierarchy bit exists (spec limitation) |
| `.accessorOf` | occurrence = accessor, relation = property | **DROP** | Low value for v0.2.0; getters/setters relating to properties |
| `.containedBy` | — | **DROP** | Lexical containment; redundant with `.childOf` |
| `.ibTypeOf` | — | **DROP** | IBOutlet; irrelevant for Swift CLI tools |

**The `.baseOf` direction ambiguity is the core META-06 spike question.** The role name `.baseOf` is semantically ambiguous:
- **Interpretation A:** "the occurrence's symbol's base IS the relation's symbol" → B.baseOf means B has base A (correct direction for SCIP — relationship goes on B)
- **Interpretation B:** "the occurrence's symbol IS a base OF the relation's symbol" → A.baseOf means A is base of B (wrong direction — need reverse lookup)

The spike resolves this empirically. See Spike Design section.

### Pattern 2: Extended SymbolRoleMapping

**What:** Adds `ForwardDefinition`, `Test`, and `Generated` bits
**When to use:** Same call site as current `scipRoles(for:)`, but signature changes to accept `Symbol` for property access

```swift
// Sources/scip-swift/SCIPMapping/SymbolRoleMapping.swift (EXTENDED)
import IndexStoreDB

enum SymbolRoleMapping {
    // Signature CHANGE: now takes Symbol to access SymbolProperty
    static func scipRoles(for indexStoreRoles: SymbolRole, symbol: Symbol) -> Int32 {
        var roles: Int32 = 0
        if indexStoreRoles.contains(.definition) {
            roles |= Int32(Scip_SymbolRole.definition.rawValue)
        }
        // NEW: ForwardDefinition for .declaration role
        // SCIP ForwardDefinition = 0x40 [VERIFIED: scip.proto:541]
        if indexStoreRoles.contains(.declaration) {
            roles |= Int32(Scip_SymbolRole.forwardDefinition.rawValue)
        }
        if indexStoreRoles.contains(.write) {
            roles |= Int32(Scip_SymbolRole.writeAccess.rawValue)
        } else if indexStoreRoles.contains(.reference) || indexStoreRoles.contains(.read) {
            roles |= Int32(Scip_SymbolRole.readAccess.rawValue)
        }
        // NEW: Test bit for SymbolProperty.unitTest
        // SCIP Test = 0x20 [VERIFIED: scip.proto:539]
        // SymbolProperty.unitTest verified at SymbolProperty.swift:24
        if symbol.properties.contains(.unitTest) {
            roles |= Int32(Scip_SymbolRole.test.rawValue)
        }
        return roles
    }
}
```

**IMPORTANT — `scip lint` forwardDefIsDefinitionError:** The lint source checks: `if scip.SymbolRole_Definition.Matches(occ) && scip.SymbolRole_ForwardDefinition.Matches(occ) { return forwardDefIsDefinitionError{...} }` [VERIFIED: `cmd/scip/lint.go:addOccurrence()`]. An occurrence CANNOT have both `Definition` and `ForwardDefinition` set simultaneously. The `.declaration` and `.definition` roles are mutually exclusive in IndexStoreDB (a symbol is either declared or defined at a given location), so this should not occur naturally — but the mapping code should be defensive.

**Generated code detection (META-03 partial):** IndexStoreDB does not carry a "generated" flag directly. The `Generated = 0x10` bit [VERIFIED: `scip.proto:537`] can be set heuristically based on file path patterns:
- Files under `.build/` directory (SwiftPM generated sources)
- Files with "generated" in the path name
- This is a **best-effort heuristic** — tag as `[ASSUMED]` pending spike validation

### Pattern 3: Enclosing Symbol from .childOf

**What:** Populates `Scip_SymbolInformation.enclosingSymbol` using the `.childOf` relation
**When to use:** During `makeDocument()` when building `SymbolInformation` for local symbols

```swift
// Inside makeDocument(), when processing occurrence.relations:
// .childOf relation carries the enclosing scope (parent type, containing function, module)
if let childOfRelation = occurrence.relations.first(where: { $0.roles.contains(.childOf) }) {
    let enclosingUSR = childOfRelation.symbol.usr
    let enclosingModuleName = occurrence.location.moduleName
    // Use the same formatter as global symbols — enclosing symbols are non-local
    symbolInformation.enclosingSymbol = SCIPSymbolFormatter.globalSymbolString(
        packageManager: buildToolName,
        moduleName: enclosingModuleName,
        usr: enclosingUSR
    )
}
```

**Constraint:** The `enclosingSymbol` value must be a valid SCIP symbol string that exists in the index. If the enclosing symbol is a local itself, this creates a chain. The proto says `enclosing_symbol` is "primarily for local symbols" [CITED: `scip.proto:448-463`], so only set it for symbols with `.local` property.

### Pattern 4: isSystem External Symbol Classification

**What:** Replaces the referenced-but-undefined heuristic with `SymbolLocation.isSystem`
**When to use:** In `build()` post-processing and/or `makeDocument()` tracking

```swift
// Current heuristic (SCIPIndexBuilder.swift:41-43):
// index.externalSymbols = referencedSymbols.values
//   .filter { !definedSymbolStrings.contains($0.symbol) }

// New approach: use SymbolLocation.isSystem to classify
// isSystem verified at SymbolLocation.swift:24 — marks Swift stdlib/system framework occurrences
// during occurrence processing, track system vs non-system referenced symbols:
if occurrence.location.isSystem && !occurrence.roles.contains(.definition) {
    systemReferencedSymbols[symbolString] = symbolInformation
} else if !isLocal && referencedSymbols[symbolString] == nil {
    referencedSymbols[symbolString] = symbolInformation
}

// Post-processing:
index.externalSymbols = systemReferencedSymbols.values
    .filter { !definedSymbolStrings.contains($0.symbol) }
    .sorted { $0.symbol < $1.symbol }
```

### Pattern 5: SignatureMapping (New Stateless Mapper)

**What:** Reconstructs minimal Swift signatures from `Symbol.kind`/`subKind`/`name`
**When to use:** When building `SymbolInformation` for definition occurrences

```swift
// Sources/scip-swift/SCIPMapping/SignatureMapping.swift
import IndexStoreDB

enum SignatureMapping {
    static func signature(for symbol: Symbol) -> Scip_Signature? {
        guard let prefix = declarationPrefix(for: symbol) else { return nil }

        var sig = Scip_Signature()
        sig.language = "swift"
        sig.text = "\(prefix) \(symbol.name)"
        return sig
    }

    private static func declarationPrefix(for symbol: Symbol) -> String? {
        switch symbol.kind {
        case .instanceMethod, .classMethod, .staticMethod:
            return symbol.kind == .instanceMethod ? "func" : "static func"
        case .function:
            return "func"
        case .instanceProperty:
            return "var"
        case .classProperty, .staticProperty:
            return "static var"
        case .class:
            return "class"
        case .struct:
            return "struct"
        case .enum:
            return "enum"
        case .protocol:
            return "protocol"
        case .extension:
            return "extension"
        case .typealias:
            return "typealias"
        case .variable:
            return "var"
        case .field:
            return "let"
        case .constructor:
            return "init"
        case .parameter:
            return nil  // parameters don't get standalone signatures
        case .module:
            return nil
        default:
            return nil
        }
    }
}
```

**Limitation:** This produces a minimal signature (`func greet()`, `var name`, `class Greeter`) without parameter types or return types. Full signatures need source parsing (deferred to v1.0+). This is an improvement over the current empty state. The `Symbol.name` field from IndexStoreDB includes argument labels for methods (e.g., `greet(name:)`), so the signature will be `func greet(name:)` — more useful than just `func greet`.

### Anti-Patterns to Avoid

- **Setting both is_reference and is_implementation on ALL relationships:** The proto example explicitly shows `Dog#` has `is_implementation: true` but NOT `is_reference` for class inheritance. Setting `is_reference` on inheritance relationships causes "Find references" on a protocol to return ALL conforming types — usually wrong. Only method overrides should have both bits.

- **Emitting a Relationship whose target symbol doesn't exist in the index:** `scip lint` errors with `missingSymbolInRelationshipError`. Every `Relationship.symbol` must exist either in a document's `symbols` or in `external_symbols`. This requires either: (a) only emitting relationships to symbols defined in the same document, or (b) a cross-document accumulation pass.

- **Setting ForwardDefinition AND Definition on the same occurrence:** `scip lint` errors with `forwardDefIsDefinitionError`. These are mutually exclusive — a location is either a definition or a forward declaration.

- **Parsing source files for signatures:** Violates the compiler-as-index-source invariant. Use IndexStoreDB `Symbol` data only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Relationship target resolution | Custom cross-file symbol lookup | IndexStoreDB `occurrences(relatedToUSR:roles:)` | Already provides reverse-relation queries [VERIFIED: `IndexStoreDB.swift:226-232`] |
| Test symbol detection | Name-based heuristics (`*Test`, `*Tests`) | `SymbolProperty.unitTest` | Compiler-authoritative; catches `@Test` macros and `XCTestCase` subclasses [VERIFIED: `SymbolProperty.swift:24`] |
| System symbol classification | Path/module-name heuristics | `SymbolLocation.isSystem` | Compiler-authoritative; marks actual stdlib/framework occurrences [VERIFIED: `SymbolLocation.swift:24`] |
| Symbol string formatting for relation targets | Custom formatter | `SCIPSymbolFormatter.globalSymbolString()` | Already handles USR escaping, module name, package manager fields |

**Key insight:** IndexStoreDB provides authoritative data for everything this phase needs. The entire phase is mapping existing data to SCIP fields — no data acquisition, no parsing, no heuristics (except Generated code detection).

## Runtime State Inventory

> Phase 1 is a **greenfield enrichment** phase — it adds new mapping logic and new output fields. No rename, refactor, or migration is involved.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 1 adds new fields to existing protobuf output | None |
| Live service config | None — no external services | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | None — no build artifact changes | None |

## Common Pitfalls

### Pitfall 1: Relationship booleans set incorrectly (HIGH severity)

**What goes wrong:** Setting `is_reference = true` on inheritance/conformance relationships causes "Find references" on a protocol to return ALL conforming types. The proto's TypeScript example is explicit: `Dog#` has `{symbol: "Animal#", is_implementation: true}` but NOT `is_reference` [CITED: `scip.proto:475-476, 496-500`].

**Why it happens:** IndexStoreDB relation roles don't map 1:1 to SCIP's 4 booleans. Without the proto example as a reference, it's tempting to set both flags "to be safe."

**How to avoid:** Use the mapping table above. Only `.overrideOf` gets both `is_reference` and `is_implementation`. `.baseOf`/`.extendedBy`/`.specializationOf` get `is_implementation` ONLY.

**Warning signs:** "Find references" on a protocol returns all conforming types in Sourcegraph.

### Pitfall 2: Relationship target symbols missing from index (HIGH severity)

**What goes wrong:** `scip lint` errors: `error: symbol 'X' (#1) (in symbols for file Y) has a relationship to 'Z' (#2), but couldn't find #2 in external symbols or some other document` [VERIFIED: `cmd/scip/lint.go` — `missingSymbolInRelationshipError`].

**Why it happens:** If class B in file2.swift has a relationship to class A in file1.swift, and the relationship is emitted on B's SymbolInformation, the target A must exist in the index. If A's definition occurrence was processed but its SymbolInformation is in a different document, the target resolves. But if A is a system/external symbol, it must be in `external_symbols`.

**How to avoid:** Two strategies:
1. **Same-document only:** Only emit relationships where both symbols are defined in the same document (simpler, less complete).
2. **Cross-document accumulation:** Maintain a global map of all SymbolInformation, emit relationships in a post-processing pass after all documents are processed (more complete, more complex).

**Warning signs:** `scip lint` fails with `missingSymbolInRelationshipError` after adding relationship mapping.

### Pitfall 3: .baseOf relation direction is wrong (HIGH severity — this is the META-06 spike risk)

**What goes wrong:** If `.baseOf` means "occurrence IS a base OF the relation" (interpretation B), then mapping it directly produces relationships on the BASE class pointing to DERIVED classes — backwards from what SCIP expects. "Find implementations" on a base class would return nothing.

**Why it happens:** The role name `.baseOf` is semantically ambiguous (see mapping table above).

**How to avoid:** Run the META-06 spike FIRST. If interpretation B is correct, use `occurrences(relatedToUSR:roles:)` [VERIFIED: `IndexStoreDB.swift:226-232`] for reverse lookup, or reverse-map: when processing A's occurrence with `.baseOf` B, create a relationship on B (not A).

**Warning signs:** Relationships exist but "Find implementations" returns nothing; relationships point from base to derived instead of derived to base.

### Pitfall 4: ForwardDefinition + Definition collision (MEDIUM severity)

**What goes wrong:** `scip lint` errors: `error: forward declaration for X at Y @ Z was marked as definition` [VERIFIED: `cmd/scip/lint.go` — `forwardDefIsDefinitionError`].

**Why it happens:** If the IndexStoreDB occurrence has both `.declaration` and `.definition` roles (shouldn't happen, but defensive coding matters), the mapping sets both `ForwardDefinition` and `Definition` bits.

**How to avoid:** The roles should be mutually exclusive, but add a guard: only set `ForwardDefinition` if `.definition` is NOT also present.

### Pitfall 5: SignatureMapping produces non-useful output (LOW severity)

**What goes wrong:** Signatures like `func greet(name:)` are better than nothing but lack return types and parameter types, making hover tooltips only marginally useful.

**Why it happens:** IndexStoreDB `Symbol` carries kind and name but not full type information. Full signatures need source parsing.

**How to avoid:** Accept the limitation for v0.2.0. The `Symbol.name` field includes argument labels for methods (e.g., `greet(name:)`), so the output is more useful than bare names. Document the limitation.

## META-06 Spike Design: Validating Swift Relation Population Depth

### Objective

Empirically determine:
1. **Whether** the Swift compiler populates `occurrence.relations` for inheritance, conformance, and override patterns
2. **Which direction** the relation roles flow (base→derived vs derived→base)
3. **How deep** the relations go (just direct parent, or full hierarchy)
4. **What roles** are actually emitted for each pattern

### Spike Fixture Structure

Create `Fixtures/RelationSpikeFixture/` — a minimal SwiftPM package with targeted patterns:

```
Fixtures/RelationSpikeFixture/
├── Package.swift
└── Sources/
    └── RelationSpike/
        └── Spike.swift
```

**`Spike.swift` — patterns to test:**

```swift
// Pattern 1: Class inheritance
class Animal {
    func makeSound() -> String { "" }
}
class Dog: Animal {
    override func makeSound() -> String { "Woof" }
}

// Pattern 2: Protocol conformance
protocol Greetable {
    func greet() -> String
}
struct Greeter: Greetable {
    func greet() -> String { "Hello" }
}

// Pattern 3: Protocol conformance via extension
extension Dog: Greetable {
    func greet() -> String { "Woof hello" }
}

// Pattern 4: Protocol inheritance
protocol Drawable {
    func draw()
}
protocol Shape: Drawable {
    var area: Double { get }
}

// Pattern 5: Local variable with enclosing scope
func outerFunction() {
    let localValue = 42
    print(localValue)
}
```

### Spike Methodology

**Step 1: Build with indexing enabled**

```bash
cd Fixtures/RelationSpikeFixture
swift build --enable-index-store
# Find the index store path
INDEX_STORE=$(find .build -path "*/index/store" -type d | head -1)
```

**Step 2: Open IndexStoreDB and dump occurrences with relations**

Write a temporary diagnostic script (or test) that:
1. Opens the IndexStoreDB at the build output path
2. Calls `symbolOccurrences(inFilePath:)` for `Spike.swift`
3. For each occurrence, prints: symbol USR, symbol name, roles, and ALL relations (relation symbol USR, relation symbol name, relation roles)

```swift
// Spike diagnostic test pattern
@Test("META-06: Dump relation population for spike fixture")
func dumpRelations() throws {
    let indexStoreDB = try IndexStoreLoader.open(
        storePath: spikeIndexStorePath,
        databasePath: spikeDatabasePath
    )
    let occurrences = indexStoreDB.symbolOccurrences(inFilePath: spikeFilePath)
    for occ in occurrences.sorted() {
        print("SYMBOL: \(occ.symbol.name) [\(occ.symbol.usr)]")
        print("  ROLES: \(occ.roles)")
        print("  PROVIDER: \(occ.symbolProvider)")
        for rel in occ.relations {
            print("  RELATION: \(rel.symbol.name) [\(rel.symbol.usr)]")
            print("    REL ROLES: \(rel.roles)")
        }
    }
}
```

**Step 3: Analyze output for each pattern**

For each pattern, document:
| Pattern | Expected Symbol | Relation Found? | Role(s) | Direction |
|---------|----------------|-----------------|---------|-----------|
| `class Dog: Animal` | Dog (definition) | ? | ? | ? |
| `class Dog: Animal` | Animal (reference in `: Animal`) | ? | ? | ? |
| `override func makeSound()` | Dog.makeSound (definition) | ? | ? | ? |
| `struct Greeter: Greetable` | Greeter (definition) | ? | ? | ? |
| `extension Dog: Greetable` | Dog (in extension) | ? | ? | ? |
| `func outerFunction()` body | localValue (definition) | ? | `.childOf`? | ? |

**Step 4: Determine mapping adjustments**

Based on results:
- If `.baseOf` is on Dog's occurrence → Animal: interpretation A (direct mapping works)
- If `.baseOf` is on Animal's occurrence → Dog: interpretation B (need reverse mapping)
- If no relations for inheritance: scope reduction needed (use `occurrences(relatedToUSR:roles:)` for explicit queries)
- If `.childOf` is present on local variables: enclosing_symbol implementation confirmed
- If `symbolProvider == .swift` for all: Swift frontend populates relations

### Spike Success Criteria

- **GREEN:** Relations populated for all 5 patterns, direction is determinable → full relationship mapping scope
- **YELLOW:** Relations populated for some patterns (e.g., override but not inheritance) → partial scope, document gaps
- **RED:** Relations not populated at all → scope reduction; use `occurrences(relatedToUSR:roles:)` for explicit queries, or descope relationships to v0.3.0

### Spike Risk Mitigation

If the spike shows shallow/no relation population, the fallback is:
1. Use `indexStoreDB.occurrences(relatedToUSR: usr, roles: .baseOf)` [VERIFIED: `IndexStoreDB.swift:226-232`] for explicit reverse-relation queries during `build()` post-processing
2. This is slower (one query per defined symbol) but doesn't depend on inline relation population
3. If even this returns empty, relationships must be descoped — the Swift compiler simply doesn't emit this data via IndexStoreDB

## Code Examples

### Modified makeDocument() — Integration Point

The current `makeDocument()` loop at `SCIPIndexBuilder.swift:61-112`. Here is the modification pattern showing where each new feature slots in:

```swift
// Source: current code at SCIPIndexBuilder.swift:75-110, with additions marked
for occurrence in occurrences.sorted() {
    let symbol = occurrence.symbol
    let isLocal = symbol.properties.contains(.local)
    let symbolString = isLocal
        ? SCIPSymbolFormatter.localSymbolString(localID: localNumberer.id(forUSR: symbol.usr))
        : SCIPSymbolFormatter.globalSymbolString(
            packageManager: buildToolName,
            moduleName: occurrence.location.moduleName,
            usr: symbol.usr
          )

    var scipOccurrence = Scip_Occurrence()
    scipOccurrence.symbol = symbolString
    // CHANGED: now passes symbol for .unitTest property access
    scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles, symbol: symbol)
    scipOccurrence.singleLineRange = PositionMapping.singleLineRange(
        location: occurrence.location,
        displayName: symbol.name
    )
    document.occurrences.append(scipOccurrence)

    var symbolInformation = Scip_SymbolInformation()
    symbolInformation.symbol = symbolString
    symbolInformation.displayName = symbol.name
    symbolInformation.kind = SymbolKindMapping.scipKind(for: symbol)

    // NEW (META-05): signature documentation
    symbolInformation.signatureDocumentation = SignatureMapping.signature(for: symbol)

    // NEW (META-02): enclosing symbol from .childOf relation
    if isLocal,
       let childOfRelation = occurrence.relations.first(where: { $0.roles.contains(.childOf) }) {
        symbolInformation.enclosingSymbol = SCIPSymbolFormatter.globalSymbolString(
            packageManager: buildToolName,
            moduleName: occurrence.location.moduleName,
            usr: childOfRelation.symbol.usr
        )
    }

    // NEW (META-01): relationships from non-.childOf relations
    if occurrence.roles.contains(.definition) {
        let relationships = RelationshipMapping.scipRelationships(
            for: occurrence.relations,
            symbolFormatter: { relSymbol in
                SCIPSymbolFormatter.globalSymbolString(
                    packageManager: buildToolName,
                    moduleName: occurrence.location.moduleName,
                    usr: relSymbol.usr
                )
            }
        )
        symbolInformation.relationships = relationships
    }

    // NEW (META-04): track system vs non-system referenced symbols
    if occurrence.roles.contains(.definition) {
        definedSymbols[symbolString] = symbolInformation
    } else if !isLocal {
        if occurrence.location.isSystem {
            systemReferencedSymbols[symbolString] = symbolInformation
        } else if referencedSymbols[symbolString] == nil {
            referencedSymbols[symbolString] = symbolInformation
        }
    }
}
```

### Cross-Document Relationship Handling

Relationships may target symbols defined in other files. The `scip lint` `missingSymbolInRelationshipError` requires all targets to exist. Two approaches:

**Approach A (Simpler — same-document only):** Only emit relationships where the target symbol is defined in the same document. Drop cross-document relationships. Less complete but passes lint.

**Approach B (Complete — post-processing pass):** After all documents are processed, iterate all defined symbols and their relationships. For each relationship target not found in any document's `symbols` or in `external_symbols`, add it to `external_symbols` with minimal info (displayName, kind). This ensures all targets resolve.

**Recommendation:** Start with Approach A for the initial implementation. Upgrade to Approach B if the spike shows rich relation data.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Relationships discarded (v0.1.x) | Map to SCIP Relationship (v0.2.0) | Phase 1 | Enables "Find implementations" |
| 4 role bits mapped (v0.1.x) | 7 role bits mapped (v0.2.0) | Phase 1 | Test symbols tagged, forward decls distinguished |
| Referenced-but-undefined heuristic (v0.1.x) | isSystem classification (v0.2.0) | Phase 1 | Correct external symbol classification |
| Empty signatures (v0.1.x) | Minimal signatures from kind/name (v0.2.0) | Phase 1 | Improved hover tooltips |
| No enclosing symbol (v0.1.x) | .childOf → enclosing_symbol (v0.2.0) | Phase 1 | Local symbols in hierarchy |

**Deprecated/outdated:**
- None in Phase 1 — all additions are new, no existing behavior is removed

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `.baseOf` relation is populated by the Swift compiler for class inheritance | Relationship Role Mapping Table | Relationships won't work for inheritance; spike resolves this |
| A2 | `.overrideOf` relation is populated for `override func` methods | Relationship Role Mapping Table | Override relationships won't work; spike resolves this |
| A3 | `.childOf` relation is populated for local variables pointing to enclosing function/type | Pattern 3 | enclosing_symbol won't work; spike resolves this |
| A4 | `Symbol.name` includes argument labels for methods (e.g., `greet(name:)`) | Pattern 5 | Signatures will be less useful than expected |
| A5 | Generated code can be detected by file path heuristics (`.build/`, "generated" in path) | Pattern 2 | Generated bit may be unreliable; this is a known limitation |
| A6 | `.declaration` and `.definition` roles are mutually exclusive on a single occurrence | Pitfall 4 | ForwardDefinition + Definition collision; add defensive guard |
| A7 | Relationship targets in other files will resolve via the global symbol table | Pitfall 2 | Cross-file relationships may fail lint; need post-processing pass |

## Open Questions (RESOLVED)

1. **`.baseOf` direction (META-06 spike resolves this)**
   - What we know: The role exists in IndexStoreDB source [VERIFIED: `SymbolRole.swift:33`]
   - What's unclear: Whether it appears on the derived class's occurrence (pointing to base) or the base class's occurrence (pointing to derived)
   - RESOLVED: Spike in Plan 01-01 Task 1 determines direction empirically; RelationshipMapping mapping table adjusts per spike result

2. **Cross-document relationship target resolution**
   - What we know: `scip lint` requires all `Relationship.symbol` targets to exist in the index
   - What's unclear: Whether same-document-only filtering loses significant relationship data
   - RESOLVED: Approach A (same-document-only) adopted in Plan 01-01 Task 3; cross-document upgrade deferred unless data loss is significant

3. **Protocol method requirement vs. implementation distinction**
   - What we know: `SymbolProperty.protocolInterface` exists [VERIFIED: `SymbolProperty.swift:31`]
   - What's unclear: Whether protocol requirements should get `ForwardDefinition` and implementations get `is_implementation` relationships pointing to requirements
   - RESOLVED: Deferred to v0.2.x per plan scope; for v0.2.0, treat all protocol conformances uniformly as `is_implementation`

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift 6.2.4 toolchain | Build + test | ✓ | 6.2.4 (pinned in `.swift-version`) | — |
| Xcode (for libIndexStore.dylib) | IndexStoreDB runtime | ✓ | Current | — |
| `scip` CLI (for lint validation) | Post-build verification | ✗ | — | Install via `npm install -g @sourcegraph/scip` or download from GitHub releases |

**Missing dependencies with fallback:**
- `scip` CLI is not required for Phase 1 implementation but is needed for `scip lint` verification. If unavailable, verify manually by deserializing the `.scip` protobuf and checking relationship fields programmatically.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (built into Swift 6.2.4 toolchain) |
| Config file | None — tests use `@Suite`/`@Test` attributes directly |
| Quick run command | `swift test --filter RelationshipMapping` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| META-01 | `.baseOf`/`.overrideOf` relations map to correct SCIP Relationship fields | unit | `swift test --filter RelationshipMapping` | ❌ Wave 0 |
| META-02 | `.childOf` relation populates enclosingSymbol on local symbols | unit | `swift test --filter "enclosing"` | ❌ Wave 0 |
| META-03 | ForwardDefinition, Test, Generated bits set correctly | unit | `swift test --filter SymbolRoleMapping` | ✅ (extend existing) |
| META-04 | isSystem classification replaces heuristic for external_symbols | integration | `swift test --filter Integration` | ✅ (extend existing) |
| META-05 | Signatures populated for functions/types/properties | unit | `swift test --filter SignatureMapping` | ❌ Wave 0 |
| META-06 | Relation population depth validated for Swift | spike (diagnostic) | `swift test --filter "dumpRelations"` | ❌ Wave 0 |
| TEST-02 | RelationshipMapping unit tests pass | unit | `swift test --filter RelationshipMapping` | ❌ Wave 0 |
| TEST-03 | Extended SymbolRoleMapping unit tests pass | unit | `swift test --filter SymbolRoleMapping` | ✅ (extend existing) |

### Sampling Rate

- **Per task commit:** `swift test --filter <SpecificMapper>`
- **Per wave merge:** `swift test` (full suite including integration)
- **Phase gate:** `swift test` green + manual `scip lint` on fixture output

### Wave 0 Gaps

- [ ] `Tests/scip-swiftTests/RelationshipMappingTests.swift` — covers META-01, TEST-02
- [ ] `Tests/scip-swiftTests/SignatureMappingTests.swift` — covers META-05
- [ ] `Fixtures/RelationSpikeFixture/` — covers META-06 (spike fixture)
- [ ] Extend `Tests/scip-swiftTests/SymbolRoleMappingTests.swift` — covers META-03, TEST-03 (new test cases for ForwardDefinition, Test, Generated)
- [ ] Extend `Tests/scip-swiftTests/IntegrationTests.swift` — covers META-04 (isSystem classification verification)

## Security Domain

### Applicable ASVS Categories

Phase 1 adds mapping logic only — no new input surfaces, no authentication, no network, no secrets.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — CLI tool, no auth |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes | IndexStoreDB data is compiler-generated (trusted source); no user-controlled input enters mapping logic |
| V6 Cryptography | no | N/A |

### Known Threat Patterns for Swift CLI Mapping

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious IndexStore data | Tampering | IndexStore data comes from the local Swift compiler — not a network input. No mitigation needed for a developer CLI tool. |
| Path traversal via symbol USRs | Tampering | USRs are compiler-mangled strings used verbatim; they do not influence filesystem access. SCIPSymbolFormatter escapes them per the SCIP grammar. |

## Sources

### Primary (HIGH confidence)

- **IndexStoreDB source** (checked-out dependency, the exact code the project compiles against):
  - `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolOccurrence.swift` — `relations: [SymbolRelation]` field (line 20), `SymbolRelation` struct (lines 54-63), C callback `indexstoredb_symbol_occurrence_relations` (lines 71-78)
  - `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolRole.swift` — all 10 relation roles (lines 32-41): `.childOf`, `.baseOf`, `.overrideOf`, `.receivedBy`, `.calledBy`, `.extendedBy`, `.accessorOf`, `.containedBy`, `.ibTypeOf`, `.specializationOf`; primary roles (lines 19-28): `.declaration`, `.definition`, `.reference`, `.read`, `.write`, `.call`, `.dynamic`, `.addressOf`, `.implicit`
  - `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolProperty.swift` — `.unitTest` (line 24), `.local` (line 29), `.protocolInterface` (line 31), access control bits (lines 32-50)
  - `.build/checkouts/indexstore-db/Sources/IndexStoreDB/Symbol.swift` — `Symbol` struct with `usr`, `name`, `kind`, `subKind`, `properties`, `language` (lines 77-86); `IndexSymbolKind` enum (lines 16-44); `IndexSymbolSubKind` enum (lines 52-72)
  - `.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolLocation.swift` — `isSystem: Bool` (line 24), `moduleName` (line 21), `line`/`utf8Column` (lines 25-26)
  - `.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexStoreDB.swift` — `symbolOccurrences(inFilePath:)` (lines 465-469), `occurrences(relatedToUSR:roles:)` (lines 226-232), `forEachSymbolOccurrence(inFilePath:)` (lines 480-490)

- **SCIP proto** (vendored canonical schema):
  - `Protos/scip.proto` — `Relationship` message (lines 465-516), `SymbolRole` enum (lines 521-544), `SymbolInformation` with `enclosing_symbol` (line 449), `signature_documentation` (line 441), `Signature` message (lines 232-249)

- **scip lint Go source** (fetched live from `github.com/sourcegraph/scip`):
  - `cmd/scip/lint.go` — `missingRelationshipFlagError` (lines ~310-315), `missingSymbolInRelationshipError` (lines ~317-325), `bothLocalAndExternalSymbolError` (lines ~290-295), `forwardDefIsDefinitionError` (lines ~395-400), `addRelationship()` logic (lines ~275-305)

- **Project codebase** (ground truth for current implementation):
  - `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` — `makeDocument()` at lines 61-112, `build()` at lines 16-45, external_symbols heuristic at lines 41-43
  - `Sources/scip-swift/SCIPMapping/SymbolRoleMapping.swift` — current 4-role mapping at lines 9-20
  - `Sources/scip-swift/SCIPMapping/SymbolKindMapping.swift` — exhaustive kind switch at lines 10-69
  - `Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift` — `globalSymbolString()` at lines 23-29, `LocalSymbolNumberer` at lines 62-77
  - `Sources/scip-swift/Generated/Scip.pb.swift` — `Scip_Relationship` (lines 2010-2070), `Scip_Signature` (lines 1418-1438), `Scip_SymbolInformation.enclosingSymbol` (line 1509)

- **SCIP reference docs** (fetched live):
  - `docs/scip.md` from `github.com/sourcegraph/scip` — Relationship field semantics, SymbolRole definitions, Signature documentation

### Secondary (MEDIUM confidence)

- Prior research synthesis: `.planning/research/SUMMARY.md`, `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, `PITFALLS.md` — grounded in the same primary sources above
- `.planning/codebase/CONCERNS.md` — tech debt inventory mapping limitations to specific file/line locations

### Tertiary (needs validation)

- **Swift compiler relation population depth for Swift source code** — API confirmed from source, but empirical population depth for Swift (vs Clang) is unverified. This is the META-06 spike question. [ASSUMED] until spike results are in.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified against checked-out IndexStoreDB source; zero new dependencies
- Architecture: HIGH — current codebase mapped from actual source; target architecture follows existing patterns (enum-as-namespace, exhaustive switches, pure-function mappers)
- Relationship mapping table: MEDIUM — SCIP side is HIGH (verified from proto + lint source); IndexStoreDB side is HIGH for API existence but MEDIUM for role direction semantics (`.baseOf` ambiguity)
- Pitfalls: HIGH — all lint rules verified from Go source; recovery strategies documented
- Spike design: HIGH — concrete fixture patterns, specific queries, clear success/failure criteria

**Research date:** 2026-08-11
**Valid until:** 2026-09-11 (30 days — stable domain, no fast-moving dependencies)
