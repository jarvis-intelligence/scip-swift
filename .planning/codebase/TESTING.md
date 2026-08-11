---
title: TESTING
focus: quality
last_mapped_commit: 34a8c1e
---

# TESTING

**Analysis Date:** 2026-08-11

Test framework, structure, and practices for `scip-swift`.

## Framework

- **Swift Testing** (the modern `Testing` module: `@Suite`, `@Test`, `#expect`, `#require`).
- **Not XCTest** — this is a deliberate project convention called out in `CLAUDE.md`: *"Tests use
  Swift Testing (`@Suite`/`@Test` with string descriptions), not XCTest."* New tests must follow it.
- Test target: `scip-swiftTests`, declared in `Package.swift`, depends on `scip-swift`.
- Access: `@testable import scip_swift` (so internal types are reachable).

## How Tests Run

```sh
swift test                                  # all tests (unit + integration)
swift test --filter SCIPSymbolFormatter      # one @Suite by type name
swift test --filter "SymbolKindMapping/kinds with no SCIP counterpart fall back to unspecifiedKind"
```

CI (`.github/workflows/ci.yml`, `macos-26`) runs `swift build --configuration debug` then
`swift test --configuration debug` on every push/PR.

## Structure

One file per unit under `Tests/scip-swiftTests/`. Each suite is a `struct` decorated with
`@Suite("Human Name")`; each case is a `@Test("description") func`.

| File | Suite | Covers | Mocks? |
|---|---|---|---|
| `SCIPSymbolFormatterTests.swift` | `SCIPSymbolFormatter` | symbol-string escaping, backtick doubling, `escapeSpaceField`, `LocalSymbolNumberer` stability | pure unit, no mocks |
| `SymbolKindMappingTests.swift` | `SymbolKindMapping` | nominal types, methods, subscript/getter/setter subKind overrides, unspecifiedKind fallback, destructor→method | constructs `Symbol` fixtures via `makeSymbol` helper |
| `SymbolRoleMappingTests.swift` | `SymbolRoleMapping` | `.definition`/`.write`/`.reference`/`.read`, reference+write precedence, `.call` ride-along, empty roles | pure unit |
| `XcodebuildBuildRunnerTests.swift` | `XcodebuildBuildRunner arguments` | the `.arguments` computed property: project args lead, scheme/config/derivedData pass-through, index-store enabled, signing disabled, build action last | **no real xcodebuild** — asserts on the arg list only |
| `IntegrationTests.swift` | `Integration: build -> IndexStore -> SCIP` | full pipeline against `Fixtures/MiniSwiftPackage` | **no mocks** — actually shells out to `swift build` |

## Test Helpers / Patterns

- `makeSymbol(kind:subKind:)` factory in `SymbolKindMappingTests.swift` builds a `Symbol` with a
  fake USR/name so mapping functions can be exercised without IndexStoreDB.
- `value(after:in:)` helper in `XcodebuildBuildRunnerTests.swift` reads the value following a flag
  in an argument list — the pattern for asserting on CLI arg composition.
- `IntegrationTests` derives the repo root from `#filePath` and cleans up with
  `defer { try? FileManager.default.removeItem(atPath:) }` for the fixture `.build/` and the temp
  work dir.

## Mocking Strategy

- **Deliberately minimal mocking.** Unit tests target pure functions (`*Mapping`, `SCIPSymbolFormatter`)
  that need no mocks. `XcodebuildBuildRunner` is made testable by extracting `.arguments` into a
  pure computed property so tests never spawn `xcodebuild`.
- The integration test **shells out to a real `swift build`** with no mocking — per `CLAUDE.md`:
  *"no mocks"* is the stated convention for end-to-end coverage. This makes it slower than the unit
  tests, so `--filter` is recommended when iterating.

## Coverage

- **Well-covered:** the four pure mappers (`SymbolKindMapping`, `SymbolRoleMapping`,
  `PositionMapping` via the integration test, `SCIPSymbolFormatter` + `LocalSymbolNumberer`) and
  `XcodebuildBuildRunner.arguments`.
- **Covered end-to-end (SwiftPM only):** build → IndexStore → SCIP via `IntegrationTests.fullPipeline`,
  asserting 1 document, `Greeter`/`greet()`/`name` symbols, and `toolInfo.name == "scip-swift"`.
- **Not covered:** the xcodebuild path has no real-build fixture; `SwiftPMBuildRunner` and
  `SubprocessRunner` are exercised only indirectly via the integration test; `BuildBackendDetector`,
  `XcodeProjectLocator.resolveScheme`, and `ToolchainInfo.libIndexStoreDylibPath` have no direct unit
  tests. (See CONCERNS.md.)

## Fixtures

`Fixtures/MiniSwiftPackage/` — a minimal SwiftPM package (`Greeter` struct) used by
`IntegrationTests`. No Xcode-project fixture exists.

---
*quality focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
