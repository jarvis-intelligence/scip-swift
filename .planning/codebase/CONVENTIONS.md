# Coding Conventions

**Analysis Date:** 2026-08-11

## Naming Patterns

**Files:**
- PascalCase matching the primary type: `BuildError.swift` → `enum BuildError`, `SCIPIndexBuilder.swift` → `struct SCIPIndexBuilder`
- Acronyms fully capitalized in type-level names: `SCIPSymbolFormatter`, `SCIPIndexBuilder`
- Test files: `<ModuleName>Tests.swift` — `SymbolKindMappingTests.swift`, `SCIPSymbolFormatterTests.swift`

**Functions:**
- camelCase throughout: `produceIndexStore()`, `scipRoles(for:)`, `globalSymbolString(packageManager:moduleName:usr:)`
- Static functions on enum namespaces: `SymbolKindMapping.scipKind(for:)`, `PositionMapping.singleLineRange(location:displayName:)`
- No prefix conventions for async (no async functions exist in the codebase — pipeline is synchronous)

**Variables:**
- camelCase for locals and properties: `repoPath`, `indexStorePath`, `buildToolName`
- No UPPER_SNAKE_CASE constants (Swift convention: use `static let` with camelCase)

**Types:**
- PascalCase for all types
- `enum` for stateless mappers (no instances): `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`, `SCIPSymbolFormatter`, `BuildBackendDetector`
- `struct` for data carriers and stateful mappers: `IndexStoreBuildResult`, `SCIPIndexBuilder`, `LocalSymbolNumberer`
- `protocol` for abstractions: `BuildRunner`
- No `I` prefix on protocols; no `Impl` suffix on conformances

## Code Style

**Formatting:**
- 2-space indentation (enforced throughout, no `.swiftformat`/`.swiftlint.yml` config)
- No hard line-length limit; favor clarity
- Trailing commas in multiline collection literals
- Opening brace on the same line (`K&R` style)

**Linting:**
- No linter configured (no `.swiftlint.yml`, no `.swiftformat`, no `.editorconfig`)
- Style consistency maintained by convention and code review

## Import Organization

**Order:**
1. External packages: `import ArgumentParser`, `import Foundation`, `import IndexStoreDB`, `import Testing`
2. No internal imports (single-target module — everything in `scip-swift` is accessible via `@testable import scip_swift` in tests)

**Grouping:**
- One import per line, alphabetically sorted within the external group
- No blank lines between import statements

## Error Handling

**Strategy:** Typed Swift errors via `throws`/`throw`; caught at the CLI boundary (ArgumentParser renders the error)

**Patterns:**
- Custom error enums conforming to `Error` + `CustomStringConvertible`: `BuildError` with 5 exhaustive cases
- Each case carries structured context: `BuildError.buildFailed(tool: "swift build", exitCode: 1, output: ...)` — no generic string errors
- Each case's `description` returns an actionable, user-facing message explaining what happened and how to fix it
- No `try?`, no `Result` types — errors propagate via `throws` to the top level
- Build failures include the last 50 lines of subprocess output in the error message

**Error Types:**
- `BuildError.cannotDetectBuildSystem(repoPath:)` — no Package.swift or .xcodeproj found
- `BuildError.xcodebuildSchemeRequired` — scheme couldn't be inferred
- `BuildError.toolNotLaunchable(tool:underlying:)` — executable not on PATH
- `BuildError.buildFailed(tool:exitCode:output:)` — non-zero exit from build tool
- `BuildError.indexStoreNotProduced(expectedPath:)` — build succeeded but no IndexStore

## Logging

**Framework:**
- None — just `print()` for success output
- Single line on success: `print("Wrote \(index.documents.count) document(s) to \(outputPath)")`

**Patterns:**
- No debug/trace logging — the tool is silent on success except for the final message
- Build failures surface output through `BuildError.buildFailed` (full stdout+stderr in the error description)
- No structured logging framework

## Comments

**When to Comment:**
- Every source file starts with a `///` doc comment explaining what requirement the file implements and why
- Comments explain WHY (design decisions, requirement references), never WHAT (code is self-documenting)
- Design-decision references: `/// See design.md Decision 3 / Open Questions for the full rationale.`
- Requirement references: `/// Requirement: IndexStoreDB to SCIP protobuf conversion (task 3.6)`

**Doc Comments:**
- `///` doc comments on every type and public function
- Required on all enum mappers and their static functions
- Explain the transformation, the inputs, and any approximation or limitation

**TODO Comments:**
- None in the codebase — the project tracks work via `docs/project-roadmap.md` and `docs/research-scip-swift-limitations.md`

## Function Design

**Size:**
- Small and focused — `IndexCommand.run()` (the longest function) is ~30 lines
- Complex logic extracted into named helpers: `produceIndexStore(tool:repoPath:workDirectory:)`, `makeTemporaryDirectory()`

**Parameters:**
- Up to 5 parameters for initializers (`XcodebuildBuildRunner` has 5 stored properties)
- Labels required on all parameters: `globalSymbolString(packageManager:moduleName:usr:)`, not `globalSymbolString(_:_:_:)`

**Return Values:**
- Explicit returns; early `guard` statements for preconditions
- `SCIPIndexBuilder.makeDocument()` returns `Scip_Document?` (nil if no occurrences) — optional return for "nothing to index"

## Module Design

**Type Choice Convention:**
- `enum` with `static func` = "this is a pure-function namespace, no instances ever" — the strongest signal in the codebase
- `struct` = value type for data or stateful-but-small logic
- `protocol` = abstraction boundary (`BuildRunner` is the only protocol)
- No `class` anywhere in the codebase — value semantics throughout

**Exhaustive Switches:**
- `SymbolKindMapping.scipKind(for:)` uses an exhaustive `switch` over `IndexStoreDB.Symbol.Kind` — compile-time safety net if new cases are added upstream
- `BuildError.description` uses exhaustive `switch self` — compiler enforces all cases are handled

**Vendored Code:**
- `Generated/Scip.pb.swift` is never hand-edited — regenerate from `Protos/scip.proto` via `Protos/generate.sh`
- `Protos/scip.proto` is vendored from upstream `sourcegraph/scip`

---

*Convention analysis: 2026-08-11*
*Update when patterns change*
