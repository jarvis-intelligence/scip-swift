# Testing Patterns

**Analysis Date:** 2026-08-11

## Test Framework

**Runner:**
- Swift Testing (`@Suite` / `@Test` / `#expect` / `#require`) — **not XCTest**
- No config file — Swift Testing is built into the Swift 6.2 toolchain

**Assertion Library:**
- Swift Testing built-ins: `#expect(condition)`, `#require(optional)` (throws on nil), `#expect(value == expected)`
- No third-party assertion libraries

**Run Commands:**
```bash
swift test                                    # Run all tests (unit + integration)
swift test --filter SCIPSymbolFormatter        # Run one @Suite by name
swift test --filter "SymbolKindMapping/kinds with no SCIP counterpart fall back to unspecifiedKind"  # Run one @Test
swift test --configuration debug              # Explicit configuration (default)
```

## Test File Organization

**Location:**
- Separate `Tests/scip-swiftTests/` directory (not colocated with sources)
- One test file per module under test

**Naming:**
- `<ModuleName>Tests.swift`: `SymbolKindMappingTests.swift`, `SymbolRoleMappingTests.swift`, `SCIPSymbolFormatterTests.swift`
- Integration tests: `IntegrationTests.swift` (no `.integration` suffix distinction)
- Build runner tests: `XcodebuildBuildRunnerTests.swift`

**Structure:**
```
Tests/scip-swiftTests/
├── IntegrationTests.swift              # End-to-end pipeline test (shells out to swift build)
├── SCIPSymbolFormatterTests.swift      # Unit tests for symbol formatting + escaping
├── SymbolKindMappingTests.swift        # Unit tests for kind mapping (exhaustive)
├── SymbolRoleMappingTests.swift        # Unit tests for role bit mapping
└── XcodebuildBuildRunnerTests.swift    # Unit tests for xcodebuild argument construction
```

## Test Structure

**Suite Organization:**
```swift
import Testing

@testable import scip_swift

@Suite("SCIPSymbolFormatter")
struct SCIPSymbolFormatterTests {
  @Test("real Swift USRs contain ':' (not an identifier character), so they're backtick-escaped")
  func realUSRIsEscaped() {
    let symbol = SCIPSymbolFormatter.globalSymbolString(
      packageManager: "swiftpm",
      moduleName: "MiniSwiftPackage",
      usr: "s:16MiniSwiftPackage7GreeterV"
    )
    #expect(symbol == "scip-swift swiftpm MiniSwiftPackage . `s:16MiniSwiftPackage7GreeterV`.")
  }
}
```

**Patterns:**
- `@Suite("Human Readable Name") struct FooTests` — suite name is a display string
- `@Test("descriptive behavior statement") func testName()` — test name is a behavior description
- `@testable import scip_swift` — access to internal types
- Arrange/act/assert inline; no `given`/`when`/`then` comments
- No `setUp`/`tearDown` — each test is self-contained; `defer` blocks for cleanup (integration tests)

## Mocking

**Framework:**
- No mocking framework
- No mocks at all — tests use real implementations

**What to Mock:**
- Nothing — the project explicitly avoids mocks per `IntegrationTests.swift` doc comment: "exercises real behavior end-to-end, per project convention (no mocks)"

**What NOT to Mock:**
- Everything — build runners shell out to real `swift build`/`xcodebuild`; IndexStoreDB is opened against real build output

## Fixtures and Factories

**Test Data:**
- `Fixtures/MiniSwiftPackage/` — a real, minimal Swift package (`Package.swift` + one source file with `struct Greeter` + `func greet()`)
- Integration tests build this fixture with real `swift build`, then run the full mapping pipeline

**Factory Patterns:**
- Helper functions in test files create `Symbol` instances for unit tests:
```swift
private func makeSymbol(kind: Symbol.Kind, ...) -> Symbol {
  // construct an IndexStoreDB Symbol with test values
}
```

**Location:**
- Fixtures: `Fixtures/MiniSwiftPackage/` (committed, real Swift package)
- Factory functions: inline in test files (private helper methods)

## Coverage

**Requirements:**
- No enforced coverage target
- No coverage tooling configured
- Coverage is implicit: the 4 pure mappers each have dedicated unit test suites; the integration test exercises the full pipeline

**Configuration:**
- No `.codecov.yml`, no coverage flags in CI
- CI runs `swift test` — pass/fail is the gate

## Test Types

**Unit Tests:**
- Scope: Test individual mapper functions in isolation
- Examples: `SCIPSymbolFormatterTests` (escaping logic), `SymbolKindMappingTests` (exhaustive kind mapping), `SymbolRoleMappingTests` (role bit packing), `XcodebuildBuildRunnerTests` (argument construction)
- Speed: Fast (<1s each) — pure function calls, no I/O
- No mocking — they call static functions directly with synthetic inputs

**Integration Tests:**
- Scope: Full pipeline — build → IndexStore → SCIP serialization
- Example: `IntegrationTests.fullPipeline()` — builds `Fixtures/MiniSwiftPackage`, runs `SwiftPMBuildRunner`, opens IndexStoreDB, runs `SCIPIndexBuilder.build()`, asserts on the resulting `Scip_Index`
- Speed: Slow (~10–30s) — shells out to real `swift build`
- Assertions: document count, relative path, language, occurrence presence, display names (`Greeter`, `greet()`, `name`), metadata tool info

**E2E Tests:**
- Not separately distinguished — the integration test IS the end-to-end test
- No CLI-level testing (running the compiled `scip-swift` binary as a subprocess)

## Common Patterns

**Exhaustive Kind Mapping Tests:**
- `SymbolKindMappingTests` tests every `IndexStoreDB.Symbol.Kind` case — this is intentional to catch upstream API additions
- Each test verifies a specific kind → SCIP kind mapping

**Escaping Edge Cases:**
- `SCIPSymbolFormatterTests` tests backtick escaping, identifier-only strings, backtick doubling inside escaped identifiers — edge cases of the SCIP symbol grammar

**Xcodebuild Argument Construction:**
- `XcodebuildBuildRunnerTests` asserts on the `arguments` array without spawning Xcode — tests the pure argument-builder property separately from the subprocess execution
- This allows testing the signing-disabled / no-destination logic without a real Xcode environment

**Integration Test Cleanup:**
- `defer { try? FileManager.default.removeItem(atPath: ...) }` removes fixture `.build` and temp work directory after each run — no shared state between test runs

---

*Testing analysis: 2026-08-11*
*Update when test patterns change*
