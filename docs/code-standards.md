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
  static func mapKind(_ indexstoreKind: IndexStoreDB.Symbol.Kind) -> Scip_SymbolInformation.Kind {
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
  case buildFailed(String)
  case indexStoreNotProduced(String)
  
  var description: String {
    switch self {
    case .buildFailed(let log):
      return "Build failed. Last 50 lines of output:\n\(log)"
    case .indexStoreNotProduced:
      return "Build completed but IndexStore was not produced. ..."
    }
  }
}
```

**Rationale**: Users see meaningful error context without needing to read code; errors guide troubleshooting.

### 4. Transparent Type Mapping with Enums

Symbol kind and role mappings use exhaustive enum switches to ensure all SCIP variants are handled:

```swift
enum SymbolRoleMapping {
  static func mapRoles(_ indexstoreRoles: [IndexStoreDB.SymbolRole]) -> [Scip_SymbolRole] {
    var roles: Set<Scip_SymbolRole> = []
    for role in indexstoreRoles {
      switch role {
      case .definition:
        roles.insert(.definition)
      case .reference:
        roles.insert(.reference)
      // ... additional cases
      }
    }
    return Array(roles)
  }
}
```

**Rationale**: Exhaustive switches catch additions to IndexStoreDB enums at compile time; no silent data loss.

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
let symbolString = SCIPSymbolFormatter.formatSymbol(from: symbolUSR)
```

**Rationale**: Links implementation back to architectural decision; aids future maintenance.

### Public Function Documentation

Public methods and types should have doc comments:

```swift
/// Converts an IndexStoreDB symbol kind to the nearest SCIP equivalent.
/// - Parameter kind: The IndexStoreDB symbol kind.
/// - Returns: The mapped SCIP SymbolInformation.Kind.
static func mapKind(_ kind: IndexStoreDB.Symbol.Kind) -> Scip_SymbolInformation.Kind
```

**Rationale**: Makes the API self-documenting; helps IDE autocompletion and documentation generation.

## Testing Conventions

### Unit Tests

- File names mirror the class/module being tested (e.g., `SymbolKindMappingTests.swift` for `SymbolKindMapping.swift`).
- Tests use descriptive names following `test<Scenario><ExpectedBehavior>` convention.

```swift
func testSymbolKindMapping_FunctionMapsToDotMethod() {
  let result = SymbolKindMapping.mapKind(.function)
  XCTAssertEqual(result, .method)
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
- Runs `swift build` and `swift test` on macOS-15 runners.
- Produces a release binary on tagged commits (v*).

## Error Handling Philosophy

- **BuildError** is exhaustive; no generic error strings.
- **IndexStore query failures** are propagated with context (which file, which symbol failed).
- **File system errors** (missing IndexStore, unwritable output path) are caught early with actionable messages.
- **Subprocess failures** (build command exit != 0) include the last 50 lines of stdout/stderr.

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
