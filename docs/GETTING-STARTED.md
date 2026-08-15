<!-- generated-by: gsd-doc-writer -->
# Getting Started

This guide walks you from a clean machine to a validated `.scip` index for a Swift repository.

## Prerequisites

- **macOS 14 (Sonoma) or later.** `libIndexStore.dylib` only ships on macOS, and indexing repos
  that import Apple-platform frameworks (`UIKit`, `WatchKit`, `WidgetKit`) requires Xcode + the
  iOS SDK.
- **Xcode** (from the Mac App Store) or Command Line Tools (`xcode-select --install`). Both
  `swift build` and `xcodebuild` backends need it.
- **Swift toolchain 6.2.4** — the version pinned in [`.swift-version`](../.swift-version). USR
  stability across toolchain versions isn't guaranteed by Apple; the prebuilt binaries are
  already built against it, so you only need a matching local toolchain if you build from source
  or index your own code with a different compiler.

Verify your environment:

```sh
xcode-select -p        # should print a Developer directory
xcrun --find swift     # should print a swift binary path
```

## Installation

Install the prebuilt binary via Homebrew:

```sh
brew install phuongddx/scip-swift/scip-swift
```

Alternatives:

- Prebuilt universal binaries (arm64 + x86_64) are attached to each
  [GitHub release](https://github.com/jarvis-intelligence/scip-swift/releases).
- Build from source:

```sh
git clone https://github.com/jarvis-intelligence/scip-swift.git
cd scip-swift
swift build -c release
cp .build/release/scip-swift /usr/local/bin/
```

## First index run

1. Point `scip-swift` at a Swift repo (the bare form and `index` are equivalent — `index` is the
   default subcommand):

   ```sh
   scip-swift index /path/to/your/swift/repo
   # Wrote N document(s) to /path/to/your/swift/repo/index.scip
   ```

   The first run builds the repo with indexing enabled (`swift build --enable-index-store` for
   SwiftPM, or `xcodebuild ... COMPILER_INDEX_STORE_ENABLE=YES` for Xcode projects), so expect
   it to take roughly as long as a full debug build.

2. **Where the output lands** — by default `<repo>/index.scip`. Override with `--output`:

   ```sh
   scip-swift index /path/to/your/swift/repo --output /path/to/output.scip
   ```

3. Validate the output with the Sourcegraph `scip` CLI:

   ```sh
   scip lint /path/to/your/swift/repo/index.scip
   ```

   <!-- VERIFY: install command for the Sourcegraph `scip` CLI (e.g. npm) — check https://github.com/sourcegraph/scip -->

Useful `index` flags (see [README.md](../README.md) for the full table):

| Flag | Meaning |
|---|---|
| `--output <path>` | Where to write the `.scip` file (default: `<repo>/index.scip`) |
| `--build-tool swiftpm\|xcodebuild` | Override auto-detection |
| `--configuration debug\|release` | Build configuration forwarded to the build tool (default: `debug`) |
| `--scheme <name>` | Xcode scheme (only for `xcodebuild`) |
| `--cache-dir <path>` | Enable the persistent incremental cache (default when set: `<repo>/.scip-cache`) |
| `--index-only` | Skip the build and read an existing cached IndexStore |

## Indexing multiple repos

`index-many` requires at least two repo paths and indexes each independently:

```sh
# one .scip per repo (named <repo-basename>.scip) written to --output-dir (default: .)
scip-swift index-many /path/to/repoA /path/to/repoB --output-dir out/

# merge into a single index (default: ./merged.scip)
scip-swift index-many /path/to/repoA /path/to/repoB --merge --merged-output combined.scip
```

`index-many` also accepts `--configuration` and `--cache-dir`.

## Common setup issues

### `libIndexStore.dylib was not found ...` (`BuildError.xcodeRequired`)

The tool locates `libIndexStore.dylib` via `xcrun --find swift`; if the dylib isn't at the
resolved toolchain path, you're missing Xcode or Command Line Tools (see
[BuildError.swift](../Sources/scip-swift/Build/BuildError.swift)). Fix:

1. Install Xcode from the Mac App Store, or run `xcode-select --install`.
2. If Xcode is installed but not selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
3. Verify with: `xcrun --find swift`

### `Could not detect a build system at <path>`

The repo has neither `Package.swift` nor `.xcodeproj`/`.xcworkspace`. Pass `--build-tool swiftpm`
or `--build-tool xcodebuild` explicitly.

### `xcodebuild requires --scheme <name>`

Use Xcode projects with `--scheme`, or ensure the project has exactly one scheme so it can be
auto-detected.

### `Build succeeded but no IndexStore was produced`

The code compiles neither on this host nor with these SDKs — commonly Apple-platform-only
imports on a non-macOS host, or a missing SDK. `scip-swift` fails the build rather than emitting
a partial index.

### `--index-only was used but no IndexStore was found`

`--index-only` reads a previously cached IndexStore; run `scip-swift` once without `--index-only`
(and with the same `--cache-dir`, if you passed one) to build and cache it first.

### Wrong toolchain

Building from source or indexing with a Swift toolchain other than the pinned 6.2.4 may work in
practice but is untested and unsupported; switch toolchains before filing USR-related issues.

## Next steps

- [README.md](../README.md) — full flag reference, incremental indexing, and known limitations
- [docs/system-architecture.md](system-architecture.md) — the five-stage pipeline in detail
- [docs/CONFIGURATION.md](CONFIGURATION.md) — configuration reference
