# Features Research: v0.3.0 Readable Indexes

**Project:** scip-swift
**Researched:** 2026-08-15
**Mode:** Inline orchestrator research (researcher subagents unavailable — provider 503 capacity errors; findings from targeted web research + codebase knowledge)
**Confidence:** MEDIUM-HIGH (peer-indexer behavior from public sources; specifics marked VERIFY where a claim wasn't directly checked)

## Category: Symbol Presentation

**Table stakes (every SCIP indexer has them):**
- Human-readable symbol names in `SymbolInformation.symbol` — scip-typescript emits `Class.method`, scip-rust emits crate-qualified paths, scip-java emits fully-qualified names. scip-swift currently emits opaque raw USRs wrapped in `swift <usr>` — the outlier.
- Enclosing-scope structure in the symbol scheme (scip-swift has this via relationships).

**Differentiators:**
- Demangled, fully-typed Swift names (`Module.Class.method(arg:) -> ReturnType`) — few indexers include full type signatures in the name; scip-rust does not. Having signatures already extracted (SignatureMapping), scip-swift can go further than peers.
- Documentation on hover (see below).

**Anti-features for this tool:**
- Custom name schemes not derived from compiler data — would break the "compiler data is authoritative" principle. Demangling IS compiler data (the demangler is the compiler's own library).

## Category: Occurrence Ranges

**Table stakes:**
- Exact start AND end positions for every occurrence — all peer indexers emit precise ranges (they parse source directly). scip-swift's approximated end columns (display-name length) drift on compound names; this is a correctness gap vs peers, not a nice-to-have.

**Differentiators:**
- Half-open ranges exact to the UTF-8 byte (SCIP convention) including multi-byte identifiers.

**Anti-features:**
- Whole-declaration ranges for references — SCIP wants the identifier token only.

## Category: Documentation

**Table stakes (peers):**
- scip-typescript: JSDoc → Markdown into `SymbolInformation.documentation` (repeated string). Hover docs in Sourcegraph come from this field.
- scip-rust: `///` rustdoc (Markdown by definition) → same field.
- scip-swift: currently emits signature documentation only (`signatureDocumentation`); the markdown `documentation` field is empty — parity gap.

**Differentiators:**
- `///` and `/** */` Swift Markdown doc comments extracted via SwiftSyntax leading trivia; combined with signatures gives hover parity with Xcode's quick-help.

**Anti-features:**
- Rendering/processing the Markdown beyond normalization (leave rendering to consumers).
- License-header extraction as "documentation".

## Category: Build Targeting (xcodebuild -destination)

**Table stakes:** SourceKit-based tools handle destinations via workspace context; CLI indexers typically document which platform they index. scip-swift's no-destination choice was deliberate (provisioning failures on app projects) but leaves iOS-only targets under-indexed.
**Differentiators:** optional, explicit `--destination` flag with nil default preserving current behavior.
**Anti-features:** auto-provisioning magic; destination autodetection that overrides user intent.

## Complexity / Dependencies Table

| Feature | Complexity | Depends on (existing) |
|---------|-----------|----------------------|
| Demangled names | Medium | SCIPSymbolFormatter, SignatureMapping (for combining) |
| Exact ranges | Medium | PositionMapping; adds swift-syntax parse pass |
| Documentation | Medium | Same swift-syntax pass as ranges |
| -destination | Low | XcodebuildBuildRunner; **prerequisite: restore lost `.xcodebuild` dispatch branch in IndexCommand.indexOneRepo (c06c050 refactor)** |

## Implications for Roadmap

1. All four features are additive to an already-working pipeline — no re-architecture.
2. The prerequisite dispatch fix must be its own early work item (Phase 6 candidate).
3. Ranges + docs share one SwiftSyntax pass — build them together after ranges land.
4. Demangling is independent of the others and can parallelize.
