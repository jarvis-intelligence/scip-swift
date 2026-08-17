---
status: complete
phase: 09-symbol-documentation (consolidated v0.3.0 milestone UAT)
source: [06-01..02, 07-01..02, 08-01..02, 09-01 SUMMARY.md]
started: 2026-08-17T20:35:00Z
updated: 2026-08-17T20:50:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Phase 6 (REPAIR-01): Xcode-project repo indexes via xcodebuild backend
expected: `scip-swift index <XcodeTestProject copy>` produces a .scip through the xcodebuild backend.
result: pass
evidence: "Wrote 1 document(s) to xcode.scip" (~27s real xcodebuild); lint clean; symbols present (Animal class, Foundation externals).

### 2. Phase 6 (REPAIR-02): --destination selects destination
expected: Valid destination builds for that destination; flag visible in help.
result: pass
evidence: Flag threaded (visible in the error invocation); valid `platform=macOS` path exercised in integration tests; omitting preserves generic behavior (test 1 ran without flag).

### 3. Phase 6 (REPAIR-03): Bogus destination surfaces -showdestinations hint
expected: Failing destination build prints full output + copyable `xcodebuild ... -showdestinations` hint.
result: pass
evidence: Exit 70 error carries full invocation; "Hint: list valid destinations ... xcodebuild -project ... -showdestinations" printed.

### 4. Phase 7 (SYMBOL-01): Demangled display names in .scip
expected: Swift symbols show readable names.
result: pass
evidence: "MiniSwiftPackage.Greeter", "MiniSwiftPackage.Greeter.init(name: Swift.String) -> MiniSwiftPackage.Greeter", getter/setter names in output; scip lint clean.

### 5. Phase 7 (SYMBOL-02): Non-demanglable fallback
expected: ObjC/c: USRs keep opaque form; indexing never fails.
result: pass
evidence: Xcode-project index (Foundation-heavy) built cleanly with `c:@M@Foundation` opaque externals intact.

### 6. Phase 7 (SYMBOL-04): --no-demangle reproduces v0.2.x output
expected: Opaque-only names when flag passed.
result: pass
evidence: Opaque run contains zero demangled Greeter strings; demangled-only strings absent.

### 7. Phase 7 (SYMBOL-03): Incremental cache + second-run identity
expected: --cache-dir creates cache (index-db/docs/manifest); second run byte-identical content.
result: pass
evidence: Cache layout present; second run reuses cache. Note: raw `cmp` differs ONLY in metadata.toolInfo (output filename string) — documents/occurrences identical; the suite's byte-identity test (fixed output name) passes. Relative --cache-dir from a repo's parent dir hits a temp-dir resolution quirk — see Gaps.

### 8. Phase 4 carryover (cross-repo): index-many --merge
expected: Two distinct repos merge into one lint-clean index.
result: pass
evidence: mini + renamed mini2 → "Merged 2 indexes: 2 document(s)"; lint exit 0.

### 9. Phase 8 (RANGE-01/02): Exact ranges incl. Unicode
expected: Unicode fixture indexes with exact byte columns; lint clean.
result: pass
evidence: UnicodeRangeFixture indexed; lint clean; F4 column table verified by suite + Phase 8 verifier's own decode.

### 10. Phase 9 (DOCS-01): Doc comments as Markdown documentation
expected: /// and /** */ docs attached to symbols in the .scip.
result: pass
evidence: doc.scip contains "Frozen constant." on var/getter/setter USRs (accessor inheritance works); "Documented with noise interleaved." (real /// doc) present; lint clean.

### 11. Phase 9 (DOCS-02): Exclusions
expected: License headers, // noise, trailing comments excluded.
result: pass
evidence: "license line one" NOT in output; "trailing noise after a statement" NOT in output; real interleaved doc IS present.

### 12. Phase 9 (DOCS-03): One parse per file
expected: Documentation rides the same parse pass.
result: pass
evidence: Verified by suite (parse-count hook + structural grep gate = 1 Parser.parse in Sources/); Phase 9 verifier independently confirmed.

## Summary

total: 12
passed: 12
issues: 1
pending: 0
skipped: 0

## Gaps

- gap_id: G-v030-1
  truth: "--cache-dir accepts relative paths uniformly across invocation directories"
  status: failed
  reason: "Invoking with a relative --cache-dir while CWD differs from the repo root resolves the cache under $TMPDIR semantics ('/var/folders/.../T/rel-cache' from inside the repo), producing indexstoredb_index_create failure 'No such file or directory'. Also, run from the PARENT of the repo with a bare relative dir, the build-scratch path interpolation fails to produce an index store ('<triple>' placeholder in error path suggests unresolved scratch dir). Absolute --cache-dir works perfectly (all cache tests green)."
  severity: minor
  test: 7
  artifacts: ["Sources/scip-swift/Commands/IndexCommand.swift", "Sources/scip-swift/Caching/CacheStore.swift"]
  missing: ["document --cache-dir as requiring an absolute path OR normalize relative paths to an absolute resolved path at parse time"]
