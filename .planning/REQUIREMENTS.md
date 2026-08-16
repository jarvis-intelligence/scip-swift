# Requirements: Milestone v0.3.0 — Readable Indexes

**Created:** 2026-08-15
**Status:** Active

## Requirements

### Repair & Targeting (REPAIR)

- [x] **REPAIR-01**: User can index an Xcode-project repo via `scip-swift index <repo>` and it builds through the xcodebuild backend again (restore the `.xcodebuild` dispatch branch lost in the 0cdefd7 cache rewrite (code recoverable from 1c5ba8f)), verified by an integration test against the existing Xcode fixture.
- [x] **REPAIR-02**: User can pass `--destination <spec>` (e.g. `platform=iOS Simulator,name=iPhone 16`) to select the xcodebuild destination; omitting the flag preserves today's generic-destination behavior.
- [x] **REPAIR-03**: When a `--destination` build fails, the error output includes a hint to run `xcodebuild -showdestinations` so the user can discover valid destination strings.

### Readable Symbols (SYMBOL)

- [x] **SYMBOL-01**: User sees demangled, human-readable symbol names (e.g. `null.Greeter.greet(name: Swift.String) -> Swift.String`) in place of raw `s:`-prefixed USRs for Swift symbols in the generated `.scip` index.
- [x] **SYMBOL-02**: Symbols that cannot be demangled (ObjC/C `c:`-prefixed USRs, future mangling constructs) keep the existing opaque wrapped-USR form — indexing never fails because of demangling.
- [x] **SYMBOL-03**: Symbol identity remains stable — the wrapped USR stays the canonical `symbol` field so incremental cache hits and cross-repo merge dedup behave unchanged when demangling is enabled (verified by existing second-run byte-identity and merge tests, re-baselined).
- [x] **SYMBOL-04**: User can disable demangling (`--no-demangle`) to reproduce v0.2.x-style opaque output.

### Exact Occurrence Ranges (RANGE)

- [ ] **RANGE-01**: Occurrence end columns are computed from the exact identifier token extent (via SwiftSyntax) instead of approximated from display-name length; definitions and references both emit exact ranges.
- [ ] **RANGE-02**: Occurrence ranges are correct on files containing multi-byte (Unicode/CJK/emoji) content earlier on the same line — columns are normalized to UTF-8 byte offsets end-to-end (fixture test).
- [ ] **RANGE-03**: Files that SwiftSyntax cannot fully parse (error nodes, macro-expanded code) still index successfully, falling back to name-length end columns for affected occurrences.

### Symbol Documentation (DOCS)

- [ ] **DOCS-01**: User sees Swift doc comments (`///` and `/** */`) attached to the corresponding symbols in the `.scip` index, rendered as Markdown in `SymbolInformation.documentation` (hover parity with scip-typescript/scip-rust).
- [ ] **DOCS-02**: Non-doc comments (`//`), license headers, and comments on non-declaration tokens are excluded from documentation extraction.
- [ ] **DOCS-03**: Documentation extraction shares the same per-file parse pass as range refinement (one SwiftSyntax parse per file, not two).

## Future Requirements (deferred)

- Fully-typed symbol names combining demangled name + signature in the display string (differentiator beyond peers) — needs UX validation
- Doc-comment extraction for ObjC headers
- Destination autodetection / multi-destination indexing sweeps

## Out of Scope

- Linux support — unchanged (macOS-only `libIndexStore.dylib`)
- Custom Swift source parser for indexing decisions — SwiftSyntax refines ranges/docs only; the compiler index stays authoritative for what the occurrences ARE
- Markdown rendering/processing beyond normalization — consumers render
- Whole-declaration ranges for references — SCIP wants identifier tokens

## Traceability

| REQ | Phase | Status |
|-----|-------|--------|
| REPAIR-01 | Phase 6 | Complete |
| REPAIR-02 | Phase 6 | Complete |
| REPAIR-03 | Phase 6 | Complete |
| SYMBOL-01 | Phase 7 | Complete |
| SYMBOL-02 | Phase 7 | Complete |
| SYMBOL-03 | Phase 7 | Complete |
| SYMBOL-04 | Phase 7 | Complete |
| RANGE-01 | Phase 8 | pending |
| RANGE-02 | Phase 8 | pending |
| RANGE-03 | Phase 8 | pending |
| DOCS-01 | Phase 9 | pending |
| DOCS-02 | Phase 9 | pending |
| DOCS-03 | Phase 9 | pending |
