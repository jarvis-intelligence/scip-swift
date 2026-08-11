# External Integrations

**Analysis Date:** 2026-08-11

## APIs & External Services

**Compiler / Toolchain integrations (subprocess-based, invoked per run):**

- `swift build` — builds SwiftPM repos with indexing enabled. Invoked by `SwiftPMBuildRunner.produceIndexStore()` (`Sources/scip-swift/Build/SwiftPMBuildRunner.swift:14`). Command: `swift build --configuration <c> --scratch-path <path> --enable-index-store`. Resolved via `SubprocessRunner.resolveExecutable(named: "swift")` (`Sources/scip-swift/Build/SubprocessRunner.swift:69`).
- `xcodebuild` — builds Xcode-project repos with indexing enabled. Invoked by `XcodebuildBuildRunner.produceIndexStore()` (`Sources/scip-swift/Build/XcodebuildBuildRunner.swift:41`). Flags include `COMPILER_INDEX_STORE_ENABLE=YES`, `-derivedDataPath`, and code-signing disabled (`CODE_SIGNING_ALLOWED=NO` etc. — index builds never ship/run the product). Argument list built in `XcodebuildBuildRunner.arguments` (`Sources/scip-swift/Build/XcodebuildBuildRunner.swift:18`).
- `xcrun --find swift` — locates the active toolchain so `libIndexStore.dylib` can be resolved. Called in `ToolchainInfo.libIndexStoreDylibPath()` (`Sources/scip-swift/Platform/ToolchainInfo.swift:16-19`).

  - SDK/Client: none (subprocesses spawned via `Foundation.Process`).
  - Auth: none.
  - Error surfacing: `BuildError` (`Sources/scip-swift/Build/BuildError.swift`) is exhaustive — `toolNotLaunchable`, `buildFailed` (carries last lines of combined output), `indexStoreNotProduced`, `xcodebuildSchemeRequired`, `cannotDetectBuildSystem`.

**Native library integration:**

- `libIndexStore.dylib` — Apple's compiler indexing library, loaded at runtime via `IndexStoreLibrary(dylibPath:)` (`Sources/scip-swift/IndexStore/IndexStoreLoader.swift:8`). Path resolved by `ToolchainInfo.libIndexStoreDylibPath()` (`Sources/scip-swift/Platform/ToolchainInfo.swift:16`). This is the lowest-level integration — it is the actual reader of the IndexStore binary format produced by the Swift compiler.

**SCIP / Sourcegraph ecosystem (output, not consumed at runtime):**

