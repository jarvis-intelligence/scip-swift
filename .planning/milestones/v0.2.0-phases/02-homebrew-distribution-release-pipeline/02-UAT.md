---
status: complete
phase: 02-homebrew-distribution-release-pipeline
source: [02-SUMMARY.md, 02-01-SUMMARY.md, 02-02-SUMMARY.md]
started: 2026-08-15T14:00:00Z
updated: 2026-08-15T14:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. GitHub Release v0.2.0 published with universal binary
expected: Tag-triggered CI publishes a non-draft release with a tarball containing an arm64 + x86_64 universal binary.
result: pass
evidence: `gh release view v0.2.0` — published 2026-08-13, asset `scip-swift-0.2.0.tar.gz` (3.7 MB); `lipo -info` confirms `x86_64 arm64`.

### 2. Release binary reports version 0.2.0
expected: `scip-swift --version` on the release artifact prints `0.2.0`.
result: pass
evidence: "Originally failed (binary printed 0.1.2). Fixed: Version.swift bumped, v0.2.1 tagged from bumped source; v0.2.1 release binary reports 0.2.1."

### 3. Release binary indexes a SwiftPM repo and passes scip lint
expected: Downloaded release binary runs `index` against MiniSwiftPackage fixture, writes a .scip file that passes `scip lint` (exit 0).
result: pass
evidence: `Wrote 1 document(s) to mini.scip`; `scip lint` exit 0; stats: 1 document, 16 occurrences.

### 4. Incremental indexing flags work on release binary
expected: `--cache-dir` populates a persistent cache (index-db, docs, manifest.json); second run uses cached documents with identical index content.
result: pass
evidence: Cache dir created with `index-db/`, `docs/`, `manifest.json`, `build-scratch/`. Second-run output differs only in metadata.toolInfo (output filename + cache-dir args recorded); documents/occurrences identical (1 doc, 16 occurrences both runs).

### 5. Homebrew formula installable from tap
expected: `brew install phuongddx/scip-swift/scip-swift` works from the tap repo.
result: pass
evidence: "Originally failed (tap repo 404, CI auth failure). Fixed: phuongddx/homebrew-scip-swift created with v0.2.0 formula, HOMEBREW_TAP_TOKEN secret set, release.yml URL corrected to jarvis-intelligence org. Verified: tap + install + universal binary at /opt/homebrew/Cellar/scip-swift/0.2.0."

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0

## Gaps

- gap_id: G-02-2
  truth: "Release binary reports version 0.2.0"
  status: resolved
  reason: "Version.swift never bumped; binary ships 0.1.2 inside the v0.2.0 tarball"
  severity: minor
  test: 2
  artifacts: ["Sources/scip-swift/Version.swift"]
  missing: ["version bump to 0.2.0 + new tag/release or patch release"]
  resolved_by: "fix(release): bump version to 0.2.0 (33d7154) + v0.2.1 tag"
  resolved_at: 2026-08-15
  notes: "v0.2.0 release assets are immutable; v0.2.1 tagged from bumped source. Old tarball still reports 0.1.2 — superseded by v0.2.1."
- gap_id: G-02-5
  truth: "brew install phuongddx/scip-swift/scip-swift works"
  status: resolved
  reason: "Tap repo missing; CI tap-update step failed on authentication (HOMEBREW_TAP_TOKEN invalid or repo absent)"
  severity: major
  test: 5
  artifacts: [".github/workflows/release.yml", "Formula/scip-swift.rb"]
  missing: ["create phuongddx/homebrew-scip-swift repo", "valid HOMEBREW_TAP_TOKEN secret", "re-run tap formula update"]
  resolved_by: "tap bootstrap + HOMEBREW_TAP_TOKEN secret + release.yml URL fix (33d7154)"
  resolved_at: 2026-08-15
  notes: "Tap repo created, formula pushed with real v0.2.0 SHA256, `brew install phuongddx/scip-swift/scip-swift` verified working (universal binary, /opt/homebrew/Cellar/scip-swift/0.2.0). Release workflow now updates the tap on future tags."
