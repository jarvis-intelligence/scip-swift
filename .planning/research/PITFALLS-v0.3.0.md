# Pitfalls Research: v0.3.0 Readable Indexes

**Project:** scip-swift
**Researched:** 2026-08-15
**Mode:** Inline orchestrator research (researcher subagents unavailable — provider 503 capacity errors; distilled from ARCHITECTURE.md ground truth, IndexStoreDB/SwiftSyntax documentation, and peer-indexer post-mortems)
**Confidence:** MEDIUM-HIGH (each pitfall maps to a known failure mode of the specific APIs involved)

## P1: Demangling format drift across Swift versions
**Warning signs:** demangled output differs between local run and CI; newer mangling constructs (macros, parameter packs) return nil or partially-demangled strings.
**Prevention:** toolchain is pinned (`.swift-version` 6.2.4) — demangler and compiler emit the same mangling version by construction. Always fall back to the opaque USR on nil/failed demangle. Never assume success.
**Phase:** demangling phase (6) — bake the fallback into the formatter contract from the first commit.

## P2: Non-Swift USRs reaching the demangler
**Warning signs:** `c:`/`objc:` USRs (ObjC/C symbols) crash or return garbage.
**Prevention:** verified — `swift_demangle_getDemangledName` returns length 0 for `c:` USRs; only rewrite `s:`-prefixed USRs (`s:`→`_$s`), keep everything else opaque.
**Phase:** demangling phase (6).

## P3: Closures / local / disambiguated symbols demangle to unusable names
**Warning signs:** `(closure #1)`, `(implicit)` fragments; local symbols (`local <n>`) have no USR to demangle.
**Prevention:** demangle only global/ scoped symbols; locals keep their stable `local <n>` scheme. Treat demangled name as display-only — the opaque wrapped USR stays the canonical symbol identity so cross-run and cross-repo symbol identity doesn't shift (incremental cache + ScipIndexMerger stability).
**Phase:** demangling phase (6); regression-tested via cache-identity tests.

## P4: In-process `@_silgen_name("swift_demangle")` fragility
**Warning signs:** link errors on some SDK versions; symbol present but semantics differ (buffer-ownership).
**Prevention:** ARCHITECTURE.md verified the symbol path; keep the batched `swift-demangle` CLI subprocess as the documented fallback. Wrap in one helper so the swap is one-line.
**Phase:** demangling phase (6).

## P5: SwiftSyntax parse of files that don't parse (macros,Generated code,IDE-fixits)
**Warning signs:** `Parser.parse` throwing or producing error nodes; range refinement silently missing files.
**Prevention:** SwiftSyntax always returns a tree (error nodes included); refinement must skip error nodes and fall back to name-length end columns. Never fail the whole file because a node is malformed.
**Phase:** ranges phase (7).

## P6: UTF-8 vs UTF-16 column confusion
**Warning signs:** ranges shifted by 1 on files with emoji/CJK in earlier lines; IndexStoreDB uses `utf8Column`, SwiftSyntax positions are UTF-8 offsets, SCIP is UTF-8-based — but editors/SCIP consumers may assume UTF-16.
**Prevention:** normalize everything to UTF-8 byte columns in one place (PositionMapping); add fixture tests with multi-byte identifiers/strings. <!-- VERIFY: scip consumer column-unit expectations in scip.proto comments -->
**Phase:** ranges phase (7) — tests with Unicode fixtures before wiring.

## P7: `xcodebuild -destination` failure modes
**Warning signs:** "Unable to find a destination"; provisioning errors on simulator destinations for app targets; destination names drift across Xcode versions (`platform=iOS Simulator,name=iPhone 16`).
**Prevention:** destination is opt-in only (nil default = current generic My Mac behavior). On xcodebuild failure, surface the full output (already untruncated) with a hint listing `xcodebuild -showdestinations`. Document supported destination strings.
**Phase:** destination phase (6 or 7, after dispatch-branch fix).

## P8: Doc-comment extraction edge cases
**Warning signs:** license headers captured as docs; `//` line comments (non-doc) captured; `///` inside string literals; comments on the wrong node due to attached-trivia walking.
**Prevention:** only `docLineComment`/`docBlockComment` trivia pieces count (not `lineComment`); walk to the declaration token only; strip leading `/// ` markers; normalize block-comment continuation.
**Phase:** docs phase (8) with the shared SwiftSyntax pass.

## P9: Incremental-cache invalidation when symbol format changes
**Warning signs:** cached documents from v0.2.x served after upgrading to v0.3.x → mixed opaque/demangled symbols; byte-diff comparisons in tests flake.
**Prevention:** IndexManifest already has four-field version invalidation — bump the manifest/index format version so old caches invalidate atomically. Second-run byte-identity tests must re-baseline.
**Phase:** whichever phase first changes serialized output (demangling, 6) — bump version there.

## P10: Symbol identity churn breaking cross-repo merge
**Warning signs:** ScipIndexMerger dedup/strip logic keyed on the old opaque symbol strings stops matching after demangling.
**Prevention:** keep canonical identity = wrapped USR (unchanged); demangled text is metadata, not identity. Merger tests must assert merge still works with demangled docs present.
**Phase:** demangling phase (6) regression suite.
