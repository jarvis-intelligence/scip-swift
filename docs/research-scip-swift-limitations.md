# Research Report: scip-swift Limitations Deep Dive

**Date:** 2026-08-07
**Method:** Code-grounded analysis (read all 5 mappers + builder + the exact `indexstore-db` checkout the project compiles against) cross-referenced against the canonical `scip.proto` and IndexStoreDB Swift API. Plus external research on SCIP spec + peer indexers (scip-typescript, scip-rust).

## Executive Summary

`scip-swift` ships a working, `scip lint`-passing pipeline, and its **documented** limitations (no demangling, approximate ranges, no call-role, USR instability, macOS-only) are all **accurate**. However, comparing the implementation against the actual IndexStoreDB API surface and the canonical `scip.proto` reveals **several material gaps the docs do not mention or understate** — most notably: the compiler's `relations` data is now mapped (override relationships only — Swift's IndexStore does not populate type-level inheritance/conformance relations; see `RelationshipMapping.swift`), `signature_documentation` is now populated via `SignatureMapping`, and only the markdown `documentation` field remains unset. These were fixable with the *existing* dependency and several have since been implemented. The single hardest, genuinely-fundamental gap is **opaque USR symbol names** (no demangling), which puts UX behind scip-typescript/scip-rust.

## Limitation taxonomy

Severity = impact on the value of the emitted index. Fixability = how tractable.

| # | Limitation | Documented? | Severity | Fixability |
|---|---|---|---|---|
| 1 | **Type-level relationships (inheritance/conformance) unavailable** — Swift's IndexStore populates relations only on member occurrences, so only override relationships are mapped | ❌ NO | **High** | **Hard** (compiler data gap) |
| 2 | **`documentation` never set (`signature_documentation` now populated via `SignatureMapping`)** | ❌ NO | **Medium** | Medium |
| 3 | **SymbolRole mapping drops declaration/implicit/test/generated** | ❌ NO | Medium | Easy |
| 4 | **Opaque USR symbol names (no demangling)** | ✅ yes | **High** | **Hard** |
| 5 | Approximate occurrence ranges (no end column) | ✅ yes | Low-Med | Hard |
| 6 | No call-site role (real proto has no Call bit) | ✅ yes | Low | **Unfixable** (spec) |
| 7 | `enclosing_symbol` never set for locals | ❌ NO *(since implemented: `SCIPIndexBuilder.swift:163-169` sets it from `.childOf` relations)* | Low | Easy |
| 8 | `isSystem` location flag ignored | ❌ NO *(since implemented: `SCIPIndexBuilder.swift:188` partitions system-referenced symbols)* | Low | Easy |
| 9 | Xcode path has no integration fixture/test | ✅ yes *(since implemented: `Tests/scip-swiftTests/XcodeIntegrationTests.swift` runs a real `xcodebuild` end-to-end)* | Medium | Easy |
| 10 | Xcodebuild passes no `-destination` (generic "My Mac") | partial | Medium | Medium |
| 11 | macOS-only host; full rebuild each run; in-memory | ✅ yes | Low | Architectural |
| 12 | USR instability across Swift toolchain versions | ✅ yes | Medium | Process-only |

---

## Confirmed documented limitations (verified accurate)

### L4 · Opaque USR symbol names — the biggest UX gap
SCIP symbol strings embed the raw compiler USR verbatim as a single escaped descriptor term:
`scip-swift swift <module> . <usr>.` → e.g. `_$s5Hello7GreeterC7sayHelloyySSF`.
- **Why it matters:** scip-typescript/scip-rust emit **human-readable descriptor chains** (`com/example/MyClass#myMethod().`) that SCIP tools render nicely in hover/breadcrumbs. scip-swift's symbols are correct (resolve fine) but unreadable to humans.
- **Fixability: HARD.** USR demangling needs the Swift compiler's mangling library (not publicly packaged for standalone use) or a custom demangler. Roadmap defers this to v1.0+ (H2 2027). `SCIPSymbolFormatter.swift:13-16` documents the rationale.
- **Note:** correctness is unaffected — USRs are compiler-guaranteed project-unique. This is purely a readability/UX limitation.

### L5 · Approximate occurrence ranges
Verified against `SymbolLocation.swift`: only `line` + `utf8Column` (1-based single anchor). **No end column exists in the API.** `PositionMapping.swift:26-28` estimates end from display-name length, stopping at `(` for compound names like `greet(name:)`. Exact ~95% of the time for simple identifiers; drifts for compound/unusual spellings. Fix would require re-lexing source files — genuinely hard.

