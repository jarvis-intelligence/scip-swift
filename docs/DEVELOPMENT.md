<!-- generated-by: gsd-doc-writer -->
# Development Guide

Everything you need to build, modify, run, and release `scip-swift` locally.

## Local setup

scip-swift is macOS-only: indexing Apple-platform imports requires Xcode + the iOS SDK, and `libIndexStore.dylib` only ships on macOS. Do not attempt to make the build/test pipeline pass on Linux.

Prerequisites:

- **macOS 14+** (Package.swift pins `platforms: [.macOS(.v14)]`)
- **Xcode** providing the Swift toolchain — the project pins **Swift 6.2.4** in `.swift-version`. USR stability across Swift versions isn't guaranteed, so don't build or test with a different toolchain without a reason. Verify with `swift --version` after selecting Xcode (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).
- No other tools are needed for day-to-day work. `protoc` + `protoc-gen-swift` are only required to regenerate protobuf bindings (see below).

Clone and build:

```sh
git clone git@github.com:jarvis-intelligence/scip-swift.git
cd scip-swift
swift build
```

The first `swift build` resolves and compiles the three dependencies declared in `Package.swift` (IndexStoreDB from `swiftlang/indexstore-db` `main` branch, swift-protobuf `>= 1.28.0`, swift-argument-parser `>= 1.5.1`), so expect it to take a few minutes.

There are no environment variables to configure for development; all options are CLI flags (see [CONFIGURATION.md](CONFIGURATION.md)).

## Project layout

A single SwiftPM executable target in `Sources/scip-swift/`, organized as a five-stage pipeline:

```text
Sources/scip-swift/
  ScipSwiftCommand.swift     # ArgumentParser root command
  Version.swift              # ScipSwiftVersion.version — must be bumped on tagged releases
  Commands/                  # IndexCommand (default subcommand), IndexManyCommand (multi-repo)
  Build/                     # BuildBackendDetector, SwiftPMBuildRunner, XcodebuildBuildRunner,
                             # SubprocessRunner, BuildError, IndexStoreBuildResult, locators
  IndexStore/                # IndexStoreLoader (opens IndexStoreDB), SwiftFileDiscovery
  SCIPMapping/               # SCIPIndexBuilder main loop + pure mappers (see below),
                             # ScipIndexMerger, RelationshipMapping, SignatureMapping
  Caching/                   # CacheStore, ContentHasher, IndexManifest (incremental index cache)
  Platform/                  # ToolchainInfo (reads .swift-version)
  Generated/                 # Scip.pb.swift — vendored, never hand-edit
Protos/                      # scip.proto (vendored from sourcegraph/scip) + generate.sh
Tests/scip-swiftTests/       # Swift Testing suites, incl. integration tests
Fixtures/                    # MiniSwiftPackage, XcodeTestProject, CrossRepo* fixtures
Formula/scip-swift.rb        # local copy of the Homebrew tap formula
```

Stage flow: **CLI dispatch** (`ScipSwiftCommand` → `Commands/IndexCommand.swift`, which owns the temp work directory) → **build orchestration** (`Build/`) → **index access** (`IndexStore/`) → **SCIP mapping** (`SCIPMapping/`) → **output** (serialized `Scip_Index` written to `.scip`, default `<repo>/index.scip`).

See [system-architecture.md](system-architecture.md) for the full component breakdown.

## Build and test commands

SwiftPM is the only build system — there is no `Makefile` and no script indirection.

| Command | Description |
|---|---|
| `swift build` | Debug build → `.build/debug/scip-swift` |
| `swift build -c release` | Release build → `.build/release/scip-swift` |
| `swift test` | Run all tests (unit + integration) |
| `swift test --filter SCIPSymbolFormatter` | Run one `@Suite` by name |
| `swift test --filter "SymbolKindMapping/kinds with no SCIP counterpart fall back to unspecifiedKind"` | Run a single `@Test` by string description |
| `Protos/generate.sh` | Regenerate protobuf bindings (see below) |

CI (`.github/workflows/ci.yml`) runs `swift build --configuration debug` and `swift test --configuration debug` on a `macos-26` runner for every push to `main` and every pull request.

### Integration test cost

`Tests/scip-swiftTests/IntegrationTests.swift` (and the other `*IntegrationTests.swift` files) shell out to a real `swift build` against `Fixtures/MiniSwiftPackage` and other fixtures — no mocks. These are much slower than the unit tests, so prefer `--filter` when iterating on a single mapper.

## Running the tool locally

After `swift build`:

```sh
# Index a repo (defaults: auto-detected backend, debug config, output <repo>/index.scip)
.build/debug/scip-swift /path/to/your-swift-repo

# Useful flags
.build/debug/scip-swift --help
.build/debug/scip-swift --version
.build/debug/scip-swift index <repo> --output custom.scip --build-tool xcodebuild --scheme MyScheme
.build/debug/scip-swift index <repo> --index-only   # skip the build, reuse an existing IndexStore
```

