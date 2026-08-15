# Architecture Patterns: v0.3.0 Readable Indexes Integration

**Project:** scip-swift
**Researched:** 2026-08-15
**Mode:** Project architecture research (milestone: demangling, exact ranges, `-destination`, doc comments)
**Overall confidence:** HIGH (all load-bearing claims verified by running code against Swift 6.2.4 / Xcode 26 toolchain, or read directly from this repo's source and git history)

## Ground Truth Established by Verification

Every architectural recommendation below rests on these empirically verified facts:

1. **`swift-demangle` cannot demangle USRs as-is.** USRs start with `s:`; the demangler expects mangled
   names. Feeding `s:4null7GreeterC5greet4nameS2S_tF` returns the input unchanged. Rewriting the prefix
   to `_$s` works:
   `_$s4null7GreeterC5greet4nameS2S_tF` → `null.Greeter.greet(name: Swift.String) -> Swift.String`.
   (Real USRs extracted from a live index-store record; tested via `xcrun swift-demangle --compact`.)
2. **ObjC/clang USRs (`c:...`) do not demangle** (`swift_demangle_getDemangledName` returns length 0).
   These must keep the current opaque fallback.
3. **`libswiftDemangle.dylib` ships in the active Xcode toolchain** at
   `<toolchain>/usr/lib/libswiftDemangle.dylib` and exports the C symbol
   `swift_demangle_getDemangledName` (verified via `dlopen` + `dlsym` + call). The `SwiftDemangle`
   Swift module is **not** importable (`no such module 'SwiftDemangle'`).
4. **SwiftSyntax is not bundled with the toolchain** — it must be added as a Package.swift
   dependency. `swift-syntax 602.0.0` resolves against the pinned Swift 6.2.4 toolchain with official
   prebuilt downloads and compiles/runs (verified end-to-end). It requires macOS 10.15+, which is
   compatible with scip-swift's macOS 14 floor.
5. **SwiftSyntax 602 exact-range and doc-comment APIs verified by running code:**
   `Parser.parse(source:)` → tree; `node.positionAfterSkippingLeadingTrivia.utf8Offset` /
   `node.endPosition.utf8Offset` give exact 0-based UTF-8 byte token bounds (`func name: greet
   utf8: 116 < 121`); doc comments are `.docLineComment(String)` pieces in leading trivia and
   regular `//` comments are correctly excluded.
6. **SCIP `documentation` field semantics** (vendored `Protos/scip.proto` L261-263, generated code
   L1450-1456): `SymbolInformation.documentation` is `repeated string` markdown intended for
   docstrings; `signature_documentation` carries only code-formatted signatures.
7. **Critical regression discovered: the xcodebuild backend is unreachable from the CLI.**
   `IndexCommand.indexOneRepo` (`Sources/scip-swift/Commands/IndexCommand.swift`) constructs only
   `SwiftPMBuildRunner` in both its branches — the `case .xcodebuild:` dispatch existed in commit
   `aadc82d` but was lost during the `indexOneRepo` extraction in commit `c06c050`. A repo detected
   as `.xcodebuild` gets `swift build` run against it and fails. `--destination` work is blocked
   until this is restored.

## Recommended Architecture

The five-stage pipeline and the six-mapper layering are preserved. v0.3.0 adds one new pipeline
concern — a **per-file source-refinement pass** that sits between Index access and SCIP mapping —
and one new pure mapping input — a **USR demangler**. Nothing moves stages; the mappers stay
stateless enums (demangler memoization lives in a wrapper object owned by the builder, not inside
the formatter).

### The Hybrid Contract (answers "is SwiftSyntax acceptable?")

PROJECT.md lists "Source code parsing" as Out of Scope with the rationale "the compiler's
IndexStore is the data source; no custom Swift parser." A hybrid is architecturally acceptable
**only under a strict division of authority**, which should be written down as an evolved decision:

| Concern | Authority | SwiftSyntax's role |
|---|---|---|
| What symbols exist, USR identity, kinds, roles, relations, enclosing scope | IndexStoreDB (compiler) | **None** — never used for symbol discovery |
| Where an occurrence's token starts/ends (exact range) | IndexStoreDB gives the anchor; SwiftSyntax refines start→end | Presentation refinement only |
| Doc comments | SwiftSyntax (IndexStoreDB does not expose doc text) | Extraction keyed by definition anchors from the index |
| Signatures | IndexStoreDB (`Symbol.kind`/`name`) today; demangled form can enrich later | None in this milestone |

Rules that keep this principled:

- Every SwiftSyntax-derived refinement must have a **fallback to current behavior** (approximate
  range, missing documentation) when the tree has no match at the index anchor. The emitted index
  must be valid and `scip lint`-passing even if refinement fails for every occurrence (parse
  error, macro-expanded file, generated code).
- Refinement is keyed **by offsets coming from the index**, never by walking the tree independently.
  This preserves "zero false positives": if the compiler didn't emit an occurrence, we never invent one.

This is an evolution of the Out of Scope entry (it targeted building a custom symbol
extractor), not a violation of it. Update PROJECT.md wording at roadmap time.

### Component Boundaries After v0.3.0

| Component | Status | Responsibility | Communicates With |
|---|---|---|---|
| `ScipSwiftCommand` / `IndexCommand` | **Modified** | New `--destination` flag; restore `.xcodebuild` dispatch | `XcodeProjectLocator`, runners |
| `XcodebuildBuildRunner` | **Modified** | Optional `-destination <value>` insertion; nil = today's behavior | `SubprocessRunner` |
| `USRDemangler` (new, `SCIPMapping/`) | **New** | USR → demangled string, with `s:`→`_$s` rewrite, batch memoization, opaque fallback for `c:`/failures | `SCIPSymbolFormatter` |
| `DemangledNameParser` (new, `SCIPMapping/`) | **New** | Demangled string → descriptor chain pieces (module, containers, name+labels) | `SCIPSymbolFormatter` |
| `SCIPSymbolFormatter` | **Modified** | Emit descriptor-chain symbol strings from demangled pieces; opaque USR fallback | `USRDemangler`, `DemangledNameParser` |
| `SwiftSyntaxRefiner` (new) | **New** | Per-file parse; token anchor→exact-range map; definition-anchor→doc-comment map | `SCIPIndexBuilder`, `PositionMapping` |
| `PositionMapping` | **Modified** | Lookup-or-approximate: exact range from refiner, else display-name approximation | `SwiftSyntaxRefiner` |
| `SCIPIndexBuilder.makeDocument` | **Modified** | Build refinement context once per file; attach `documentation` to definitions | All mappers, `SwiftSyntaxRefiner` |
| `SwiftPMBuildRunner`, `IndexStoreLoader`, `SwiftFileDiscovery`, Caching | Unchanged | — | — |

## Feature-by-Feature Integration

### 1. Demangling — hooks in the formatter, NOT a post-pass

**Decision: hook at `SCIPSymbolFormatter` level, with the demangler memoized outside it.**

- **Why not a post-pass:** the symbol string is the primary key woven through `document.symbols`,
  `document.occurrences`, `externalSymbols`, `RelationshipMapping` output, and
  `enclosingSymbol`. Rewriting post-hoc means remapping every cross-reference and re-sorting —
  strictly worse than producing the final string at the single point where all of them originate
  (today every one of those paths already funnels through
  `SCIPSymbolFormatter.globalSymbolString`).
- **Why not inside the formatter as-is:** the formatter is a stateless enum and is called per
  occurrence (hot path). Demangling must be memoized per-run. Keep the enum pure; give the builder
  (or a `DemanglingContext` struct) a `[USR: String]` cache and pass demangled pieces in, or pass
  the memoizer as a parameter. Preserve the existing "enum namespace, static functions" convention.
- **Primary mechanism — recommendation: one batched `swift-demangle` subprocess per index run.**
  Collect all unique global USRs after the occurrence loop's first pass (or lazily, per document),
  feed them to `xcrun swift-demangle --compact` on stdin (one `_$s`-rewritten name per line), read
  back the results. Verified working. One process total, no C interop, no dlopen path fragility.
  - dlopen of `libswiftDemangle.dylib` + `swift_demangle_getDemangledName` is the verified
    optimization path if subprocess overhead ever matters; keep it out of v0.3.0 for simplicity.
- **Symbol string shape:** demangled `null.Greeter.greet(name: Swift.String) -> Swift.String`
  → descriptor chain `Greeter#greet(name:).` (type suffix `#`, method suffix `.`; the module
  already occupies the `<package>` field, so strip the demangled module prefix). Parens/colons are
  not identifier characters, so `escapeIdentifierName` backtick-wraps them — the grammar already
  supports this, no formatter surgery needed beyond choosing the descriptor split.
  - VERIFY: descriptor parsing of demangled edge cases — generic parameters, operators,
    accessors (`subscript.modify`), local functions (`...F...L...` USR suffixes), property
    getters/setters. Mitigation: build a corpus test from scip-swift's own index store plus
    `Fixtures/MiniSwiftPackage`; any parse failure must fall back to opaque-USR wrapping, never
    crash or emit an invalid string.
- **Locals:** `local <n>` strings are unaffected — `LocalSymbolNumberer` untouched.
- **Cache invalidation:** cached `Scip_Document`s embed old symbol strings. `IndexManifest.converterVersion`
  already keys off `ScipSwiftVersion.version` — the v0.3.0 version bump invalidates every stale
  cache automatically. No manifest schema change needed. Flag for the roadmap: tests asserting
  byte-identical second-run output still hold *after* the version bump.

### 2. Exact Ranges — a refinement pass feeding `PositionMapping`

**Data flow change:** introduce a per-file refinement context, built once, consumed by the
occurrence loop.

```
SwiftFileDiscovery → filePath
SwiftSyntaxRefiner.refine(filePath) → SourceRefinement {
  exactRange(line: Int32, utf8Column: Int32) -> (start, end)?   // nil = no token at anchor
  docComment(line: Int32, utf8Column: Int32) -> [String]?       // definitions only
}
```

- **Anchor matching must be self-computed, not via `SourceLocationConverter` inverse.** Build the
  map by walking tokens, computing each token's line from a line-start offset table and its column
  as `utf8Offset - lineStartOffset` (UTF-8 bytes). This matches IndexStoreDB's
  `SymbolLocation` (1-based line, 1-based UTF-8-byte column) exactly.
  VERIFY: SwiftSyntax's `SourceLocationConverter.column` semantics (UTF-8 vs UTF-16) — do not rely
  on it for the key; the self-computed table sidesteps the question.
- `PositionMapping` becomes: exact range if the refiner has one for the anchor; otherwise the
  existing display-name approximation (keep `approximateTokenLength` as the fallback path — it is
  also the behavior for files that fail to parse).
- One parse per file, shared with doc-comment extraction (see below). SwiftParser is
  editor-grade fast; scip-typescript parses all sources too. Cost is acceptable, but the refiner
  must skip files already served from the cache (cached documents bypass `makeDocument` entirely —
  unchanged flow).
- Definition vs reference anchors both refine: the anchor hits the name token in both cases
  (verified conceptually against how IndexStoreDB emits anchors; VERIFY against the Xcode fixture
  for compound names — operator definitions, `init?`, attribute-wrapped declarations).

### 3. Doc Comments — same parse, keyed by definition anchors

- In `makeDocument`, when `occurrence.roles.contains(.definition)` and the symbol is non-local,
  look up the refiner's doc-comment map at the anchor. Extract `.docLineComment` pieces from the
  declaration node's leading trivia (verified: `///` captured, `//` excluded), strip the leading
  `///` and one space, and append to `symbolInformation.documentation`.
- SCIP `documentation` is `repeated string`; scip-typescript emits one string per line.
  VERIFY the exact convention against a scip-typescript-produced index (one line per element vs a
  single markdown blob) and match it.
- Do **not** put doc text into `signatureDocumentation` — the proto explicitly separates code
  signatures from docstrings; `SignatureMapping` stays as-is this milestone.
- Doc comments attach to `SymbolInformation` (per-symbol), which lands in `document.symbols` —
  no change to `Scip_Document` structure itself; only richer `SymbolInformation`.
- Cached documents already carry whatever documentation existed when cached — the version-bump
  invalidation covers this too.

### 4. `-destination` — parameter on the runner, flag on the CLI, and one prerequisite fix

**Prerequisite (must land first):** restore the `.xcodebuild` dispatch in
`IndexCommand.indexOneRepo` (the lost `case .xcodebuild:` branch from commit `aadc82d` —
`XcodeProjectLocator.workspaceOrProjectArguments` + `resolveScheme` + `XcodebuildBuildRunner`
construction). Until then, `--destination` would be a flag on a code path the CLI can't reach,
and every Xcode-project repo fails with a misleading SwiftPM build error.

Integration, preserving the current no-destination decision:

- Add `let destination: String?` to `XcodebuildBuildRunner` (default `nil`). In the pure
  `arguments` property, insert `["-destination", value]` only when non-nil, positioned after
  `-scheme`/`-configuration` and before the build settings. Nil behaves **byte-identically** to
  today — the existing argument-list tests keep passing unchanged, which is the regression guard
  for the "don't break macOS-app repos" decision.
- Add `--destination` option to `IndexCommand`, thread through `indexOneRepo` → the xcodebuild
  branch only. Help text should recommend `generic/platform=iOS Simulator` for index builds.
  VERIFY: simulator generic destination + existing `CODE_SIGNING_ALLOWED=NO` overrides index
  iOS-only targets cleanly (signing is skipped, so no provisioning input phase). Device
  destinations (`generic/platform=iOS`) should be allowed but not recommended — indexing doesn't
  need a real device.
- `IndexManyCommand` deliberately does **not** get the flag in this milestone (repos may want
  different destinations; per-repo flags are scope creep — keep it manual).
- The existing comment block in `XcodebuildBuildRunner.arguments` explaining the no-destination
  rationale must be updated to say "no destination by default; `--destination` opts in" — otherwise
  the next reader "fixes" it again.

## New vs. Modified Summary

| File / component | New/Modified | Change |
|---|---|---|
| `Commands/IndexCommand.swift` | Modified | Restore `.xcodebuild` dispatch; add `--destination` |
| `Build/XcodebuildBuildRunner.swift` | Modified | Optional `destination`; conditional arg insertion; comment update |
| `SCIPMapping/USRDemangler.swift` | New | Batched demangling, prefix rewrite, fallback |
| `SCIPMapping/DemangledNameParser.swift` | New | Demangled string → descriptor pieces |
| `SCIPMapping/SCIPSymbolFormatter.swift` | Modified | Descriptor-chain output; opaque fallback; memoization injected |
| `SourceRefinement/SwiftSyntaxRefiner.swift` (new dir) | New | Per-file parse, anchor→range map, anchor→doc map |
| `SCIPMapping/PositionMapping.swift` | Modified | Exact-range lookup, approximation fallback |
| `SCIPMapping/SCIPIndexBuilder.swift` | Modified | Build refinement context per file; wire docs + demangling cache |
| `Package.swift` | Modified | Add `swift-syntax` 602.0.0 dependency (SwiftSyntax + SwiftParser products) |
| `Version.swift` | Modified | Bump to 0.3.0 (drives cache invalidation) |
| Tests | New suites | Demangler corpus, refiner range/doc fixtures, runner destination args, restored-dispatch integration |

## Suggested Build Order

1. **Restore xcodebuild dispatch** — prerequisite bug fix; tiny, independently testable
   (`XcodeIntegrationTests` already exercises the runner directly). Unblocks everything Xcode-side
   and stops shipping a broken advertised backend.
2. **`--destination` support** — depends only on 1; confined to Build/ + CLI; verified by the pure
   `arguments` property tests (fast, no Xcode needed) plus one fixture run. No output-format
   change, so no cache/consumer impact.
3. **USR demangling in `SCIPSymbolFormatter`** — independent of SwiftSyntax entirely; delivers the
   headline feature (readable names) with no new package dependency. Includes version bump +
   cache-invalidation check. Corpus test from the repo's own index store.
4. **SwiftSyntax dependency + exact ranges** — first new dependency; introduces `SwiftSyntaxRefiner`
   and the fallback path in `PositionMapping`. Falls back gracefully, so it can ship even with
   imperfect anchor matching.
5. **Doc comments** — reuses 4's parse and anchor maps; smallest marginal risk once the refiner
   exists; fills `SymbolInformation.documentation`.

**Ordering rationale:** 1→2 is a hard dependency (flag on unreachable code is dead code).
3 before 4 because it needs no new dependency and changes symbol identity — landing the riskiest
identity change before adding a second new subsystem isolates blame if consumers report issues.
4→5 is a hard dependency (shared per-file parse). Every step keeps `scip lint` green and the
fallback path exercised.

## Anti-Patterns to Avoid

- **Rewriting symbol strings in a post-pass.** The symbol string is the cross-reference key in five
  places; regenerate at the formatter, never mutate after assembly.
- **Using SwiftSyntax for symbol discovery.** One walk that emits occurrences not backed by the
  index re-introduces the false-positive risk the IndexStoreDB decision exists to avoid.
- **Making the demangler lossy-by-default.** Any demangle/parse failure must degrade to the opaque
  USR wrapper (still unique, still valid) — never drop the symbol or emit a placeholder.
- **Trusting `SourceLocationConverter` column semantics for anchor keys.** Compute line/col from
  UTF-8 offsets directly; the converter's column basis is unverified and a mismatch would silently
  break every refinement lookup.
- **Hardcoding the demangle library path.** If dlopen is used later, resolve the toolchain the same
  way `IndexStoreLoader` resolves `libIndexStore.dylib` (`xcrun --find swift`), never
  `/Applications/Xcode.app/...` literally.

## Sources

- Verified empirically (2026-08-15, Swift 6.2.4 / Xcode 26 toolchain): `swift-demangle` CLI on
  real index-store USRs; `dlopen`/`dlsym`/call of `swift_demangle_getDemangledName`; `SwiftDemangle`
  module import failure; `swift-syntax 602.0.0` resolve/compile/run incl. exact ranges and
  `.docLineComment` extraction (HIGH).
- Repo source: `SCIPIndexBuilder.swift`, `SCIPSymbolFormatter.swift`, `PositionMapping.swift`,
  `SignatureMapping.swift`, `XcodebuildBuildRunner.swift`, `XcodeProjectLocator.swift`,
  `IndexCommand.swift`, `BuildBackendDetector.swift`, `Protos/scip.proto`, `Generated/Scip.pb.swift`
  (HIGH).
- Git history: commits `aadc82d` (xcodebuild dispatch present) vs `c06c050` (lost during
  `indexOneRepo` extraction) (HIGH).
- Unverified items are marked VERIFY inline (demangled-name edge cases, `documentation` line
  convention, simulator-destination + signing interaction, `SourceLocationConverter` column basis).
