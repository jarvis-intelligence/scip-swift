---
title: CONVENTIONS
focus: quality
last_mapped_commit: 34a8c1e
---

# CONVENTIONS

**Analysis Date:** 2026-08-11

Code style, naming, patterns, and error handling for `scip-swift`.

## Formatting & Style

- **Indentation:** 2 spaces, enforced throughout (documented in `docs/code-standards.md` and
  `CLAUDE.md`).
- **No configured formatter/SwiftFormat/.swiftformat config** in the repo — consistency is by
  convention, not tooling.
- **No hard line-length limit**; favor clarity.
- **Trailing newline** on files; no trailing whitespace.

## Naming Conventions

- **Types:** `PascalCase` (`SCIPIndexBuilder`, `BuildBackendDetector`).
- **Properties/methods/locals:** `camelCase`.
- **Enum cases:** `camelCase` (`BuildTool.swiftpm`, `.xcodebuild`).
- **Files** named after their primary type (`BuildError.swift` → `enum BuildError`).
- **Acronym capitalization** is inconsistent by intent: type acronyms are uppercase
  (`SCIPIndexBuilder`, `SCIPSymbolFormatter`) while proto-generated types use `Scip_` prefix.
  Follow the existing file's style when editing.

## Architectural Patterns

### 1. Stateless logic = `enum` namespace with `static` functions
Pure, side-effect-free mapping/utility code is an `enum` (not a `struct`/`class`) to signal "no
instance, no constructor needed." Examples: `SymbolKindMapping`, `SymbolRoleMapping`,
`PositionMapping`, `SCIPSymbolFormatter`, `BuildBackendDetector`, `SwiftFileDiscovery`,
`IndexStoreLoader`, `SubprocessRunner`, `ToolchainInfo`, `XcodeProjectLocator`.

```swift
enum SymbolKindMapping {
  static func scipKind(for symbol: Symbol) -> Scip_SymbolInformation.Kind { … }
}
```

### 2. Protocol-based build-tool abstraction
`protocol BuildRunner { func produceIndexStore() throws -> IndexStoreBuildResult }`
(`Sources/scip-swift/Build/IndexStoreBuildResult.swift`). Implementations: `SwiftPMBuildRunner`,
`XcodebuildBuildRunner`. The mapping layer depends only on the `IndexStoreBuildResult` handoff.

### 3. Exhaustive `switch` as a compile-time safety net
Kind/role/subKind mappings use exhaustive switches over IndexStoreDB enums, so adding a new enum
case is a compile error until the mapping handles it — the intended guardrail
(`SymbolKindMapping.swift`, `SymbolRoleMapping.swift`).

### 4. Testable, pure argument builders
`XcodebuildBuildRunner.arguments` is a **computed property** kept separate from
`produceIndexStore()` precisely so it can be asserted on without spawning Xcode
(`XcodebuildBuildRunnerTests.swift`).

### 5. One primary type per file
Files contain a single primary type (or a tight cluster like `SCIPSymbolFormatter` +
`LocalSymbolNumberer`). No "utils" grab-bags.

## Error Handling

- **Typed errors only** — no `String`-based errors, no `NSError`. The pipeline uses `BuildError`
  (`Sources/scip-swift/Build/BuildError.swift`), an exhaustive `enum BuildError: Error,
  CustomStringConvertible`.
- **Every case carries actionable context:** `buildFailed(tool:exitCode:output:)` embeds the
  combined stdout+stderr (last 50 lines via `combinedOutput`); `cannotDetectBuildSystem(repoPath:)`
  tells the user to pass `--build-tool`; `indexStoreNotProduced(expectedPath:)` explains the common
  Apple-platform-import cause.
- **Fail loud, fail early:** non-zero build exit → `BuildError.buildFailed`; missing IndexStore →
  `indexStoreNotProduced`; unresolvable executable → `toolNotLaunchable`. No silent partial output.
- IndexStoreDB/protobuf calls `try`-propagate; the top-level `IndexCommand.run() throws` surfaces
  them to ArgumentParser's error printing.

## Swift Idioms Used

- `@main struct …: ParsableCommand` for the CLI (`ScipSwiftCommand`).
- `ExpressibleByArgument` for CLI-enum flags (`BuildTool`, `BuildConfiguration`).
- `@Argument` / `@Option(name: .long, help:)` for CLI args.
- `Foundation.Process` + `Pipe` for subprocess execution; `DispatchGroup` for concurrent pipe reads
  (`SubprocessRunner`).
- `@unchecked Sendable` on a private `DataBox` with a documented happens-before justification
  (`SubprocessRunner.swift`) — the one deliberate concurrency-safety escape hatch.
- `(String as NSString).appendingPathComponent` / `deletingLastPathComponent` for path math.
- Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`) in tests — **not** XCTest.

## Code-Generation Boundary

- `Sources/scip-swift/Generated/Scip.pb.swift` is generated from `Protos/scip.proto` via
  `Protos/generate.sh`. It is **never hand-edited**; the file header carries no manual notice, but
  `CLAUDE.md` and `docs/code-standards.md` both forbid edits. Regenerate after proto changes.
- `Protos/scip.proto` is vendored from `sourcegraph/scip`; sync manually from upstream.

## Comments

- Doc comments (`///`) on every public-facing type and function, often citing a Requirement/task ID
  (e.g. "Requirement: Build-index generation (task 3.4)") and design-decision references
  ("Decision 3", "design.md").
- Inline `//` comments explain *why*, especially around subtle platform behavior (e.g. the
  `xcrun --find swift` rationale in `ToolchainInfo`, the code-signing rationale in
  `XcodebuildBuildRunner`).

## Testing Conventions

- New tests follow the Swift Testing pattern in `Tests/scip-swiftTests/` — `@Suite("Name") struct`
  with `@Test("description") func` and `#expect`. See TESTING.md for full detail.

---
*quality focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
