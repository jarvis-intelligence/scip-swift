# Plan 01-01 Summary: Tracer — Spike + RelationshipMapping + Wiring

**Date:** 2026-08-12
**Plan:** 01-01 (Wave 1 Tracer)
**Status:** DONE

## What Was Built

### Task 1: Spike Fixture (META-06)
Created `Fixtures/RelationSpikeFixture/` — minimal SwiftPM package with inheritance, override, conformance, and protocol patterns. Three diagnostic tests validate IndexStoreDB relation population.

**Spike findings (critical for downstream design):**
- ✅ `.overrideOf` IS populated — Dog.makeSound has a relation to Animal.makeSound
- ✅ `.childOf` IS populated — every member has a relation to its containing type
- ❌ Type-level definitions (Dog, Animal, Greeter) have **0 relations** — relations are on members only
- ❌ No `.baseOf` or `.extendedBy` at the type level — Swift's IndexStoreDB doesn't express inheritance/conformance as type-level relations
- **Implication:** Relationship mapping covers method overrides. Type-level inheritance/conformance cannot be mapped via `occurrence.relations`.

### Task 2: RelationshipMapping (META-01, TEST-02)
New pure-function mapper `Sources/scip-swift/SCIPMapping/RelationshipMapping.swift`:
- `.overrideOf` → `is_reference = true, is_implementation = true`
- `.childOf` → excluded (used for `enclosing_symbol` in Plan 01-02)
- All other roles without at least one boolean → dropped (scip lint compliance)

5 unit tests in `RelationshipMappingTests.swift` — all passing.

### Task 3: SCIPIndexBuilder Wiring (META-01)
Modified `SCIPIndexBuilder.makeDocument()` to call `RelationshipMapping.scipRelationships(for:symbolFormatter:)` on non-local definition occurrences. Relations are formatted using the same global symbol string pattern as the definition symbols.

**Verified output:** Dog.makeSound now shows `rels=1` in the dump — the override relationship is correctly emitted.

## Files Created/Modified

| File | Action |
|------|--------|
| `Fixtures/RelationSpikeFixture/Package.swift` | Created |
| `Fixtures/RelationSpikeFixture/Sources/RelationSpike/Spike.swift` | Created |
| `Tests/scip-swiftTests/RelationSpikeTests.swift` | Created (3 tests) |
| `Sources/scip-swift/SCIPMapping/RelationshipMapping.swift` | Created |
| `Tests/scip-swiftTests/RelationshipMappingTests.swift` | Created (5 tests) |
| `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` | Modified (+12 lines) |

## Test Results

- **38 tests in 7 suites** — all passing
- 5 new RelationshipMapping unit tests
- 3 spike diagnostic tests
- 30 existing tests (no regressions)

## Deviations from Plan

1. **Spike test structure changed:** The original plan used a shared `spikeFixture()` helper with `defer` cleanup. This caused `symbolOccurrences(inFilePath:)` to return empty results because the `defer` deleted the temp directory (including the index database) before the test assertions ran. Fixed by inlining the build+open+query in each test method.

2. **Relationship mapping scope narrowed:** The plan expected `.baseOf`/`.extendedBy` on type definitions. The spike proved these don't exist for Swift. The mapper correctly handles `.overrideOf` (which IS populated) and excludes `.childOf`. Type-level inheritance/conformance is not expressible with the current IndexStoreDB data.

## Requirements Covered

- ✅ META-01 (relationships) — override relations mapped
- ✅ META-06 (spike) — empirically validated Swift relation population depth and direction
- ✅ TEST-02 (RelationshipMapping tests) — 5 unit tests covering all relation role types
