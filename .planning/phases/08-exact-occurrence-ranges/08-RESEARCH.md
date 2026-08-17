# Phase 8: Exact Occurrence Ranges - Research

**Researched:** 2026-08-17
**Domain:** SwiftSyntax token-extent refinement of IndexStoreDB occurrence anchors → SCIP ranges
**Confidence:** HIGH (all load-bearing claims verified this session by scratch `swiftc`/SwiftPM binaries against the pinned Swift 6.2.4 / Xcode 26 toolchain, or by reading repo source)

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RANGE-01 | Exact identifier-token end columns for definitions AND references (no compound-name drift) | 100% anchor-to-token-start match rate on both fixtures (§F2); drift cases isolated (§F3) |
| RANGE-02 | Multi-byte content correct, UTF-8 byte offsets end-to-end, fixture test | Self-computed line-start byte table sidesteps UTF-16 traps (§F1, D3); fixture + expected columns ready (§F4) |
| RANGE-03 | Unparseable files still index, fall back to name-length end columns | `Parser.parse` never throws; error nodes still yield `.present` tokens (§F5); nil-refinement fallback path (D2) |
</phase_requirements>

## Summary

Today every occurrence's end column comes from `[VERIFIED: Sources/scip-swift/SCIPMapping/PositionMapping.swift:13-22]`: `let zeroBasedLine = Int32(location.line - 1)`, `let zeroBasedStartCharacter = Int32(location.utf8Column - 1)`, `let length = Int32(approximateTokenLength(displayName: displayName))`, `range.endCharacter = range.startCharacter + max(length, 0)` with `approximateTokenLength` = `displayName.prefix(while: { $0 != "(" }).utf8.count`. The anchor (start) is already exact and UTF-8-byte-correct; only the END is guessed from the display name. The guess is wrong for `getter:name`/`setter:name` occurrences (prefix `getter:` overshoots by 7–13 bytes — measured), for the string-interpolation `init` anchored on `"` (spans into the literal), and for any future display-name/token mismatch. A SwiftSyntax refinement pass replaces the guess with the real token extent while keeping the approximation as fallback.

Empirically (scratch probe joining a real IndexStoreDB against a SwiftSyntax token map): **every** occurrence anchor in both test fixtures — 16/16 in MiniSwiftPackage, 13/13 in a Unicode fixture — lands exactly on a token start (0-based byte col `utf8Column - 1`). So a `(line, startCol) → endCol` map built from one parse per file covers all occurrences; the fallback only fires on map misses (unreadable file, anchor inside an error region).

