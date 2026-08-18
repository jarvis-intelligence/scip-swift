# Phase 9: Symbol Documentation - Research

**Researched:** 2026-08-17
**Domain:** Doc-comment (`///`, `/** */`) extraction from SwiftSyntax trivia → `SymbolInformation.documentation`
**Confidence:** HIGH (every load-bearing claim probed this session against swift-syntax 602.0.0 / Swift 6.2.4 via scratch tests run inside the repo's own build)

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOCS-01 | `///` and `/** */` doc comments as Markdown in `SymbolInformation.documentation` | Trivia taxonomy probed (§F1/F2); anchor→name-token alignment probed (§F4); normalization rules derived from raw piece text (§F3) |
| DOCS-02 | Non-doc `//`, license headers, comments on non-declaration tokens excluded | License header lands on `import`'s leading trivia as `lineComment` — excluded by kind filter alone (§F2); noise cases probed (§F2) |
| DOCS-03 | Exactly one SwiftSyntax parse per file per run — shared with Phase 8 refiner | Single `Parser.parse` call site exists (§F6); doc map built in same init walk; construction + parse-count-hook proof (§D5) |
</phase_requirements>

## Summary

Documentation is pure trivia classification + normalization, and SwiftParser already did the classification: `docLineComment`/`docBlockComment` vs `lineComment`/`blockComment` are **distinct enum cases** — no text heuristics needed for the doc-vs-comment split (only `////` needs an explicit text check). Doc comments attach as leading trivia of the **declaration's first token** — the `@` of the attribute list when attributes precede the declaration (probed: `@inline(__always) public func compute` carries its doc on `@`). The decisive alignment fact: IndexStoreDB definition anchors land on the **declaration's name token** (`compute` anchor (22,14) = name token, not `@`), while the doc sits on the *first* token — so the doc map MUST be keyed by the name-token anchor, never by the first-token anchor. The refiner already parses once and stores the tree (`Parser.parse` at SwiftSyntaxRefiner.swift:25 `[VERIFIED: read this session]`); extending its init to also build a doc map satisfies DOCS-03 by construction. Cache is free: `CacheStore` serializes the whole `Scip_Document` and `documentation` is a field of `Scip_SymbolInformation` (`public var documentation: [String] = []`, Scip.pb.swift:1450-1456 `[VERIFIED: read this session]`) — cached docs round-trip with zero cache changes.

**Primary recommendation:** Extend `SwiftSyntaxRefiner` to walk `DeclSyntax` nodes in its existing init, collect doc trivia from the decl's first token, normalize (§D4), key by the decl's **name-token anchor** (0-based line/byte-col, same convention as `exactEndColumn`); `makeDocument` sets `symbolInformation.documentation = [doc]` on definition occurrences whose anchor hits the map.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| What is documented (decl set) | SwiftSyntax tree | — | IndexStoreDB records no doc comments; tree is the only source |
| Anchor ↔ doc association | `SwiftSyntaxRefiner` (new doc map) | `SCIPIndexBuilder.makeDocument` (lookup/write) | Refiner owns the single parse; builder owns protobuf assembly |
| Doc/comment classification | SwiftParser trivia taxonomy | Own `////` check | Distinct enum cases (probed); `////` is the sole text-rule exception |
| Markdown normalization | Own pure static function in refiner | — | No library; simple text transforms (§D4) |
| One-parse contract | `SwiftSyntaxRefiner.init` (sole parse site) | parse-count test hook | Construction guarantee + cheap testable proof |
| Cache round-trip | `CacheStore` (unchanged) | protobuf `documentation` field | Whole-document serialization already carries it |

## Key Verified Facts (empirical, this session)

**F1 — Trivia taxonomy & attachment** `[VERIFIED: probe P0/P1]`: raw dump shows `docLineComment("/// Struct doc.")`, `docLineComment("///")` (empty doc line), `lineComment("// License header line 1")`, `docBlockComment("/**\n Block doc first.\n - parameter x: an int\n */")`. Doc trivia attaches to the **declaration's first token**; with `@inline(__always) public func compute`, the doc is on `@` (probe: `firstTok='@' docPieces=["docBlock"]`).

**F2 — Exclusion falls out of the kind filter** `[VERIFIED: probe P3]`: the license `//` header lands on the `import` token as `lineComment` pieces — filtered out by kind. `// noise between doc and decl` after a `///` doc: both pieces sit on the decl; taking only doc-kind pieces yields just the doc. A trailing `// noise` after a statement is trailing trivia — never seen by a leading-trivia walk. **Caveat:** `//// not-a-doc` IS classified `docLineComment("//// b")` (probe P4) — SwiftParser calls any `////+` a doc comment (TriviaParser.swift:178-181: `is(offset: 1, at: "/")` decides). DOCS-02 needs an explicit rule: drop doc-line pieces whose content (after `///`) starts with `/`.

**F3 — Normalization inputs from raw piece text** `[VERIFIED: probe P4]`: `docLineComment` text **includes** `///`; `docBlockComment` text **includes** the `/**` and `*/` wrappers. Multiple `///` pieces arrive as separate pieces in reading order (`/// Var doc line 1.`, `/// Var doc line 2.`).

**F4 — Anchor alignment (the decisive probe)** `[VERIFIED: probe P2, real IndexStoreDB build]`: definition anchors land on: the name token for named decls (`compute` (22,14), `value` (10,13), `Finalizer`, `Whole`, `tight`, enum-case elements `red` (47,7)/`blue` (49,7)); the `init`/`deinit` **keywords** for constructors/destructors ((13,9), (42,2)); the extended-type's first token for extensions (`Documented` (56,10)). Doc trivia rides the decl's **first** token (`@`/`public`/`func`), NOT the name token — a first-token-keyed doc map would miss every attributed decl. **Key at the name-token anchor.** Accessor definitions (`getter:value`) anchor at the same point as the property name token (doc-inheritance decision in D3). Params anchor at their name token but param decls never carry doc trivia in practice (see D3).

**F5 — One-parse status quo** `[VERIFIED: read Sources this session]`: single `Parser.parse` in Sources/ (SwiftSyntaxRefiner.swift:25); `syntaxTree` stored but used only for the token map. `makeDocument` instantiates the refiner once per file (SCIPIndexBuilder.swift:155). Cache hits skip `makeDocument` entirely (SCIPIndexBuilder.swift:53-59).

**F6 — Fixture status** `[VERIFIED: read this session]`: Greeter.swift has **no doc comments**, and IntegrationTests assert exact line numbers there (`line == 1`, `line == 8`, IntegrationTests.swift:66-72) — inserting doc lines would shift them. **New fixture required**; do not edit MiniSwiftPackage. No existing fixture uses attributes (grep) — attribute-interleaving must be in the new fixture.

## Decisions

**D1 — Doc map lives in `SwiftSyntaxRefiner` (same parse).** In the existing init, after `tokenEndColumns`, walk decls: read first-token leading trivia, filter doc kinds (+ `////` rule), normalize (D4), key by name-token anchor via the existing line-start table: `docsByAnchor[(line, col)] = normalized`. Lookup `documentation(line:utf8Column:) -> String?` takes IndexStoreDB's 1-based values, mirroring `exactEndColumn`'s contract (nil = miss, never an error). Manual recursion matches the codebase's no-visitor style; stays a struct with static helpers per repo convention.

**D2 — Name-token extraction per decl kind.** `decl.asProtocol(NamedDeclSyntax.self)?.name` (covers class/struct/enum/protocol/func/typealias — probe verified for `Documented`, `compute`, `Finalizer`, `Whole`, `extra`, `tight`), plus explicit fallbacks: `VariableDeclSyntax` → `bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier`; `InitializerDeclSyntax` → `initKeyword`; `DeinitializerDeclSyntax` → `deinitKeyword`; `ExtensionDeclSyntax` → `extendedType.firstToken`; `EnumCaseDeclSyntax` → each `elements[].name`. All casts compile and align on 602.0.0 (probe P1/P2). Multi-element `case a, b` shares one doc — acceptable, documented limitation.

**D3 — Builder wiring (accessors inherit; params get none).** In `makeDocument`, after signatureDocumentation: if `occurrence.roles.contains(.definition)` and the doc-map lookup hits, set `symbolInformation.documentation = [doc]`. Attach to **all** definition occurrences hitting the map — getter/setter USRs share the property's anchor and inherit the property doc (correct hover behavior; scip-typescript does the same). Params: `FunctionParameterSyntax` never carries doc trivia in Swift (documented via `- parameter` lines in the func doc) and the walk reads decl first tokens only — params naturally get no docs. **Re-baseline surface: none** — grep verified zero tests assert `documentation`/`signatureDocumentation`.

**D4 — Normalization spec (locked).**
- `.docLineComment(text)`: `content = text.hasPrefix("///") ? String(text.dropFirst(3)) : text`; **skip the piece when `content.hasPrefix("/")`** (the `////` case); else drop at most one leading space. `docLineComment("///")` → `""` (blank Markdown line — paragraph separator).
- `.docBlockComment(text)`: strip `/**` and `*/`, split on `\n`, drop empty artifact first/last lines, strip per-line leading `*` then one optional space.
- Pieces arrive in reading order; append lines in order; join multi-piece docs with `\n`.
- Emit a **single-element** `documentation` array (consumer-side join convention `[ASSUMED]` — A1).

**D5 — One-parse proof (DOCS-03).** By construction the only `Parser.parse` in Sources/ is the refiner's (F5). Test-proof: `SwiftSyntaxRefiner` gains a package-visible `static var parseCount` incremented in init; unit test asserts one refiner instance bumps it by exactly 1; integration test asserts pipeline parseCount == number of documents built (catches any second parse sneaking into the builder). Cheap, concrete, preferable to review-only assurance.

**D5b — Version/cache.** No bump. `Version.swift` is `0.3.0` (read this session: `static let version = "0.3.0"`), latest tag `v0.2.1`, 0.3.0 unreleased (Phase 8 D4 precedent). Residual: dev machines hold doc-less 0.3.0 caches under unchanged content hashes; self-heal on content change. Document in plan; don't bump the milestone version.

**D6 — New fixture `Fixtures/DocumentationFixture`** (SwiftPM package mirroring UnicodeRangeFixture): license `//` header; `///` single- and multi-line; `/** */` block with `- parameter` line and blank paragraph line; attribute-interleaved (`@inline(__always)` after doc); `//` noise between doc and decl; trailing `//` after a statement; `////` line; undocumented decls; enum with per-case docs; extension/init/deinit/typealias docs. Integration asserts exact per-symbol documentation strings and that license/noise/four-slash text appears in no documentation field.

## Common Pitfalls

### Pitfall 1: Attribute-attachment confusion
**What goes wrong:** Keying the doc map at the decl's first-token anchor — docs attach to `@` of `@inline(__always)` (F1), missing every attributed decl.
**Avoid:** Walk decls, key at the name token (F4). **Warning sign:** attributed fixture decls show empty docs.
### Pitfall 2: Anchor misalignment (name vs keyword tokens)
**What goes wrong:** Assuming uniform name-token anchors; `init`/`deinit` anchor on keywords, extensions on the extended type, enum cases on element names (F4).
**Avoid:** D2's per-kind extraction. **Warning sign:** init/deinit/extension docs missing while others work.
### Pitfall 3: Trivia-kind confusion (`////`, wrapper prefixes)
**What goes wrong:** (a) Trusting `docLineComment` classification — `////` is also `docLineComment` (F2). (b) Forgetting piece text includes `///`/`/** */` wrappers — output carries literal prefixes (F3).
**Avoid:** D4 rules + exact-string corpus tests. **Warning sign:** any `///` or `*` artifact surviving into output.
### Pitfall 4: Doc-vs-comment leakage
**What goes wrong:** `//` comments near decls become docs.
**Avoid:** Kind filter only — license headers land on `import` trivia as `lineComment` and drop naturally (F2). **Warning sign:** license text on the first symbol.

### Pitfall 5: Markdown normalization losses
**What goes wrong:** Flat-joining pieces kills paragraph breaks; block-comment `*` prefixes leak; `- parameter` loses its leading space.
**Avoid:** Preserve blank doc lines; per-line `*`-then-one-space strip (D4). **Warning sign:** single-paragraph output for multi-paragraph docs.
### Pitfall 6: Second parse sneaking in (DOCS-03)
**What goes wrong:** A separate extractor type re-parses per file.
**Avoid:** Extraction inside the refiner init (D1); parse-count hook (D5) makes it a failing test, not a review note. **Warning sign:** parseCount > document count.
### Pitfall 7: Accessor doc handling
**What goes wrong:** Either special-casing getter/setter USRs to skip docs (hover gap) or worrying about "wrong" inheritance.
**What's correct:** Accessor definitions share the property's name-token anchor (F4) and inherit its doc — same hover content as Swift-Docc for the property. **Avoid:** No accessor special-casing in code; assert inheritance in the integration test.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Doc/comment classification | `hasPrefix("///")` heuristics | Trivia cases `docLineComment`/`docBlockComment` | Parser already classifies; `////` is the only text rule |
| Second parse for docs | Separate extractor pass | Refiner's stored tree | DOCS-03 contract |
| Markdown rendering | HTML conversion | Verbatim passthrough | Out of scope (REQUIREMENTS.md: "consumers render") |
| Anchor math | Re-derived line/col | Refiner's line-start byte table | Already byte-correct (Phase 8) |

## Code Examples

### Refiner doc-walk skeleton (probe-verified casts, swift-syntax 602.0.0)
```swift
// Source: probe P1/P2 verified these casts compile and align on 602.0.0 / Swift 6.2.4
// inside SwiftSyntaxRefiner.init, after tokenEndColumns is built:
var docs: [AnchorKey: String] = [:]  // AnchorKey = 0-based (line, byte col) of the name token
for decl in syntaxTree.descendants(ofType: DeclSyntax.self) {  // or manual recursion
  guard let first = decl.firstToken(viewMode: .sourceAccurate),
        let doc = Self.docComment(from: first.leadingTrivia) else { continue }
  for token in Self.nameTokens(of: decl) {  // D2 per-kind extraction
    Self.assign(doc, toToken: token, lineStarts: lineStarts, into: &docs)
  }
}
// lookup mirrors exactEndColumn: 1-based in, 0-based map, nil on miss
```

### Builder wiring (SCIPIndexBuilder.swift, after the signatureDocumentation assignment ~line 189)
```swift
if occurrence.roles.contains(.definition),
   let doc = refiner?.documentation(
     line: occurrence.location.line, utf8Column: occurrence.location.utf8Column
   ) {
  symbolInformation.documentation = [doc]
}
```

## Validation Architecture

**Framework:** Swift Testing (`@Suite`/`@Test`); quick: `swift test --filter SwiftSyntaxRefinerTests`; full: `swift test` (CI, macos-26).

| Req | Behavior | Type | Command | Exists? |
|-----|----------|------|---------|---------|
| DOCS-01 | `///` single/multi-line + `/** */` block → exact normalized Markdown strings | unit | `swift test --filter SwiftSyntaxRefinerTests` | extend ❌ Wave 0 |
| DOCS-02 | `//`, license header, trailing, noise-between, `////` never in docs | unit | `swift test --filter SwiftSyntaxRefinerTests` | extend ❌ Wave 0 |
| DOCS-02/01 | attribute-interleaved doc reaches the attributed decl (name-token key) | unit | `swift test --filter SwiftSyntaxRefinerTests` | extend ❌ Wave 0 |
| DOCS-01/02 | pipeline: DocumentationFixture exact doc strings; noise absent in all fields; getter USR inherits property doc | integration | `swift test --filter IntegrationTests` | extend ❌ Wave 0 |
| DOCS-03 | refiner parseCount == documents built (hook) | integration | `swift test --filter IntegrationTests` | ❌ Wave 0 |
| DOCS-01 | cached document keeps documentation (round-trip) | unit | `swift test --filter CacheStoreTests` | extend ❌ Wave 0 |
| RANGE regress | Phase 8 exact-range assertions unchanged | integration | `swift test --filter IntegrationTests` | ✅ keep green |

**Sampling:** per task `--filter` suite; phase gate full `swift test`.
**Wave 0:** extend `SwiftSyntaxRefinerTests` (normalization corpus + anchor alignment + exclusions), `IntegrationTests` (DocumentationFixture + parse-count), `CacheStoreTests` (doc round-trip); new `Fixtures/DocumentationFixture`. No new framework/config needed.

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | SwiftSyntax: memory-safe, non-throwing parser over untrusted source; doc text flows verbatim into a protobuf field — no eval, no path derivation |
| V2/V3/V4/V6 | no | Local CLI; no auth/session/crypto surface change |

Markdown is consumer-rendered (out of scope per REQUIREMENTS.md) — no sanitization here.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Single-element `documentation: [String]` matches scip-typescript/scip-rust hover behavior | D3/D4 | Cosmetic; corpus tests pin our output regardless |
| A2 | Params get no docs (Swift convention: `- parameter` lines) is acceptable for v0.3.0 | D3 | Param hover gap vs peers |
| A3 | swift-syntax 602.0.0 has no public `docComment` convenience API (grep of checkout found none in SwiftSyntax module sources) | D1 | If it exists, prefer it over the hand walk |

## Open Questions (RESOLVED)

1. **`////` exclusion vs ecosystem parity** — SwiftFormat/SwiftSyntax's own `docByteRange` semantics unknown; we drop `////` (section-divider intent). Recommendation: drop it; revisit only if peer-indexer parity testing flags it.
2. **Accessor doc inheritance** — shipped by design (D3); if a consumer dislikes docs on getter/setter USRs, gate by `symbol.kind`. Recommendation: ship inheritance, assert it in the integration test.

## Sources

### Primary (HIGH)
- Empirical scratch probes P0–P4 (2026-08-17, in-repo swift-syntax 602.0.0 / Swift 6.2.4): raw trivia dumps (incl. `////` classification, `/** */` wrapper text); decl-walk attachment (docs on `@`/`public` first tokens); name-token anchor alignment joined against a real IndexStoreDB (struct/class/func/var/let/enum-case/typealias/init/deinit/extension all aligned); exclusion cases (license header, interleaved noise, trailing, four-slash). Scratch files deleted after probing (`git status` clean).
- Read this session: `SwiftSyntaxRefiner.swift` (sole `Parser.parse`:25; refiner instantiated once per file in `makeDocument`, SCIPIndexBuilder.swift:155), `Scip.pb.swift:1450-1456` (`public var documentation: [String] = []`), `CacheStore.swift:31-35` (whole-document serialization), `REQUIREMENTS.md` (DOCS-01..03), `IntegrationTests.swift:66-72` (line-number assertions), `SwiftSyntaxRefinerTests.swift` (suite to extend), `Package.swift` (swift-syntax 602.0.0 exact), `Version.swift` (`static let version = "0.3.0"`), `Greeter.swift` (no docs), `TriviaParser.swift:178-192` (doc-comment classification rules)
- grep: `Parser.parse` exactly once in Sources/; zero `documentation` assertions in Tests/; no `@` attributes in existing fixtures

## Metadata

**Confidence breakdown:** trivia/anchor mechanics HIGH (empirical, toolchain-pinned); normalization spec HIGH (raw text dumps); architecture HIGH (source-read + Phase 8 precedent); peer hover parity MEDIUM (A1/A2).
**Research date:** 2026-08-17. **Valid until:** 2026-09-16 (toolchain-pinned, stable).

> Decisions adopted: `////` dropped as noise (Task 2 text-drop rule); accessor doc inheritance ships by design and is asserted (Task 3).
