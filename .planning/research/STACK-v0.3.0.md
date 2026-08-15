# Stack Research: v0.3.0 Readable Indexes

**Project:** scip-swift
**Researched:** 2026-08-15
**Mode:** Inline orchestrator research (researcher subagents unavailable — provider 503 capacity errors; findings below from targeted web research + the empirically verified ARCHITECTURE.md research)
**Confidence:** HIGH for demangling (verified by the architecture researcher against the live toolchain); MEDIUM for library versions (VERIFY markers where noted)

## Decisions Needed For

1. Demangling USRs into readable symbol names
2. Exact occurrence ranges
3. `xcodebuild -destination` selection
4. Symbol documentation extraction

## 1. Demangling — `swift_demangle` via runtime symbol

**Primary approach (recommended):** call the Swift runtime's `swift_demangle` C symbol directly from Swift via `@_silgen_name`, wrapping it in a small module-internal helper. No external SwiftPM dependency needed.

```swift
@_silgen_name("swift_demangle")
private func _swift_demangle(
  _ mangledName: UnsafePointer<CChar>?,
  _ mangledNameLength: Int,
  _ outputBuffer: UnsafeMutablePointer<CChar>?,
  _ outputBufferSize: UnsafeMutablePointer<Int>?,
  _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
```

**Verified facts (from ARCHITECTURE.md ground truth, tested against Swift 6.2.4 / Xcode 26):**
- USRs start with `s:`; `swift-demangle` CLI returns them unchanged. Rewriting prefix `s:` → `_$s` makes them demangle: `_$s4null7GreeterC5greet4nameS2S_tF` → `null.Greeter.greet(name: Swift.String) -> Swift.String`.
- ObjC/clang USRs (`c:...`, `objc:`) do not demangle — keep the current opaque USR fallback for those.
- `libswiftDemangle.dylib` ships in the active Xcode toolchain at `<toolchain>/usr/lib/libswiftDemangle.dylib` and exports `swift_demangle_getDemangledName`.
- The runtime symbol `swift_demangle` is available in-process (any Swift binary links the runtime).

**Community-package alternative:** `SwiftDemangler` (small SwiftPM lib wrapping the same `swift_demangle` symbol, with a `demangleUSR` helper doing exactly the `s:`→`$s` rewrite). <!-- VERIFY: latest version and maintenance status — community package, not Apple-supported. --> Recommendation: do NOT add the dependency; the wrapper is ~30 lines and the project already avoids non-essential dependencies. In-process `_silgen_name` call is faster than the CLI-subprocess option (no fork per batch), though ARCHITECTURE.md evaluated a batched `swift-demangle` subprocess as a fallback if in-process linking proves fragile.

**What NOT to add:** a full demangler implementation, swift-syntax for demangling, or a vendored copy of libswiftDemangle.

## 2. Exact occurrence ranges — SwiftSyntax

**Fact (verified against IndexStoreDB API):** `SymbolOccurrence` stores only a single start anchor (`location.line`, `location.utf8Column`) — no end position, no range, in the public API or underlying indexstore records.

Two tiers:

1. **Cheap exact-enough fix (no new dependency):** compute `endColumn = startColumn + symbol.name.utf8.count`. Identifiers are single-line; this is exact for simple identifiers and wrong only for macro-generated or multi-line raw identifiers. Strictly better than the current display-name approximation for compound names (`greet(name:)`), because `symbol.name` is the bare identifier at that site.
2. **Full exact ranges (new dependency):** `swift-syntax` SwiftPM package — parse each source file once, walk `TokenSyntax` to get precise `(line, utf8Column)` end positions for every token, and refine occurrence ends. <!-- VERIFY: current swift-syntax release compatible with Swift 6.2.4 toolchain pin — check https://github.com/swiftlang/swift-syntax releases; major versions track the toolchain. -->

ARCHITECTURE.md recommends tier 2 as a shared per-file "SwiftSyntaxRefiner" pass that also extracts doc comments (one parse, two outputs). The hybrid stays within the "compiler index is authoritative" principle: the index decides WHAT the occurrences are; SwiftSyntax only refines positions and extracts comments.

## 3. `xcodebuild -destination` — no new dependency

`-destination` is a plain `xcodebuild` argument. Add an optional `--destination` CLI flag (default `nil` = current behavior, generic "My Mac" destination) threaded through `XcodebuildBuildRunner`. Requires no package changes. See ARCHITECTURE.md for the prerequisite fix: the `.xcodebuild` dispatch branch was lost from `IndexCommand.indexOneRepo` in the c06c050 refactor and must be restored first.

## 4. Symbol documentation — SwiftSyntax (shared with ranges)

SwiftSyntax exposes doc comments via leading trivia (`TriviaPiece.docLineComment` / `docBlockComment`) attached to declaration nodes. Extract text, normalize to Markdown lines, emit into `Scip_SymbolInformation.documentation` (repeated string, treated as Markdown by consumers — same field scip-typescript fills from JSDoc and scip-rust from rustdoc). One SwiftSyntax parse per file covers both range refinement and doc extraction.

## Dependency Summary

| Need | Dependency | Version | Rationale |
|------|-----------|---------|-----------|
| Demangling | none (runtime `swift_demangle` via `@_silgen_name`) | — | Zero-dependency; runtime is always linked |
| Exact ranges | `swift-syntax` | <!-- VERIFY latest Swift-6.2-compatible release --> | Only source of precise token end positions |
| Doc comments | `swift-syntax` (same parse) | same | Leading-trivia extraction |
| `-destination` | none | — | Plain xcodebuild argument |

**Integration points:** `SCIPSymbolFormatter` (demangling hook), `PositionMapping` (range refinement input), `XcodebuildBuildRunner` (destination argument), new `SwiftSyntaxRefiner` (shared parse pass feeding `Scip_Document` construction).

**What NOT to add (reaffirmed):** custom Swift parser for indexing decisions, full-text source parsing to replace the index, vendored protobuf changes.

## Sources

- Swift runtime `swift_demangle` symbol usage pattern (SwiftDemangler package, community reference implementation)
- IndexStoreDB public API (`SymbolOccurrence`, `SymbolLocation` — start anchor only)
- scip.proto `SymbolInformation.documentation` field semantics; scip-typescript/scip-rust doc extraction behavior
- ARCHITECTURE.md ground-truth experiments (this repo, 2026-08-15): USR `s:`→`_$s` rewrite verified with `xcrun swift-demangle --compact` on live index-store USRs; `c:` USRs return length 0