### L6 · No call-site role — CORRECT, and unfixable
Confirmed two ways:
1. **`scip.proto` `SymbolRole` has no `Call` bit.** Verbatim enum: `Definition=0x1, Import=0x2, WriteAccess=0x4, ReadAccess=0x8, Generated=0x10, Test=0x20, ForwardDefinition=0x40`. No call.
2. **IndexStoreDB DOES have `.call` + `.dynamic`** (`SymbolRole.swift:25-26`), but there's nowhere to map them. `SymbolRoleMapping.swift:6-7` correctly drops them onto `.reference`. This is a spec limitation, not a bug.

### L11/L12 · Platform & toolchain
- macOS-only (needs Xcode + `libIndexStore.dylib` + Apple SDKs) — architectural, documented.
- `.swift-version` pins `6.2.4`; Apple doesn't guarantee USR stability across versions — documented, process-only mitigation.

---

## UNDOCUMENTED / understated limitations (research findings)

> These are the gaps the README, PDR, and roadmap do **not** surface. Each is grounded in the actual checked-out IndexStoreDB source.

### 🔴 L1 · Type-level relationships unavailable (override relationships since implemented) — HIGH severity, compiler data gap

**The finding:** IndexStoreDB's `SymbolOccurrence` carries a **`relations: [SymbolRelation]`** array (verified in `SymbolOccurrence.swift`). The compiler populates it with structural relationships via these `SymbolRole` bits (`SymbolRole.swift:30-40`):

```
.childOf  .baseOf  .overrideOf  .receivedBy  .calledBy
.extendedBy  .accessorOf  .containedBy  .specializationOf
```

There is also a dedicated query API: `occurrences(relatedToUSR:roles:)`.

**`SCIPIndexBuilder.makeDocument` now reads `occurrence.relations`** (`SCIPIndexBuilder.swift:163` for `.childOf`, `:174` for the rest) and populates `Scip_Relationship` messages via `RelationshipMapping.scipRelationships` (`SCIPIndexBuilder.swift:174-186`). However, Swift's IndexStore populates relations only on member occurrences — type-level `.baseOf`/`.extendedBy` (inheritance, protocol conformance) are not emitted for Swift, so only override relationships get mapped.

**Meanwhile, the canonical `scip.proto` has a first-class `Relationship` message** designed exactly for this:
```proto
message Relationship {
  string symbol = 1;
  bool is_reference = 2;        // "Find references" grouping
  bool is_implementation = 3;   // "Find implementations"
  bool is_type_definition = 4;  // "Go to type definition"
  bool is_definition = 5;
}
```
`SymbolInformation.relationships` is populated for non-local definitions via `RelationshipMapping` (`SCIPIndexBuilder.swift:174-186`; see `RelationshipMapping.swift` and `RelationshipMappingTests.swift`), but only with override relationships — type-level inheritance/conformance relations are absent from Swift's IndexStore data.

**Impact:** With type-level relationships missing, the emitted index **cannot power**:
- inheritance hierarchy navigation (class `B` extends `A`)
- protocol conformance links (`struct S: P`)
- method override resolution (`override func` → superclass)
- **"Find implementations"** — a headline SCIP feature
- "Go to type definition"