- The emitted `.scip` file follows the [SCIP protobuf schema](https://github.com/sourcegraph/scip), vendored at `Protos/scip.proto`. It is consumed downstream by:
  - `scip` CLI (`scip lint index.scip` validates; `scip upload` publishes)
  - Sourcegraph Cloud / on-prem via the SCIP upload API
  - SCIP-aware editor plugins (VS Code, JetBrains) for "go to definition" / "find references"
  - These are **consumers of this tool's output**, not runtime dependencies. The tool itself never calls any Sourcegraph API.

## Data Storage

**Databases:**
- IndexStoreDB (LMDB-backed key-value store). Opened per-run via `IndexStoreLoader.open(storePath:databasePath:)` (`Sources/scip-swift/IndexStore/IndexStoreLoader.swift:7`). The tool **does not own** either store — both are produced by the upstream `swift build` / `xcodebuild` step:
  - SwiftPM: `<scratch-path>/<triple>/<configuration>/index/store` (located by `SwiftPMBuildRunner.findIndexStore(...)` at `Sources/scip-swift/Build/SwiftPMBuildRunner.swift:39`).
  - Xcodebuild: `<derivedDataPath>/Index.noindex/DataStore` (`Sources/scip-swift/Build/XcodebuildBuildRunner.swift:52`).
  - The LMDB index DB is written into a per-run temp directory: `<workDirectory>/index-db` (`Sources/scip-swift/Commands/IndexCommand.swift:36`).
- Client: `IndexStoreDB` library (the `indexstore-db` SwiftPM package, with transitive `swift-lmdb`).

**File Storage:**
- Local filesystem only. All paths are POSIX paths resolved via `Foundation.FileManager` / `NSString` path APIs.
- Temporary workspace created per invocation at `$TMPDIR/scip-swift-<uuid>/` (`Sources/scip-swift/Commands/IndexCommand.swift:77`), containing `scratch/` (SwiftPM), `derived-data/` (Xcode), and `index-db/` subdirectories.
- Source discovery: `SwiftFileDiscovery.swiftFiles(underRepoPath:)` (`Sources/scip-swift/IndexStore/SwiftFileDiscovery.swift:11`) walks the repo via `FileManager.enumerator`, skipping `.build`, `.git`, `.swiftpm`, `DerivedData`, `Pods`, `.index-build`.

**Caching:**
- None. Each run rebuilds and reindexes from scratch into a fresh temp directory. No persistent index cache (noted as a future consideration in `docs/system-architecture.md`).

## Authentication & Identity

**Auth Provider:**
- None. This is a local CLI tool with no network calls, no user identity, and no auth.

## Monitoring & Observability

**Error Tracking:**
- None. Errors are Swift `Error` types, surfaced to the CLI user as stderr messages.

**Logs:**
- `print("Wrote \(index.documents.count) document(s) to \(outputPath)")` on success (`Sources/scip-swift/Commands/IndexCommand.swift:45`). No structured logging framework. `swift build` / `xcodebuild` output is captured (not streamed) and only surfaced on failure via `BuildError.buildFailed` (`Sources/scip-swift/Build/SubprocessRunner.swift:17-19` concatenates stdout+stderr because both tools write compiler diagnostics to stdout).

## CI/CD & Deployment

**Hosting:**
- N/A — local CLI tool, distributed as a compiled binary (`swift build -c release`).

**CI Pipeline:**
- GitHub Actions, single workflow `.github/workflows/ci.yml`.
- Runs on `macos-26` (provides Xcode 26 → Swift 6.2.4 toolchain).
- Triggers: push to `main`, all pull requests.
- Steps: `actions/checkout@v5` → show toolchain versions → `swift build --configuration debug` → `swift test --configuration debug`.
- No release/publish pipeline in-repo.

## Environment Configuration

**Required env vars:**
- None. The tool resolves everything it needs from the filesystem and `xcrun`/`PATH`.
- Implicit requirement: a `swift` 6.2.4 toolchain and (for Xcode repos) `xcodebuild` on PATH. `xcrun` must be functional (it manages the macOS toolchain trampoline at `/usr/bin/swift`).

**Secrets location:**
- None. No secrets are read or stored anywhere in this tool.

## Webhooks & Callbacks

**Incoming:**
- None.

**Outgoing:**
- None. The tool is fully offline after the build step (the build step itself only runs if the target repo has un-fetched dependencies; `scip-swift` does not perform network I/O directly).

## Tool Output Contract (for downstream consumers)

This is not a traditional "integration" but is the key external contract:

- **Schema:** `Protos/scip.proto` (vendored from `sourcegraph/scip`).
- **Generated bindings:** `Sources/scip-swift/Generated/Scip.pb.swift` — regenerated via `Protos/generate.sh` (requires `protoc` + `protoc-gen-swift`).
- **Output file:** binary protobuf `Scip_Index`, default `<repo>/index.scip` (`Sources/scip-swift/Commands/IndexCommand.swift:42-43`).
- **Metadata embedded:** `tool_info.name = "scip-swift"`, `tool_info.version = <converterVersion>` (`Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:48-55`), `project_root` = repo URL, `text_document_encoding = .utf8`, `position_encoding = .utf8CodeUnitOffsetFromLineStart`.
- **Known contract limitations** (documented in `README.md`): symbol strings embed the raw compiler USR opaquely (not demangled), occurrence end columns are approximated from display-name length, and there is no call-hierarchy role in `scip.proto`.

---

*Integration audit: 2026-08-11*
