# Plan 01-02 + 01-03 Summary: Role Expansion + Enclosing + isSystem + Signatures

**Date:** 2026-08-12
**Plans:** 01-02, 01-03 (Wave 2)
**Status:** DONE

## What Was Built

### Plan 01-02: META-03 + META-02 + TEST-03

**SymbolRoleMapping expansion:**
- Signature changed to `scipRoles(for:symbol:)` — accesses `SymbolProperty.unitTest`
- `.declaration` → `ForwardDefinition` (0x40) with collision guard (never set alongside `.definition`)
- `SymbolProperty.unitTest` → `Test` (0x20)
- Backwards-compatible overload preserved for callers without symbol access

**SCIPIndexBuilder changes:**
- Passes `symbol` to the role mapper for `.unitTest` property access
- `Generated` bit (0x10) set for occurrences in `.build`/`DerivedData`/`.index-build` paths
- `enclosing_symbol` populated for local symbols via `.childOf` relation

### Plan 01-03: META-04 + META-05

**SignatureMapping (new mapper):**
- `enum SignatureMapping { static func signature(for:) -> Scip_Signature? }`
- Maps `Symbol.kind` to Swift declaration prefixes: `func`, `static func`, `var`, `static var`, `class`, `struct`, `enum`, `protocol`, `extension`, `typealias`, `init`, `let`
- Returns nil for `.parameter`, `.module`, `.unknown`, and other non-declarable kinds

**SCIPIndexBuilder isSystem classification:**
- Split `referencedSymbols` into `systemReferencedSymbols` (via `SymbolLocation.isSystem`) and project-internal `referencedSymbols`
- `external_symbols` now includes both, but system symbols are correctly partitioned

## Files Created/Modified

| File | Action |
|------|--------|
| `Sources/scip-swift/SCIPMapping/SymbolRoleMapping.swift` | Modified — new signature + 3 role bits |
| `Sources/scip-swift/SCIPMapping/SignatureMapping.swift` | Created |
| `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` | Modified — enclosing, Generated, isSystem, signatures |
| `Tests/scip-swiftTests/SymbolRoleMappingTests.swift` | Modified — 4 new test cases |
| `Tests/scip-swiftTests/SignatureMappingTests.swift` | Created (12 tests) |

## Test Results

- **54 tests in 8 suites** — all passing
- 12 new SignatureMapping tests
- 4 new SymbolRoleMapping tests
- 0 regressions

## Requirements Covered

- ✅ META-02 — enclosing_symbol from .childOf
- ✅ META-03 — ForwardDefinition, Test, Generated bits
- ✅ META-04 — isSystem classification
- ✅ META-05 — signature_documentation
- ✅ TEST-03 — extended SymbolRoleMapping tests
