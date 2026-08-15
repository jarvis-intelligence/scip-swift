# scip-swift: Code Standards

Code standards and architectural patterns observed throughout the project.

## Formatting & Style

- **Indentation**: 2 spaces (enforced throughout).
- **Naming**: 
  - Swift identifiers follow standard Swift conventions (camelCase for properties/methods, PascalCase for types).
  - File names match primary type name where applicable (e.g., `BuildError.swift` for the `BuildError` enum).
- **Line length**: No hard limit enforced; favor clarity over strict column width.

## Architectural Patterns

### 1. Enums as Stateless Namespaces

Mapping logic that has no state is organized as enums with static functions. This pattern avoids unnecessary class instantiation and clarifies intent:

**Examples**: `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`, `SCIPSymbolFormatter`, `BuildBackendDetector`.

```swift
enum SymbolKindMapping {
  static func scipKind(for symbol: Symbol) -> Scip_SymbolInformation.Kind {
    // implementation
  }
}
```

**Rationale**: These are pure functions; using an enum signals "no constructor" and avoids boilerplate static class patterns.

### 2. Protocol-Based Build Tool Abstraction

The `BuildRunner` protocol decouples the pipeline from specific build tools:

```swift
protocol BuildRunner {
  func produceIndexStore() throws -> IndexStoreBuildResult
}
```

Implementations (`SwiftPMBuildRunner`, `XcodebuildBuildRunner`) handle tool-specific logic. The main pipeline (`SCIPIndexBuilder`) is agnostic to which runner is used.

**Rationale**: Enables testing with mock runners; supports adding new build systems without modifying pipeline logic.

### 3. Custom Error Types with Actionable Messages

Errors inherit from Swift's error protocol and implement `CustomStringConvertible` to provide user-facing explanations:

```swift
enum BuildError: Error, CustomStringConvertible {
  case cannotDetectBuildSystem(repoPath: String)
  case xcodebuildSchemeRequired
  case toolNotLaunchable(tool: String, underlying: String)
  case buildFailed(tool: String, exitCode: Int32, output: String)
  case indexStoreNotProduced(expectedPath: String)
  case xcodeRequired(dylibPath: String)
  case indexStoreNotFoundForIndexOnly(expectedPath: String)

  var description: String { /* actionable, case-specific message */ }
  }
}
```

**Rationale**: Users see meaningful error context without needing to read code; errors guide troubleshooting.

### 4. Transparent Type Mapping with Enums

Symbol kind and role mappings use exhaustive enum switches to ensure all SCIP variants are handled:

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

**Rationale**: SCIP roles are a packed `Int32` bitfield; `write` is mutually exclusive with `read` (a `write`-implying role suppresses the read bit). There is no call-specific bit in `scip.proto`, so `.call` contributes nothing.

### 5. Result Structs for Data Passing

Simple data carriers use structs with explicit field names:

```swift
struct IndexStoreBuildResult {
  let indexStorePath: String
}
```

**Rationale**: Clear intent; avoids tuples that obscure meaning; immutable by default.

## Documentation Requirements

### Design Decision References

Code that implements a specific design decision should include a comment referencing the decision:

```swift
// Per design.md: "Symbol identity via USR, not demangling"
// We keep the raw compiler USR as-is for project-wide uniqueness.
let symbolString = SCIPSymbolFormatter.globalSymbolString(
  packageManager: buildToolName, moduleName: moduleName, usr: symbolUSR)
```

**Rationale**: Links implementation back to architectural decision; aids future maintenance.

### Public Function Documentation

Public methods and types should have doc comments:

```swift
/// Converts an IndexStoreDB symbol to the nearest SCIP equivalent kind.
/// - Parameter symbol: The IndexStoreDB symbol (kind and subKind).
/// - Returns: The mapped SCIP SymbolInformation.Kind.
static func scipKind(for symbol: Symbol) -> Scip_SymbolInformation.Kind
```

**Rationale**: Makes the API self-documenting; helps IDE autocompletion and documentation generation.

## Testing Conventions

### Unit Tests

- File names mirror the module being tested (e.g., `SymbolKindMappingTests.swift` for `SymbolKindMapping.swift`).
- Uses [Swift Testing](https://developer.apple.com/documentation/testing) — `@Suite` / `@Test` with string descriptions and `#expect`, **not** XCTest. Run one suite via `swift test --filter SymbolKindMapping`.

```swift
@Suite("SymbolKindMapping")
struct SymbolKindMappingTests {
  @Test("instance method maps to method")
  func methods() {
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .instanceMethod)) == .method)
  }
}
```

### Integration Tests

- `IntegrationTests.swift` runs the end-to-end pipeline against a fixture (small real SwiftPM package).
- Validates that the SCIP output is serializable and contains expected documents/symbols.

**Rationale**: Unit tests catch individual mapping errors; integration tests catch pipeline integration bugs.

## Dependency Management

### Adding New Dependencies

- Update `Package.swift` with the new dependency and its version constraint.
- Run `swift package resolve` to update `Package.resolved`.
- Document the dependency in [codebase-summary.md](./codebase-summary.md) and the relevant module's doc comment.

### Vendored Code

- `Protos/scip.proto` and `Sources/scip-swift/Generated/Scip.pb.swift` are vendored from upstream `sourcegraph/scip`.
- **Never hand-edit generated code**; regenerate via `Protos/generate.sh` if the `.proto` file changes.
- Keep `.proto` in sync with the latest upstream version; regenerate when upgrading.

## Build and Test Workflow

### Local Development

```bash
# Build
swift build

# Test
swift test

# Build release binary
swift build -c release

# Inspect the binary
file .build/release/scip-swift
```

### CI/CD

- GitHub Actions (`.github/workflows/ci.yml`) runs on every push and PR.
- Runs `swift build` and `swift test` on `macos-26` runners.
- Release binaries are cut automatically by `.github/workflows/release.yml` on `v*` tags (universal arm64 + x86_64 binary, GitHub Release, and tap formula update); both `ci.yml` and `release.yml` exist.

## Error Handling Philosophy

- **`BuildError`** is exhaustive; no generic error strings (see the seven cases above).
- **Subprocess failures** (`buildFailed`) carry the tool name, exit code, and combined stdout+stderr.
- **Missing IndexStore** (`indexStoreNotProduced`) points at the expected path and notes the common Apple-platform-on-non-macOS cause.
- **Unlaunchable tool** (`toolNotLaunchable`) reports the executable and the underlying message.

**Rationale**: Users can troubleshoot without needing to attach a debugger or read source code.

## Performance Expectations

- **Incremental builds** (when sources haven't changed) should complete in seconds.
- **First-time builds** depend on project size; no special optimization for extremely large codebases yet.
- **Memory usage** is expected to scale with the number of symbol occurrences indexed.

## Known Trade-offs

| Trade-off | Reason |
|---|---|
| Raw USR as symbol identity | Project-wide uniqueness; compiler stability; avoids demangling library dependency |
| Approximate occurrence ranges | IndexStore provides only anchor points; full range recovery requires AST query |
| No call-hierarchy role | SCIP spec limitation, not a scip-swift limitation |
| macOS-host only | Apple doesn't ship iOS SDK for Linux |

## Future Standards to Consider

- **Exact occurrence ranges** — if IndexStore API is extended or alternative symbol-location query is available.
- **Demangled symbol names** — if the Swift compiler's mangling library becomes a public API.
- **Caching** — for large projects, caching IndexStore queries to avoid re-reading the entire index.
