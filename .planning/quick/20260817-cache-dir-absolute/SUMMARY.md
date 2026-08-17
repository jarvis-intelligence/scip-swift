---
status: complete
completed: 2026-08-17
task: normalize --cache-dir to absolute path (G-v030-1)
---

# Quick Task: fix relative --cache-dir (G-v030-1)

## Description
UAT gap G-v030-1: relative `--cache-dir` values failed with `indexstoredb_index_create` ENOENT depending on invocation directory.

## Root Cause
Not our path joining — upstream IndexStoreDB behavior: the vendored LLVM support's `createUniquePath` (Path.cpp:740) anchors any *relative* model path under the system temp dir (`system_temp_directory`). The process-unique index-db directory (`index-db/v13/p<pid>-<rand>`) is therefore constructed as `$TMPDIR/<relative-cache>/...`, whose parent never exists → "No such file or directory". Absolute cache dirs bypass the anchoring entirely.

## Fix
`IndexCommand.indexOneRepo`: resolve the cache dir via `URL(fileURLWithPath:).standardizedFileURL.path` before any consumer sees it — one line, applies to explicit `--cache-dir` and the default `.scip-cache` alike. `index-many` routes through the same `indexOneRepo` path, so it's covered.

## Verification
- Relative `--cache-dir` from inside the repo: run 1 builds cache layout (build-scratch/index-db/docs/manifest.json), run 2 cache-hits, doc-level content identical (diff is only metadata.toolInfo output filename — same as absolute-path behavior)
- Relative `--cache-dir` from parent dir: works
- `--cache-dir ../parent-rel`: resolves against CWD correctly
- `swift test --filter IncrementalIntegrationTests`: 5/5 green
- `swift test --skip Xcode`: 139/139 green

## Deviation note
First attempt used `(rawCacheDir as NSString).absolutePath` — renamed to `isAbsolutePath` (Bool) in modern Foundation; the initial "verification" of that attempt was invalid because `| tail -1` masked the compile failure (the exact pipe-masking anti-pattern the Phase 8 plan-checker flagged). Rebuilt with error surfacing, switched to `standardizedFileURL.path`, then verified for real.

Commit: 1f59991
