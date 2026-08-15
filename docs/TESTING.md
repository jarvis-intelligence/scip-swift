<!-- generated-by: gsd-doc-writer -->
# Testing

This guide describes how the scip-swift test suite is organized, how to run and filter it, and how it is exercised in CI.

## Test framework and setup

Tests use **Swift Testing** (the `Testing` module with `@Suite` / `@Test`), not XCTest. Assertions use `#expect(...)` and optional unwraps use `try #require(...)`.

Before running any test:

1. Use the toolchain pinned in `.swift-version` (`6.2.4`). USR stability across Swift versions is not guaranteed, so building/testing with a different toolchain may produce different symbols.
2. macOS only — indexing Apple-platform imports requires Xcode and the iOS SDK, and `libIndexStore.dylib` only ships on macOS.
3. Run `swift build` once, or just run `swift test` (it builds first).

Tests live in `Tests/scip-swiftTests/` (single test target declared in `Package.swift`). Each file contains one `@Suite` with a string description, e.g. `@Suite("SCIPSymbolFormatter")`.

## Running tests

```bash
swift test                                  # full suite (unit + integration)
swift test --filter SymbolKindMapping       # one @Suite by name
swift test --filter SCIPSymbolFormatter     # same, by suite description string
swift test --filter "SymbolKindMapping/kinds with no SCIP counterpart fall back to unspecifiedKind"  # one @Test by string description
```

The filter matches both the Swift type name and the suite/test description strings. Integration tests shell out to real `swift build` / `xcodebuild` runs and are noticeably slower than the unit tests — prefer `--filter` when iterating on a single mapper.

## Test suite inventory

16 suites, 95 `@Test` functions total, split into two categories:

### Unit tests (no real builds)

| File | Suite | What it covers |
| --- | --- | --- |
| `CacheStoreTests.swift` | CacheStore | Incremental-indexing cache persistence |
| `ContentHasherTests.swift` | ContentHasher | File content hashing used as cache keys |
| `DylibCheckTests.swift` | Dylib Check Error | Errors when `libIndexStore.dylib` cannot be located |
| `IndexManifestTests.swift` | IndexManifest | Output index manifest bookkeeping |
| `RelationshipMappingTests.swift` | RelationshipMapping | IndexStoreDB relations → SCIP relationships |
| `ScipIndexMergerTests.swift` | ScipIndexMerger | Merging multiple `Scip_Index` outputs |
| `SCIPSymbolFormatterTests.swift` | SCIPSymbolFormatter | USR → opaque escaped SCIP symbol strings, local symbol numbering |
| `SignatureMappingTests.swift` | SignatureMapping | Symbol signatures → SCIP signature strings |
| `SymbolKindMappingTests.swift` | SymbolKindMapping | IndexStoreDB `Symbol.Kind`/subKind → SCIP kinds |
| `SymbolRoleMappingTests.swift` | SymbolRoleMapping | IndexStoreDB `SymbolRole` bits → SCIP roles |
| `XcodebuildBuildRunnerTests.swift` | XcodebuildBuildRunner arguments | Argument-vector construction for `xcodebuild` (no subprocess) |

### Integration tests (shell out to real toolchain invocations, no mocks)

| File | Suite | Fixture | What it covers |
| --- | --- | --- | --- |
| `IntegrationTests.swift` | Integration: build -> IndexStore -> SCIP | `Fixtures/MiniSwiftPackage` | Full SwiftPM pipeline: `swift build` with indexing → IndexStoreDB → `SCIPIndexBuilder` → serialized `Scip_Index` |
| `XcodeIntegrationTests.swift` | Xcode Integration | `Fixtures/XcodeTestProject` | Full Xcode pipeline: `xcodebuild` (workspace/project + scheme resolution) → SCIP index |
| `IncrementalIntegrationTests.swift` | Incremental Indexing | `Fixtures/MiniSwiftPackage` | Cache determinism: second run on unchanged fixture produces identical bytes; cache miss then hit |
| `MultiRepoMergeIntegrationTests.swift` | Multi-Repo Merge | `Fixtures/CrossRepoPackageA` + `Fixtures/CrossRepoPackageB` | Building two repos independently, merging with `ScipIndexMerger`, and validating structural invariants |
| `RelationSpikeTests.swift` | META-06: Relation Spike | `Fixtures/RelationSpikeFixture` | Empirical validation that the compiler populates `occurrence.relations` (e.g. `overrideOf` for inheritance) |

Integration tests locate the repo root from `#filePath`, build fixtures into temp directories (`NSTemporaryDirectory()` + UUID), and clean up via `defer`. `RelationSpikeTests` queries `IndexStoreDB` inline without deferred cleanup because the DB handle must outlive the temp directory it reads from.

## Fixtures

Real, buildable Swift projects under `Fixtures/` — never hand-edit the `.scip` expectations instead of the fixture, tests assert on live build output:

- `Fixtures/MiniSwiftPackage` — minimal SwiftPM package (`Greeter.swift`) used by the main and incremental pipelines
- `Fixtures/CrossRepoPackageA` / `Fixtures/CrossRepoPackageB` — two independent packages (B does not depend on A; it defines its own `Consumer` type), used for multi-repo merge validation
- `Fixtures/RelationSpikeFixture` — Swift patterns (inheritance, etc.) that exercise compiler relations
- `Fixtures/XcodeTestProject` — `.xcodeproj` project (the `.xcworkspace` is internal to the project bundle) with an SPM dependency, used by the Xcode integration path

## Writing new tests

- Add a new file to `Tests/scip-swiftTests/` following the existing pattern: `@Suite("Name")` with a string description, one suite per file.
- Use `#expect` for assertions and `try #require` for force-unwraps that should fail the test rather than crash.
- Give `@Test` functions string descriptions for filtering: `@Test("kinds with no SCIP counterpart fall back to unspecifiedKind")`.
- Mark the suite type with `@testable import scip_swift`.
- Unit tests for mapping logic should be pure-function calls (the mappers are stateless `enum` namespaces). Only shell out to real builds in the integration-style suites listed above.
- 2-space indentation, matching the rest of the codebase.

## Coverage requirements

No coverage threshold is configured (no `.codecov`, `scoverage`, or coverage flags in `Package.swift` or CI). Correctness is enforced by the unit suites plus the real-build integration suites.

## CI integration

Workflow: `.github/workflows/ci.yml` (job `build-and-test`), triggered on push to `main` and on pull requests.

- Runner: `macos-26` (ships Xcode 26 / Swift 6.2, matching the `swift-tools-version 6.2` requirement and the `.swift-version` pin) — macOS-only by design; building/indexing Apple-platform code needs the iOS SDK, which is not available on Linux.
- Steps: `actions/checkout@v5` → print `swift --version`, `xcodebuild -version`, and the pinned `.swift-version` → `swift build --configuration debug` → `swift test --configuration debug`.

## Next steps

- [system-architecture.md](system-architecture.md) — the five-stage pipeline the integration tests exercise end-to-end
- [code-standards.md](code-standards.md) — patterns catalog (stateless `enum` mappers, exhaustive switches)
- [CONFIGURATION.md](CONFIGURATION.md) — CLI options and environment behavior