**Primary recommendation:** Add `swift-syntax` `exact: "602.0.0"` (SwiftSyntax + SwiftParser products), new `SourceRefinement/SwiftSyntaxRefiner.swift` building a `[line: [startCol: endCol]]` byte-column map per parsed file, exact end = `token.positionAfterSkippingLeadingTrivia.utf8Offset + token.text.utf8.count` (**never** `endPosition` — it includes trailing trivia), lookup in `makeDocument` before the existing approximation, which remains the fallback. No version bump: 0.3.0 is unreleased (latest tag `v0.2.1`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| What occurrences exist, anchor position | IndexStoreDB (unchanged) | — | Hybrid contract: index decides WHAT, syntax refines WHERE |
| Exact token extent | New `SwiftSyntaxRefiner` (SourceRefinement/) | `PositionMapping` (conversion math) | Parse once per file; mapper stays pure |
| 1-based↔0-based / fallback math | `PositionMapping` (unchanged convention) | — | Single place for the anchor math, per milestone ARCHITECTURE.md |
| Parse orchestration, per-file caching | `SCIPIndexBuilder.makeDocument` | CacheStore (skip parse on cache hit) | One parse per non-cached document |
| Dependency/version policy | `Package.swift` | `.swift-version` pin | swift-syntax major tracks toolchain (602 ↔ Swift 6.2) |

## Key Verified Facts (empirical)

**F1 — Token semantics** `[VERIFIED: scratch binary, swift-syntax 602.0.0, Swift 6.2.4]`: `positionAfterSkippingLeadingTrivia.utf8Offset` and `endPosition.utf8Offset` are 0-based UTF-8 byte offsets. `endPosition` **includes trailing trivia**: token `emoji` start=4, `endPosition`=10, but `start + text.utf8.count` = 9 (text is 5 bytes; +1 trailing space). Identifier-exact end is **always** `start + token.text.utf8.count` (held for every identifier across both fixtures). `AbsolutePosition` has **no** `.line`/`.column` members in 602.0.0 (compile error verified); line/col live on `SourceLocationConverter`, whose column basis is unverified — do not use it; compute from a line-start offset table over the UTF-8 bytes (verified to match IndexStoreDB anchors exactly).

**F2 — Anchor↔token match rate** `[VERIFIED: scratch probe joining IndexStoreDB occurrences to SwiftSyntax token starts]`: MiniSwiftPackage 16/16 anchors (defs + refs) exactly at token starts; Unicode fixture 13/13, including `greet` ref at 0-based col 13 after 6-byte `名前` on the same line, and `String` refs after CJK. Zero containing-only hits, zero misses.

**F3 — Where the current approximation actually drifts** `[VERIFIED: probe output]`: (a) accessor occurrences — `getter:name` anchored at token `name` [13,17) but display name gives end 24 (+7); `getter:名前` exact [4,10) vs approx 17 (+13); (b) `init(stringInterpolation:)` anchored at the `"` token [4,5) vs approx [4,8) (into the literal); (c) plain identifiers/compound call refs (`greet(name:)` → base `greet`) are already correct — the approximation's `prefix(while: != "(")` handles them, and `utf8Column` is already byte-based, so **current output is already UTF-8-correct**; RANGE-02 pins the NEW path against UTF-16 regressions, it does not fix existing drift on ASCII-pure simple names.

**F4 — Unicode fixture + expected columns** (hexdump-verified bytes): `let emoji = "🦖"` / `let 名前 = greet(name: "日本語")` / blank / `func greet(name: String) -> String {` / `  "Hello, \(name) 🎉"`. Expected 0-based SCIP ranges: emoji def L0 [4,9); getter:emoji L0 [4,9) (approx 16 ✗); 名前 def L1 [4,10); getter:名前 L1 [4,10) (approx 17 ✗); greet ref L1 [13,18); greet def L3 [5,10); name param def L3 [11,15); String refs L3 [17,23) and [28,35); `init(stringInterpolation:)` L4 [2,3); name ref L4 [12,16). (名前=6 bytes, 日本語=9, 🦖=4, 🎉=4.)

**F5 — Error recovery (RANGE-03)** `[VERIFIED: scratch]`: `Parser.parse(source:)` is non-throwing; on `struct Broken { let x: = }` the tree reports `hasError=true` yet tokens `ok`, `Broken`, `x`, `alsoOk`, `print` are all `.presence == .present` with correct exact extents (31 tokens, 0 missing). Fallback therefore only fires for anchors that miss the map (unreadable file → `String(contentsOfFile:)` nil → nil refinement; anchor inside a garbled region).

**F6 — Build cost** `[VERIFIED: measured]`: release binary 7,023,480 B → 24,547,384 B (+17.5 MB, 3.5×) with SwiftSyntax+SwiftParser statically linked (no new dylibs — `otool -L` unchanged). Cold release build 261 s vs ~26 s incremental baseline; swift-syntax alone compiles in ~154 s release. Parse+map runtime: 27 ms for a 118 KB / 13k-token file — negligible vs the index build.

## Decisions

**D1 — Dependency: `swift-syntax` pinned `exact: "602.0.0"`.** Tag exists on `swiftlang/swift-syntax` (git ls-remote), resolves and compiles against the 6.2.4 toolchain (verified end-to-end). Exact pin over `from:` — majors track toolchains (602=6.2; 603/604/605 exist for newer toolchains and must not be pulled). Package.swift form: `.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0")` plus products `SwiftSyntax`, `SwiftParser` on the executable target. Binary-size cost accepted (24 MB is normal for Homebrew CLIs); note in release notes.

**D2 — `SwiftSyntaxRefiner` (new `SourceRefinement/` dir), one parse per document.** `makeDocument` reads file content once (`String(contentsOfFile:encoding:.utf8)`), parses, builds `tokenEndColumns: [Int: [Int: Int]]` (line → 0-based byte startCol → 0-based byte endCol, end = start + text.utf8.count), computed from a self-built line-start table over `[UInt8]` — never `SourceLocationConverter`. Lookup API: `exactEndColumn(line: Int, utf8Column: Int) -> Int?` taking IndexStoreDB's 1-based values. Read failure or any miss → `nil`. Cache interaction is free: cache hits skip `makeDocument` entirely `[VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:53-59]`, and the cache is content-hash keyed, so cached ranges are the ranges that content produces. `makeDocument` runs once per file already — no extra memoization needed; design the refiner to be extensible for Phase 9 docs (same parse) but do not extract docs now.

**D3 — Conversion math stays in `PositionMapping`.** New signature `singleLineRange(location:displayName:exactEndColumn: Int32?)` — same 1-based→0-based math as today verbatim, but `endCharacter` uses the exact end when non-nil, else the existing `approximateTokenLength` path unchanged. Keeps the fallback testable pure-unit. Call site `[VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:171-177]` gains one lookup argument.

**D4 — No second version bump.** `[VERIFIED: Sources/scip-swift/Version.swift:5]` is already `static let version = "0.3.0"` and the latest git tag is `v0.2.1` — no released binary ever wrote a 0.3.0 manifest, so the Phase-7 bump already invalidates every real-world cache via `[VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:124-141]` (manifest mismatch → `store.invalidateAll()`). Residual: dev machines that ran post-Phase-7 builds hold 0.3.0-manifest caches with approximate ranges; these self-heal per-file on content change (content-hash keying). Acceptable; document, don't bump to 0.4.0 (milestone is v0.3.0).

**D5 — Key the map on ALL tokens, not just identifiers.** Operators, `init`/`subscript`, and attribute-anchored occurrences match too; the 100% match rate (F2) was measured with a full-token map. Restricting to identifiers would re-introduce misses for no measurable memory win.

**D6 — Fixture: new `Fixtures/UnicodeRangeFixture`** (content per F4). Integration test builds it with `SwiftPMBuildRunner` exactly like MiniSwiftPackage tests and asserts the F4 table; also asserts one getter occurrence where approximation drifted (RANGE-01 proof on same fixture).

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| swift-syntax 602.0.0 | SwiftPM (GitHub) | 602.0.0 released 2025-09-15; project since 2015 | n/a (SwiftPM) | github.com/swiftlang/swift-syntax | OK (manual audit) | Approved |

The seam's `package-legitimacy check` supports npm/pypi/crates only. Manual audit: official `swiftlang` org, release commit GPG-signed with Swift's verified key (checked release page), tag verified via `git ls-remote`, dependency of swift-format/SwiftLint/SourceKit-LSP. HIGH confidence.

## Common Pitfalls

### Pitfall 1: `endPosition` includes trailing trivia
**What goes wrong:** Using `token.endPosition.utf8Offset` as the identifier end over-extends by the trailing whitespace (`emoji` → 10 instead of 9).
**Avoid:** end = `positionAfterSkippingLeadingTrivia.utf8Offset + token.text.utf8.count` (verified invariant). **Warning sign:** end columns that vary with formatting changes.

### Pitfall 2: UTF-16 columns sneaking in
**What goes wrong:** Swift `String` APIs are UTF-16-biased; a column computed via `SourceLocationConverter` or `String.Index` arithmetic breaks every lookup after multi-byte content (silent — lookups just miss and everything falls back to approximation, RANGE-01/02 silently unfixed).
**Avoid:** Line-start table over `Array(source.utf8)`; all columns are byte deltas. Unit test with the F4 fixture is the tripwire. **Warning sign:** 100% fallback rate on files with emoji/CJK.

### Pitfall 3: Macros / generated code
**What goes wrong:** Assumptions that every anchor has a token. Macro-expansion declarations and garbled regions may miss.
**Avoid:** Nil-lookup → existing approximation (D2/D3). A miss is never an error. **Warning sign:** any `try`/throw on the refinement path.

### Pitfall 4: Parsing twice (Phase 9 leak)
**What goes wrong:** Doc-comment extraction (Phase 9) re-parses per file, doubling cost.
**Avoid:** Refiner owns the single parse now; Phase 9 extends it, not adds a second pass (DOCS-03 already requires this).

### Pitfall 5: Binary size / CI time surprise
**What goes wrong:** +17.5 MB binary and ~+2.5–4 min cold release builds (F6) land unnoticed.
**Avoid:** Accepted per D1; call it out in the release notes and expect slower first CI build after the dependency lands.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Swift lexing/token extents | Regex/word-boundary scanner | SwiftParser tokens | Compiler-grade lexing incl. operators, string interpolations, Unicode identifiers |
| Line/column math | `SourceLocationConverter` | Own line-start byte table | Converter column basis unverified; self-computed table empirically matches IndexStoreDB |
| Fallback policy | Deleting occurrences on miss | Keep current approximation | RANGE-03 contract; index stays valid even when refinement misses everything |

## Code Examples

### Refiner core (verified logic, production skeleton)
```swift
// Source: scratch probe logic verified against Swift 6.2.4 / swift-syntax 602.0.0
import SwiftSyntax
import SwiftParser

struct SwiftSyntaxRefiner {
  private let tokenEndColumns: [Int: [Int: Int]]  // line -> startColByte -> endColByte

  init?(filePath: String) {
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }
    let bytes = Array(source.utf8)
    var lineStarts = [0]
    for (i, b) in bytes.enumerated() where b == 0x0A { lineStarts.append(i + 1) }
    var map: [Int: [Int: Int]] = [:]
    for token in Parser.parse(source: source).tokens(viewMode: .sourceAccurate) {
      let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
      let end = start + token.text.utf8.count   // NOT endPosition (trailing trivia!)
      var line = 1
      for (idx, ls) in lineStarts.enumerated() where ls <= start { line = idx + 1 }
      let ls = lineStarts[line - 1]
      map[line, default: [:]][start - ls] = end - ls
    }
    tokenEndColumns = map
  }

  // IndexStoreDB gives 1-based line / 1-based utf8Column
  func exactEndColumn(line: Int, utf8Column: Int) -> Int? {
    tokenEndColumns[line]?[utf8Column - 1]
  }
}
```
`makeDocument` change at the `singleLineRange` call site: pass `exactEndColumn: refinement?.exactEndColumn(line: location.line, utf8Column: location.utf8Column).map(Int32.init)`.

## Validation Architecture

**Framework:** Swift Testing (`@Suite`/`@Test`), `Tests/scip-swiftTests/`. Quick: `swift test --filter SwiftSyntaxRefiner`. Full: `swift test` (CI runs it on macos-26).

| Req | Behavior | Type | Command | Exists? |
|-----|----------|------|---------|---------|
| RANGE-01 | anchor→exact end (emoji, greet def+ref, getter drift case) | unit | `swift test --filter SwiftSyntaxRefinerTests` | ❌ Wave 0 |
| RANGE-01 | PositionMapping uses exact end when present, approximates when nil | unit | `swift test --filter PositionMappingTests` | ❌ Wave 0 (file does not exist today) |
| RANGE-02 | F4 fixture end-to-end: all expected [start,end) byte columns | integration | `swift test --filter UnicodeRange` | ❌ Wave 0 (new `Fixtures/UnicodeRangeFixture`) |
| RANGE-03 | broken source still yields `.present` token map; nil refinement → approximation; unreadable file → nil | unit | `swift test --filter SwiftSyntaxRefinerTests` | ❌ Wave 0 |
| REGRESS | MiniSwiftPackage pipeline + demangle suites unchanged; second-run byte-identity | integration | `swift test --filter IntegrationTests` / `IncrementalIntegrationTests` | ✅ must stay green |

**Re-baseline surface:** none — grep verified no test asserts `startCharacter`/`endCharacter`/`singleLineRange` today; `PositionMappingTests.swift` does not exist. New assertions are additive.

**Sampling:** per task `swift test --filter <suite>`; phase gate full `swift test` (budget ~2 extra min cold for the new dependency).

**Wave 0 gaps:** `SwiftSyntaxRefinerTests.swift`, `PositionMappingTests.swift`, `Fixtures/UnicodeRangeFixture` (+ its integration suite).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| swift-syntax (SwiftPM) | RANGE-01..03 | ✓ (verified resolve/build) | 602.0.0 exact | — |
| Swift 6.2.4 toolchain | pin match | ✓ (`.swift-version`) | 6.2.4 | — |
| Network (first resolve) | dependency fetch | ✓ locally; CI fetches once | — | vendor if CI is offline (not needed) |

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | SwiftSyntax is a memory-safe, non-throwing parser over untrusted repo source; file read bounded; no eval |
| V2/V3/V4/V6 | no | Local CLI, no auth/session/crypto surface change |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | CI macos-26 resolves swift-syntax 602.0.0 identically (same pinned toolchain) | D1 | CI failure on first build; fixed by pin, low risk |
| A2 | Anchor hit rate stays ~100% on real-world repos beyond the two fixtures | F2 | More fallbacks than expected — output still valid, just approximate (RANGE-03 covers) |

## Open Questions

1. **Homebrew stance on a 24 MB binary** — measured (F6), accepted in D1, but the distribution channel owner should confirm at release time.
2. **Macro-heavy repos** — probes covered none; the nil-lookup fallback is the safety net, and A2 flags real-world validation for the verifier phase.

## Sources

### Primary (HIGH)
- Empirical scratch binaries (2026-08-17, Swift 6.2.4/Xcode 26): token offset/trivia semantics; anchor↔token join on two real IndexStoreDBs (16/16, 13/13); error-node token recovery; release build size/time; parse perf
- Repo source read this session: `PositionMapping.swift`, `SCIPIndexBuilder.swift`, `IndexManifest.swift`, `CacheStore.swift`, `IndexCommand.swift`, `Package.swift`, `Version.swift`, `IntegrationTests.swift`, indexstore-db checkout `SymbolLocation.swift:22-24` (`public var line: Int`, `public var utf8Column: Int`)
- `git ls-remote` + release page: swift-syntax 602.0.0 tag exists, GPG-signed, swiftlang org
- `.planning/research/ARCHITECTURE.md` (milestone hybrid contract; refiner placement; SourceLocationConverter warning — confirmed empirically here)

## Metadata

**Confidence breakdown:** token/anchor mechanics HIGH (empirical); architecture HIGH (source-read + matches milestone research); CI/Homebrew impact MEDIUM (A1 + open question).
**Research date:** 2026-08-17. **Valid until:** 2026-09-16 (toolchain-pinned, stable).
