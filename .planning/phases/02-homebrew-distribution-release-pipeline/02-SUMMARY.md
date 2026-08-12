# Phase 2 Summary: Homebrew Distribution & Release Pipeline

**Date:** 2026-08-12
**Status:** DONE

## What Was Built

### Plan 02-01: Runtime Dylib Guard (DIST-04)
- `BuildError.xcodeRequired(dylibPath:)` — new exhaustive error case with actionable multi-step fix instructions
- `IndexStoreLoader.open` guards with `FileManager.default.fileExists` before loading `IndexStoreLibrary`, preventing opaque dyld crashes
- 3 unit tests verify error message content (dylib name, Xcode, xcode-select)

### Plan 02-02: Homebrew Formula + Release CI (DIST-01, DIST-02, DIST-03)
- `Formula/scip-swift.rb` — pre-built binary formula with SHA256 verification, `depends_on macos: :sonoma`, `bin.install`, test block
- `.github/workflows/release.yml` — tag-triggered (`v*`) pipeline that:
  - Cross-compiles arm64 + x86_64 via `--triple`
  - Creates universal binary via `lipo -create`
  - Publishes GitHub Release with tarball
  - Auto-updates tap formula SHA256 via `HOMEBREW_TAP_TOKEN`
- Tap owner: `phuongddx` (matches README)

## Files Created/Modified

| File | Action |
|------|--------|
| `Sources/scip-swift/Build/BuildError.swift` | Modified — new `xcodeRequired` case |
| `Sources/scip-swift/IndexStore/IndexStoreLoader.swift` | Modified — fileExists guard |
| `Tests/scip-swiftTests/DylibCheckTests.swift` | Created (3 tests) |
| `Formula/scip-swift.rb` | Created — Homebrew formula template |
| `.github/workflows/release.yml` | Created — release CI pipeline |

## Test Results

- **57 tests in 9 suites** — all passing (3 new DylibCheck tests, 0 regressions)

## User Setup Required (before first release)

1. Create `phuongddx/homebrew-scip-swift` tap repo on GitHub
2. Copy `Formula/scip-swift.rb` into the tap repo's `Formula/` directory
3. Store `HOMEBREW_TAP_TOKEN` as a repository secret (PAT with `repo` scope)
4. Bump `ScipSwiftVersion.version` to `"0.2.0"` in `Sources/scip-swift/Version.swift`
5. Tag with `v0.2.0` to trigger the release pipeline

## Requirements Covered

- ✅ DIST-01 — Homebrew formula in custom tap
- ✅ DIST-02 — Universal binary via cross-compilation + lipo
- ✅ DIST-03 — Release CI triggered on v* tags
- ✅ DIST-04 — Runtime dylib guard with actionable error
