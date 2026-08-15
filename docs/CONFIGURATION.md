<!-- generated-by: gsd-doc-writer -->
# Configuration

scip-swift is configured entirely through CLI flags — it reads no environment variables and no config files. This page documents the `index` and `index-many` subcommands, the toolchain requirements, and the incremental cache layout.

## CLI: `index` subcommand

`index` is the default subcommand, so `scip-swift <repoPath>` and `scip-swift index <repoPath>` are equivalent. Source: `Sources/scip-swift/Commands/IndexCommand.swift`.

| Flag / Argument | Type | Default | Description |
| --- | --- | --- | --- |
| `repoPath` (positional) | path | current working directory | Path to the Swift repo to index. |
| `--output <path>` | option | `<repo>/index.scip` | Output path for the `.scip` file. |
| `--build-tool <tool>` | option | auto-detect | Build backend: `swiftpm` or `xcodebuild`. When omitted, `BuildBackendDetector` picks automatically (prefers `Package.swift` first, then falls back to `.xcworkspace`/`.xcodeproj`). |
| `--configuration <config>` | option | `debug` | Build configuration forwarded to the underlying build tool: `debug` or `release`. |
| `--scheme <name>` | option | auto-detect | Xcode scheme to build. Only used with `xcodebuild`; auto-detected if the project has exactly one scheme. |
| `--cache-dir <dir>` | option | `<repo>/.scip-cache` | Directory for the incremental index cache. Passing this flag (or `--index-only`) enables the persistent cache. |
| `--index-only` | flag | off | Skip the build step and read an existing IndexStore directly from the cache directory. Requires a prior successful build into the cache; otherwise fails with `indexStoreNotFoundForIndexOnly`, expecting `<cacheDir>/build-scratch/<triple>/<configuration>/index/store`. |

## CLI: `index-many` subcommand

Indexes multiple Swift repos independently, optionally merging results. Source: `Sources/scip-swift/Commands/IndexManyCommand.swift`.

| Flag / Argument | Type | Default | Description |
| --- | --- | --- | --- |
| `repoPaths` (positional, 2+) | paths | — | Paths to Swift repos to index. At least two required; fewer raises a validation error. |
| `--merge` | flag | off | Merge all indexes into a single `.scip` output. |
| `--output-dir <dir>` | option | `.` | Directory for individual `.scip` file output when not merging. Files are named `<repoDirectoryName>.scip`. |
| `--merged-output <path>` | option | `merged.scip` | Output path for the merged `.scip` file (used with `--merge`). |
| `--configuration <config>` | option | `debug` | Build configuration forwarded to the underlying build tool: `debug` or `release`. |
| `--cache-dir <dir>` | option | none (no persistent cache) | Directory for the incremental index cache. When omitted, each repo runs without the persistent cache (temp working directory). |

Notes on `index-many` behavior:

- Build tool is always auto-detected per repo (`buildTool: nil`); there is no `--build-tool` or `--scheme` flag on this subcommand.
- When merging, each repo's symbols are namespaced by its directory name as the symbol version.
- The merged index's project root is the current working directory.

## Environment and toolchain requirements

- **Swift toolchain**: pinned to `6.2.4` in `.swift-version`. Swift USR format is compiler-version sensitive, so the symbol mapping is only guaranteed stable against this version. The version is also reported in `scip-swift --version` output.
- **Xcode / xcode-select**: the active developer directory must be set (`xcode-select`). The tool locates the Swift toolchain via `xcrun --find swift` — on macOS, `/usr/bin/swift` is an `xcrun`-managed trampoline, so a plain `PATH` lookup resolves to the wrong toolchain root. Use `xcode-select -s <path>` (or the `DEVELOPER_DIR` mechanism it controls) to select the active toolchain.
- **libIndexStore.dylib**: loaded from `<toolchain>/usr/lib/libIndexStore.dylib`, derived from the `xcrun --find swift` result. This library only ships on macOS, so scip-swift is macOS-only.
- **macOS-only**: indexing Apple-platform imports needs Xcode + iOS SDK; the build/test pipeline is not supported on Linux.
- **No environment variables**: scip-swift reads no custom environment variables; all configuration is via CLI flags.

## Cache directory layout

The persistent cache is enabled only when `--cache-dir` is passed or `--index-only` is set; otherwise a throwaway temp directory (`/tmp/scip-swift-<uuid>` prefix) is used. Source: `Sources/scip-swift/Caching/CacheStore.swift` and `Commands/IndexCommand.swift`.

```text
<cacheDir>/
  manifest.json          # version manifest for global invalidation (JSON)
  docs/                  # per-document protobuf cache
    <sha256>.scipdoc     # serialized Scip_Document keyed by source-file content hash
  index-db/              # IndexStoreDB database directory
  build-scratch/         # build working directory; IndexStore lives at
                         # build-scratch/<triple>/<configuration>/index/store
```

- `docs/` entries are keyed by SHA256 content hash of the source file (`ContentHasher`), so unchanged files are re-used across runs without re-mapping.
- `build-scratch/` is the scratch path handed to the build runner; `--index-only` searches it for an existing IndexStore instead of rebuilding.

## Cache invalidation (`manifest.json`)

Source: `Sources/scip-swift/Caching/IndexManifest.swift`. The manifest holds four fields; **any** mismatch against the current run causes the entire cache to be deleted and rebuilt:

| Field | Meaning |
| --- | --- |
| `toolchainVersion` | Swift compiler version (USR format is compiler-version sensitive). Currently `6.2.4`. |
| `converterVersion` | scip-swift version (mapping logic changes between releases). |
| `indexstoreDbRevision` | indexstore-db git revision the converter was built against. Currently `c993f4fb`. |
| `buildToolName` | `swiftpm` or `xcodebuild` — the two backends produce different index data. |

Practical implications:

- Upgrading Swift, upgrading scip-swift, or switching `--build-tool` invalidates the whole cache in one shot (no partial reuse).
- Deleting `<cacheDir>` is always safe — the next run rebuilds it from scratch.
