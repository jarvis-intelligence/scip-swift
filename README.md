<!-- generated-by: gsd-doc-writer -->
# scip-swift

A [SCIP](https://github.com/sourcegraph/scip) indexer for Swift. It converts a Swift repo's build
index into genuine `scip.proto` output — real protobuf `Index`/`Document`/`Symbol`/`Occurrence`
messages, consumable by any standard SCIP tool (the `scip` CLI, `codeintel`, Sourcegraph, editor
plugins) — by reading the same [IndexStoreDB](https://github.com/swiftlang/indexstore-db) index
that powers Xcode's own "jump to definition" and SourceKit-LSP.

## How it works

1. `scip-swift` builds your repo with indexing-while-building enabled:
   - SwiftPM repos: `swift build --enable-index-store`
   - Xcode-project repos: `xcodebuild ... COMPILER_INDEX_STORE_ENABLE=YES`
2. It reads the resulting IndexStore via `IndexStoreDB`'s `SymbolOccurrence` query API.
3. It maps each occurrence to a SCIP `Occurrence`/`SymbolInformation` — including symbol
   relationships (overrides), role bits, and minimal signatures — and emits a `.scip` file.

## Architecture

![scip-swift system architecture](docs/diagrams/system-architecture.png)

See [docs/system-architecture.md](docs/system-architecture.md) for the component-by-component
breakdown.

## Install

macOS 14 (Sonoma) or later is required.

Homebrew:

```sh
brew install phuongddx/scip-swift/scip-swift
```

Or build from source (requires a Swift toolchain matching the pinned version in
`.swift-version`):

```sh
git clone https://github.com/jarvis-intelligence/scip-swift.git
cd scip-swift
swift build -c release
cp .build/release/scip-swift /usr/local/bin/
```

Prebuilt universal binaries (arm64 + x86_64) are attached to each
[GitHub release](https://github.com/jarvis-intelligence/scip-swift/releases).

## Usage

```sh
scip-swift /path/to/your/swift/repo
# writes /path/to/your/swift/repo/index.scip
```

The `index` subcommand is equivalent — useful for tools that always pass an explicit subcommand
name (`index` is also `scip-swift`'s `defaultSubcommand`, so the bare form above dispatches to it):

```sh
scip-swift index /path/to/your/swift/repo --output /path/to/output.scip
```

Options:

| Flag | Meaning |
|---|---|
| `--output <path>` | Where to write the `.scip` file (default: `<repo>/index.scip`) |
| `--build-tool swiftpm\|xcodebuild` | Override auto-detection (`Package.swift` → swiftpm, `.xcodeproj`/`.xcworkspace` → xcodebuild) |
| `--configuration debug\|release` | Forwarded to the underlying build tool (default: `debug`) |
| `--scheme <name>` | Xcode scheme to build (only for `xcodebuild`; auto-detected if the project has exactly one scheme) |
| `--cache-dir <path>` | Directory for the incremental index cache (default: `<repo>/.scip-cache`). Passing this flag enables the persistent cache |
| `--index-only` | Skip the build step and read an existing IndexStore directly (from the cache directory) |
| `--version` | Print the converter version and the Swift toolchain version it was built against |

### Indexing multiple repos

`index-many` indexes two or more repos independently, writing one `.scip` per repo or merging
them into a single index:

```sh
# one .scip per repo, written to --output-dir (default: current directory)
scip-swift index-many /path/to/repoA /path/to/repoB --output-dir out/

# merge into a single index (default: ./merged.scip)
scip-swift index-many /path/to/repoA /path/to/repoB --merge --merged-output combined.scip
```

`index-many` supports `--configuration` and `--cache-dir` as well.

### Incremental indexing

Passing `--cache-dir` (or `--index-only`) switches the pipeline from a throwaway temp directory
to a persistent cache:

- Unchanged files reuse their previously computed `Scip_Document` (keyed by SHA256 content hash),
  so re-indexing after small edits only reprocesses what changed.
- The cache is invalidated wholesale when the Swift toolchain version, `scip-swift` version,
  indexstore-db revision, or build backend changes (recorded in `manifest.json`).
- `--index-only` reuses the already-built IndexStore under the cache directory (it does not
  rebuild), so it fails with `indexStoreNotFoundForIndexOnly` if no prior indexed build exists
  there.

## macOS-host requirement

Indexing any repo that imports Apple-platform-only frameworks (`UIKit`, `WatchKit`, `WidgetKit`)
requires a macOS host with Xcode and the relevant SDKs — Apple does not ship the iOS SDK for Linux.
Pure Swift-package code without those imports can build (and be indexed) on Linux, but that's not
the common case for a real iOS app repo. If the underlying build command fails for this reason,
`scip-swift` surfaces it as a build failure rather than silently producing a partial index.

## Known limitations

- **Symbol identity, not full demangling**: `Scip_SymbolInformation.symbol` embeds the compiler's raw USR
  (Unified Symbol Resolution string) as an opaque, escaped identifier rather than a demangled
  namespace/type/method descriptor chain. USRs are already a compiler-guaranteed, project-wide
  unique and stable identifier, so cross-references resolve correctly — but the raw symbol string
  isn't human-readable the way `com/example/MyClass#myMethod().` is for some other SCIP indexers.
- **Occurrence ranges**: IndexStoreDB (like the underlying IndexStore format) only records a
  single anchor point per occurrence — not a start/end range. The end column is the exact
  identifier-token extent from a `SwiftSyntax` parse of the file; the name-length approximation
  remains only as a fallback for regions the parser cannot recover (e.g. severely malformed
  syntax). Statically linking `SwiftSyntax`/`SwiftParser` grows the release binary from ~7 MB to
  ~24.5 MB — an accepted trade-off for this milestone (compiler-grade token extents without
  shipping a separate parser binary).
- **No call-hierarchy role**: real `scip.proto`'s `SymbolRole` enum has no call-specific bit; call
  sites are marked with the same `ReadAccess`/`WriteAccess` roles as any other reference.
- **Minimal signatures**: reconstructed signatures carry the symbol name but lack parameter and
  return types — IndexStoreDB's symbol data doesn't expose them.
- **Relationships limited to overrides**: only override relationships are mapped; IndexStoreDB's
  relation data doesn't cover the full SCIP relationship set.
- **USR stability across toolchain versions is not guaranteed by Apple.** This project pins the
  Swift toolchain version it's built and tested against (see `.swift-version`); indexing with a
  different toolchain version may be fine in practice but isn't a supported/tested configuration.

## Development

```sh
swift build
swift test
```

Regenerating the vendored SCIP protobuf bindings (only needed if `Protos/scip.proto` is updated
from upstream `sourcegraph/scip`):

```sh
brew install protobuf swift-protobuf
Protos/generate.sh
```

## License

Apache-2.0 — see [LICENSE](LICENSE).