A fast smoke test is indexing the bundled fixture:

```sh
.build/debug/scip-swift Fixtures/MiniSwiftPackage
# Wrote N document(s) to Fixtures/MiniSwiftPackage/index.scip
```

Delete stray `index.scip` / `.scip-cache/` output from fixtures before committing.

## Code conventions

Formatting and style (full catalog in [code-standards.md](code-standards.md)):

- **2-space indentation** throughout; standard Swift naming (camelCase members, PascalCase types).
- File names match the primary type (`BuildError.swift` for the `BuildError` enum).
- No linter or formatter config is checked in — no SwiftLint/SwiftFormat/`.editorconfig`. Match the surrounding style manually; CI enforces only build + tests.
- Public functions and types get `///` doc comments.

### Enum-as-namespace pure mappers

Stateless mapping logic is an `enum` namespace with `static` functions — never a struct or class. This signals "no constructor needed" and keeps the mappers pure functions:

```swift
enum SymbolKindMapping {
  static func mapKind(_ indexstoreKind: IndexStoreDB.Symbol.Kind) -> Scip_SymbolInformation.Kind {
    // ...
  }
}
```

The mappers (`SCIPSymbolFormatter`, `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`) also switch **exhaustively** over IndexStoreDB enums on purpose: if IndexStoreDB adds a new case, the build breaks instead of silently mis-mapping.

Other patterns worth preserving:

- `BuildRunner` protocol abstraction — `SwiftPMBuildRunner` / `XcodebuildBuildRunner` implement it; `SCIPIndexBuilder` stays tool-agnostic.
- `BuildError` is exhaustive with actionable, case-specific messages — no generic error strings; `buildFailed` carries the full subprocess output.
- Simple data carriers are immutable structs (`IndexStoreBuildResult`).

### Testing conventions

Tests use **Swift Testing** (`@Suite` / `@Test` with string descriptions, `#expect`) — not XCTest. New tests go in `Tests/scip-swiftTests/`, with the file named after the module under test (`SymbolKindMappingTests.swift` for `SymbolKindMapping.swift`).

## Protobuf regeneration rules

`Protos/scip.proto` and `Sources/scip-swift/Generated/Scip.pb.swift` are vendored from upstream `sourcegraph/scip`.

- **Never hand-edit `Generated/Scip.pb.swift`** — regenerate instead.
- Only regenerate after `Protos/scip.proto` changes upstream:

```sh
brew install protobuf swift-protobuf   # one-time: needs protoc + protoc-gen-swift on PATH
Protos/generate.sh
```

The script invokes `protoc --swift_out=Sources/scip-swift/Generated --swift_opt=Visibility=Public` and renames the output to `Scip.pb.swift`. Commit both the updated `.proto` and the regenerated binding together.

## Branch and PR conventions

- Default branch: `main`.
- No branch-naming rules, PR template, or CONTRIBUTING.md are checked in — follow the existing history (short-lived feature branches merged to `main`) and keep commits focused.
- Before opening a PR, `swift build` and `swift test` must pass locally — that is exactly what CI runs on `macos-26`. If you touched a mapper, run its suite with `--filter` first, then the full suite.

## Release process

Distributed as a compiled binary plus a Homebrew tap; there is no registry publish.

1. **Bump the version** in `Sources/scip-swift/Version.swift` (`ScipSwiftVersion.version`, currently `0.2.1`). The release workflow does not check this against the tag, so it's on you to keep them in sync.
2. **Tag the release**: push a `v*` tag, e.g. `git tag v0.2.2 && git push origin v0.2.2`.
3. **`.github/workflows/release.yml`** then runs on `macos-26`:
   - Builds arm64 and x86_64 release binaries (`--triple ...-macosx14`, separate scratch paths)
   - Creates a universal binary with `lipo` and verifies `./scip-swift --version`
   - Tars it (`scip-swift-<VERSION>.tar.gz`), computes SHA256, and creates a GitHub Release via `gh release create --generate-notes`
   - Clones the Homebrew tap repo (`phuongddx/homebrew-scip-swift` — <!-- VERIFY: tap repository name and update automation scope -->) and rewrites `url` / `sha256` / `version` in `Formula/scip-swift.rb` with `sed`, then commits and pushes to the tap's `main`.

Required repo secrets: `GITHUB_TOKEN` (releases) and `HOMEBREW_TAP_TOKEN` (tap push). If the tap-update step fails, apply the same three `sed` substitutions manually in the tap repo — the tarball URL is `https://github.com/jarvis-intelligence/scip-swift/releases/download/v<VERSION>/scip-swift-<VERSION>.tar.gz`.

After a release, verify locally: `brew upgrade scip-swift && scip-swift --version`.
