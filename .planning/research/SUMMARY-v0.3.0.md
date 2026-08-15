# Project Research Summary: v0.3.0 Readable Indexes

**Project:** scip-swift
**Synthesized:** 2026-08-15 (inline synthesis — researcher subagents hit repeated provider 503s; STACK/FEATURES/PITFALLS done inline, ARCHITECTURE.md by surviving subagent with live-toolchain verification)

## Key Findings

### Stack
- **Demangling needs no new dependency**: the Swift runtime's `swift_demangle` C symbol is callable via `@_silgen_name`; USRs need a `s:`→`_$s` prefix rewrite (empirically verified with `xcrun swift-demangle --compact` on live index-store USRs). ObjC `c:` USRs never demangle — keep opaque fallback.
- **Exact ranges + doc comments need one new dependency**: `swift-syntax` (one parse per file feeds both range refinement and doc-comment extraction). IndexStoreDB provably stores only a start anchor per occurrence.
- **`-destination` needs no dependency**: plain xcodebuild argument, opt-in flag.

### Features (table stakes vs peers)
- Readable symbol names and exact ranges are **table stakes** — every peer indexer (scip-typescript, scip-rust, scip-java) has them; scip-swift is the outlier on both.
- Markdown `documentation` on symbols is table stakes for hover parity (scip-typescript from JSDoc, scip-rust from rustdoc); scip-swift currently emits signatures only.
- Fully-typed demangled names (with signature) would be a **differentiator** beyond peers.

### Architecture (verified against live toolchain)
- Demangling hooks into `SCIPSymbolFormatter` (not a post-pass); canonical symbol identity stays the wrapped USR — demangled text is display metadata. This preserves incremental-cache and cross-repo-merge stability.
- One shared per-file `SwiftSyntaxRefiner` pass refines occurrence ranges AND extracts doc comments; hybrid is acceptable within the "compiler index is authoritative" principle (index decides WHAT, syntax refines WHERE/comments).
- `-destination` is an optional nil-default parameter on `XcodebuildBuildRunner`.
- **Critical prerequisite discovered**: the `.xcodebuild` dispatch branch was lost from `IndexCommand.indexOneRepo` in the c06c050 refactor — Xcode-project repos currently fall through wrong on the `index` path. Must be fixed first.

### Watch Out For
- Swift mangling drift (mitigated by pinned toolchain; always fall back to opaque USR).
- UTF-8 vs UTF-16 column units (normalize in PositionMapping; Unicode fixture tests).
- Incremental-cache invalidation (bump IndexManifest format version when serialized output changes).
- Doc-comment trivia edge cases (only docLineComment/docBlockComment; skip license headers).
- `-destination` provisioning/simulator-drift failures (opt-in only; surface `xcodebuild -showdestinations` hint).

## Implications for Roadmap

1. **Phase 6 (foundation)**: restore `.xcodebuild` dispatch branch + `-destination` flag (prerequisite + low-complexity win) AND/OR demangling with USR-rewrite + fallback contract + cache-version bump.
2. **Phase 7**: SwiftSyntax dependency + shared refiner pass → exact ranges (replacing display-name approximation).
3. **Phase 8**: doc-comment extraction riding the same SwiftSyntax pass → `documentation` fields.
4. Demangling is independent of the SwiftSyntax track — phases can partially parallelize.
5. Every phase must keep `scip lint` passing and second-run byte-identity tests green (re-baselined).

## Sources
- `.planning/research/ARCHITECTURE.md` (subagent, verified against Swift 6.2.4 / Xcode 26 with live experiments)
- `.planning/research/STACK-v0.3.0.md`, `FEATURES-v0.3.0.md`, `PITFALLS-v0.3.0.md` (inline, web-verified where marked)
- scip.proto `SymbolInformation.documentation` semantics; scip-typescript/scip-rust doc extraction (public docs)
