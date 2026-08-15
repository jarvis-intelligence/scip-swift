<!-- generated-by: gsd-doc-writer -->
# Contributing to scip-swift

Thanks for your interest in improving `scip-swift`, the macOS CLI that converts a Swift
repository's IndexStoreDB compiler index into a SCIP protobuf index.

## Prerequisites

- **macOS** — this tool is macOS-only. Building and indexing Apple-platform code requires
  Xcode and the iOS SDK, and `libIndexStore.dylib` only ships on macOS. Do not try to make
  the build or tests pass on Linux.
- **Xcode** with the Swift toolchain pinned in `.swift-version` (currently `6.2.4`). USR
  stability across Swift versions is not guaranteed — build and test with the pinned
  toolchain unless you have a specific reason not to.
- **Homebrew packages for protobuf regeneration only** (not needed for normal development):
  `brew install protobuf swift-protobuf`.

## Development setup

1. Clone the repo:

   ```bash
   git clone https://github.com/jarvis-intelligence/scip-swift.git
   cd scip-swift
   ```

2. Build and run the tests:

   ```bash
   swift build
   swift test
   ```

CI (`.github/workflows/ci.yml`) runs `swift build --configuration debug` and
`swift test --configuration debug` on a macOS runner, so a clean local `swift build && swift test`
is a good proxy for CI.

## Code style

See [docs/code-standards.md](docs/code-standards.md) for the full patterns catalog. Key points:

- **2-space indentation** throughout.
- **Stateless mapping logic** lives in an `enum` namespace with `static` functions, not a
  struct or class — this signals "no constructor needed" (see `SymbolKindMapping`,
  `BuildBackendDetector` in `Sources/scip-swift/Build/`, and the other mappers in `Sources/scip-swift/SCIPMapping/`).
- **Pure, exhaustively-switched mappers** are kept side-effect-free on purpose; they act as a
  compile-time safety net if IndexStoreDB adds new enum cases. Preserve that property when
  editing them.
- **`BuildError` is exhaustive** — no generic error strings; build failures carry the full
  subprocess output.

## Testing requirements

- Tests use **Swift Testing** (`@Suite` / `@Test` with string descriptions), not XCTest.
  Follow the existing pattern in `Tests/scip-swiftTests/*.swift` for new tests.
- Run the full suite with `swift test`, or a subset with `--filter`:

  ```bash
  swift test --filter SCIPSymbolFormatter     # one @Suite by name
  swift test --filter "SymbolKindMapping/kinds with no SCIP counterpart fall back to unspecifiedKind"  # one @Test
  ```

- Integration tests (`IntegrationTests.swift`, `IncrementalIntegrationTests.swift`,
  `MultiRepoMergeIntegrationTests.swift`, `XcodeIntegrationTests.swift`) shell out to real
  `swift build` / `xcodebuild` runs against the fixtures in `Fixtures/` (e.g.
  `MiniSwiftPackage`, `XcodeTestProject`) — no mocks. They are much slower than the unit
  tests, so prefer `--filter` while iterating on a single mapper.

All tests must pass before a PR is merged — CI enforces `swift test` on every pull request.

## Protobuf regeneration policy

`Protos/scip.proto` and `Sources/scip-swift/Generated/Scip.pb.swift` are vendored from the
upstream [sourcegraph/scip](https://github.com/sourcegraph/scip) repository:

- **Never hand-edit `Generated/Scip.pb.swift`.** Regenerate it instead.
- Only regenerate after `Protos/scip.proto` changes upstream, using:

  ```bash
  brew install protobuf swift-protobuf   # once, if not already installed
  Protos/generate.sh
  ```

## Commit conventions

Commits follow the **conventional commits** format: `type(scope): subject`, e.g.
`feat(04-01): wire version field`, `fix(release): bump version to 0.2.0`,
`test(05-01): add Xcode end-to-end integration test`, `docs: ...`, `chore: ...`. Do not
include AI attribution in commit messages.

## Pull request expectations

- All tests pass (`swift test`) — CI runs build + test on macOS for every PR.
- Keep changes scoped; follow the existing conventions in
  [docs/code-standards.md](docs/code-standards.md) and `CLAUDE.md`.
- New mapping or build behavior should come with Swift Testing coverage in
  `Tests/scip-swiftTests/`; add a fixture under `Fixtures/` if a real end-to-end build is
  needed to exercise it.
- Don't add Linux CI or attempt to port the pipeline — macOS is a hard requirement.

## License

By contributing, you agree that your contributions will be licensed under the
[Apache License 2.0](LICENSE).
