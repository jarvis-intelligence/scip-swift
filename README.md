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
3. It maps each occurrence to a SCIP `Occurrence`/`SymbolInformation` and emits a `.scip` file.

## Install

Build system requires: Swift toolchain, matching the pinned version in `.swift-version`.

```sh
git clone https://github.com/phuongddx/scip-swift.git
cd scip-swift
swift build -c release
cp .build/release/scip-swift /usr/local/bin/
```

## Usage

```sh
scip-swift /path/to/your/swift/repo
# writes /path/to/your/swift/repo/index.scip
```

Options:

| Flag | Meaning |
|---|---|
| `--output <path>` | Where to write the `.scip` file (default: `<repo>/index.scip`) |
| `--build-tool swiftpm\|xcodebuild` | Override auto-detection (`Package.swift` → swiftpm, `.xcodeproj`/`.xcworkspace` → xcodebuild) |
| `--configuration debug\|release` | Forwarded to the underlying build tool (default: `debug`) |
| `--scheme <name>` | Xcode scheme to build (only for `xcodebuild`; auto-detected if the project has exactly one scheme) |
| `--version` | Print the converter version and the Swift toolchain version it was built against |

## macOS-host requirement

Indexing any repo that imports Apple-platform-only frameworks (`UIKit`, `WatchKit`, `WidgetKit`)
requires a macOS host with Xcode and the relevant SDKs — Apple does not ship the iOS SDK for Linux.
Pure Swift-package code without those imports can build (and be indexed) on Linux, but that's not
the common case for a real iOS app repo. If the underlying build command fails for this reason,
`scip-swift` surfaces it as a build failure rather than silently producing a partial index.

## Known limitations

- **Symbol identity, not full demangling**: `Symbol.scip_symbol` embeds the compiler's raw USR
  (Unified Symbol Resolution string) as an opaque, escaped identifier rather than a demangled
  namespace/type/method descriptor chain. USRs are already a compiler-guaranteed, project-wide
  unique and stable identifier, so cross-references resolve correctly — but the raw symbol string
  isn't human-readable the way `com/example/MyClass#myMethod().` is for some other SCIP indexers.
- **Approximate occurrence ranges**: IndexStoreDB (like the underlying IndexStore format) only
  records a single anchor point per occurrence — not a start/end range — so the end column is
  approximated from the symbol's display-name length. This is usually exact for simple identifiers
  and can be slightly off for compound names or unusual spellings.
- **No call-hierarchy role**: real `scip.proto`'s `SymbolRole` enum has no call-specific bit; call
  sites are marked with the same `ReadAccess`/`WriteAccess` roles as any other reference.
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