These are core code-intelligence features. Peer indexers (scip-typescript) populate `Relationship` (the proto's own example uses `Dog implements Animal`). The remaining gap is a compiler data limitation, not a mapping omission — the builder already maps every relation Swift's IndexStore emits.

**Fixability: MEDIUM.** Mapping is approximate (IndexStoreDB relation roles don't map 1:1 to SCIP's 4 booleans), but a reasonable mapping exists:
- `.baseOf` / `.extendedBy` → `is_implementation` (protocol/inheritance)
- `.overrideOf` → `is_reference` (overrides group with base for find-refs)
- `.childOf` → `enclosing_symbol`

### 🟠 L2 · `documentation` never set (`signature_documentation` since populated) — MEDIUM

`scip.proto` marks `SymbolInformation.documentation` (markdown, "strongly recommended") and `signature_documentation` as optional-but-recommended. `SCIPIndexBuilder.swift:159-160` now sets `signatureDocumentation` via `SignatureMapping.signature(for:)`, which reconstructs minimal Swift signatures (e.g. `func greet(name:)`) from kind/name. The markdown `documentation` field remains unset.

**Impact:** hover tooltips and API docs in SCIP consumers show the reconstructed signature but no doc comments. IndexStoreDB doesn't hand back docstrings directly; full docstrings would need source-comment parsing.

### 🟠 L3 · SymbolRole mapping: declaration/test/generated since implemented; `.implicit` still dropped — LOW residual, easy fix

`SymbolRoleMapping.scipRoles` (`SymbolRoleMapping.swift:13-29`) now maps `.definition` → `Definition`, `.write` → `WriteAccess`, `.reference`/`.read` → `ReadAccess`, and — since implemented — `.declaration` (without `.definition`) → `ForwardDefinition` (`SymbolRoleMapping.swift:23-24`), `SymbolProperty.unitTest` → `Test` (`SymbolRoleMapping.swift:26-28`), and `Generated` for generated paths (`.build`/`DerivedData`/`.index-build` components, `SCIPIndexBuilder.swift:147-149`). Still dropped:
- `.implicit` — implicit/synthesized occurrences.

**Fixability: EASY.** Pure-function additions to `SymbolRoleMapping`; exhaustive switches already enforced by convention.

### 🟡 L7 · `enclosing_symbol` never set — LOW — *since implemented*
SCIP's `enclosing_symbol` (places locals in a hierarchy) is now populated for locals from `.childOf` relations (`SCIPIndexBuilder.swift:163-169`), rendering the original finding moot.

### 🟡 L8 · `isSystem` location flag ignored — LOW — *since implemented*
`SymbolLocation.isSystem` (`SymbolLocation.swift:24`) marks Swift-stdlib / system-framework occurrences. It is now used (`SCIPIndexBuilder.swift:188`) to partition system-referenced symbols from project-referenced symbols when computing `external_symbols`, replacing the pure referenced-but-not-defined heuristic for system symbols.

### 🟠 L9/L10 · Xcode path is thin
- **L9 (documented; since implemented):** only SwiftPM had a fixture (`Fixtures/MiniSwiftPackage`); the Xcode path now has a real end-to-end integration test — `Tests/scip-swiftTests/XcodeIntegrationTests.swift` shells out to a real `xcodebuild` against `Fixtures/XcodeTestProject` and runs the full pipeline (`XcodebuildBuildRunner` → IndexStore → `SCIPIndexBuilder`), not just arg-list assertions.
- **L10 (understated):** `XcodebuildBuildRunner.arguments` (`XcodebuildBuildRunner.swift:18-38`) passes **no `-destination`**, targeting generic "My Mac". The code comment justifies this (a forced iOS destination breaks macOS-app projects; disabling signing avoids provisioning failures). Trade-off: it leans on the scheme's default SDK. iOS-specific target configurations may not all index as intended. No fixture proves the iOS case works end-to-end.

---

## Comparison: scip-swift vs peer SCIP indexers

| Capability | scip-typescript | scip-rust | **scip-swift** |
|---|---|---|---|
| Human-readable symbol names | ✅ descriptor chains | ✅ descriptor chains | ❌ raw USR |
| Inheritance/conformance relationships | ✅ `Relationship` | ✅ `Relationship` | ❌ **dropped** |
| Documentation/signatures | partial | partial | ❌ none |
| Exact occurrence ranges | ✅ | ✅ | ❌ approximated |
| Call hierarchy | ❌ (spec has no bit) | ❌ (spec) | ❌ (spec) |
| Cross-platform host | ✅ | ✅ | ❌ macOS-only |
| Index data source | compiler (tsc) | compiler (rust-analyzer) | compiler (IndexStore) |

**Takeaway:** scip-swift matches peers on *data source* (compiler index — the right call) but trails on *symbol readability*, *relationships*, and *documentation* — the first two of which are addressable.

---

## Unresolved questions

1. Does Apple's `indexstore` populate `.relations` for Swift the same way it does for Clang? (The API exists, but Swift-specific population depth should be validated empirically before committing to a relationships-mapping design.)
2. Is there a usable standalone USR-demangling path? (SwiftSyntax or a partial demangler could close the readability gap without the full compiler mangling library.)
3. Should `external_symbols` use `isSystem` for correctness, or is the referenced-but-undefined heuristic sufficient for `scip lint` + Sourcegraph in practice?

## Sources

- Canonical proto: https://github.com/scip-code/scip/blob/main/scip.proto (SymbolRole, Relationship, SymbolInformation)
- SCIP spec: https://github.com/scip-code/scip/blob/main/docs/scip.md
- IndexStoreDB (compiled-against checkout): `.build/checkouts/indexstore-db/Sources/IndexStoreDB/{SymbolRole,SymbolLocation,SymbolProperty,SymbolOccurrence,Symbol}.swift`
- IndexStoreDB query API: https://github.com/swiftlang/indexstore-db/blob/main/Sources/IndexStoreDB/IndexStoreDB.swift
- Peer indexers: https://github.com/sourcegraph/scip-typescript , rust-analyzer SCIP CLI
