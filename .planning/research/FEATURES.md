# Feature Research

**Domain:** SCIP (Sourcegraph Code Intelligence Protocol) indexer for Swift
**Researched:** 2026-08-11
**Confidence:** HIGH

## Feature Landscape

This research maps the gap between scip-swift v0.1.2 and peer indexers (scip-typescript, rust-analyzer/scip-rust, scip-python). Features are grounded in source-code analysis of each peer indexer and the canonical `scip.proto` / `scip lint` rules.

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete. For a SCIP indexer, "table stakes" = features that Sourcegraph and other SCIP consumers need to deliver the headline code-intelligence experience (go-to-definition, find-references, hover). scip-swift already has the first three; the remaining ones are the v0.2.0 focus.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Build → IndexStore → SCIP pipeline | Without it, no index exists at all | — | ✅ **DONE in v0.1.0** |
| SwiftPM + Xcode build backends | Real projects use both; one backend = half coverage | — | ✅ **DONE in v0.1.0** |
| `scip lint` passes | Lint is the correctness gate; failing = consumer rejects index | — | ✅ **DONE in v0.1.0** |
| Relationships (inheritance/conformance/override) | "Find implementations", inheritance hierarchy, protocol conformance links, override resolution are headline SCIP features. scip-typescript populates these; the `scip.proto` example uses `Dog implements Animal`. Without them, Sourcegraph's "Find implementations" returns nothing for Swift. | MEDIUM | **Highest-impact gap.** Data is already fetched from IndexStoreDB (`occurrence.relations`) and silently discarded. Mapping: `.baseOf`/`.extendedBy` → `is_implementation`, `.overrideOf` → `is_reference`, `.childOf` → `enclosing_symbol`. No architectural blocker — API exists. Risk: IndexStoreDB relation population depth for Swift must be empirically validated (Clang has rich relations; Swift depth is unverified). |
| `enclosing_symbol` for locals | SCIP consumers build symbol hierarchies / outline views. Locals without an enclosing symbol appear orphaned. rust-analyzer populates this via `enclosing_moniker`; scip-typescript derives it from the descriptor chain. | LOW | **Trivial once relationships are read** — `enclosing_symbol` comes from the same `.childOf` relation role. Blocked by relationships work. |
| Expanded SymbolRole bits | Test symbols should be tagged `Test`, generated code `Generated`, protocol requirements `ForwardDefinition`. scip-typescript sets `Definition`; rust-analyzer sets `Definition` + `ForwardDefinition` for forward decls. scip-swift maps only 4 of ~20 roles. | LOW | **Easiest win.** Pure-function additions to `SymbolRoleMapping`. `SymbolProperty.unitTest` directly identifies Swift Testing / XCTest symbols. No architectural change. |
| Signature documentation | Hover tooltips in SCIP consumers are bare without signatures. rust-analyzer populates `signature_documentation` from the type system; scip-typescript embeds signatures in `documentation` as markdown codeblocks. | MEDIUM | Basic Swift signatures (`func greet(name: String) -> String`) are reconstructible from IndexStoreDB `kind`/`subKind`/`displayName`. Full type info would need deeper IndexStoreDB queries or source re-lexing. |
| Xcode path end-to-end test fixture | The Xcode build path is validated by argument-list assertions only — no real `xcodebuild` runs in CI. A regression here breaks Xcode-only projects silently. scip-typescript and scip-python both have integration fixtures. | LOW | Create a minimal `.xcodeproj` fixture and a CI step that builds it. Mostly test infrastructure, not production code. |

### Differentiators (Competitive Advantage)

Features that set scip-swift apart. Not required for parity, but valuable — and several are uniquely enabled by scip-swift's compiler-index data source.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Source-comment docstring extraction | scip-typescript gets docstrings from the compiler API (`getDocumentationComment`). rust-analyzer gets them from `///` comments via its analysis. scip-swift has neither because IndexStoreDB doesn't return them. Parsing `///` and `/** */` comments from source would be a unique win — Swift's doc-comment conventions are well-defined. | MEDIUM | Requires source-file reading + comment parsing aligned to symbol anchor positions. IndexStoreDB gives line/column anchors; map to the preceding doc-comment block. SwiftSyntax could help but is a new dependency. |
| `isSystem`-based external symbol classification | IndexStoreDB's `SymbolLocation.isSystem` authoritatively marks stdlib/framework occurrences. scip-swift currently uses a heuristic (referenced-but-not-defined). Using `isSystem` directly would be more correct than scip-typescript's package-resolution approach. | LOW | Easy correctness improvement. Swap heuristic for authoritative flag in `external_symbols` classification. |
| Xcode `-destination` auto-resolution | scip-swift currently builds with no `-destination` (generic "My Mac"), meaning iOS-only targets may not fully index. Auto-detecting and targeting the scheme's native SDK (without breaking macOS-app projects) would improve coverage for iOS codebases — a Swift-specific problem no other indexer faces. | MEDIUM | Requires scheme parsing to pick a valid destination. Trade-off documented in `XcodebuildBuildRunner.swift:24-31`. |
| `typed_range` (new SCIP 0.4+ encoding) | scip.proto now has `single_line_range` / `multi_line_range` oneofs. scip-swift still uses the deprecated `repeated int32 range`. So do both peer indexers — adopting typed ranges early would be a forward-looking quality signal. | LOW | Pure mapping change in `PositionMapping`. All peers still use deprecated form; not urgent, but costs little. |
| `enclosing_range` on occurrences | rust-analyzer and scip-typescript both emit `enclosing_range` (the bounds of the enclosing definition/expression AST node) for breadcrumbs, call hierarchies, and expand-selection. scip-swift doesn't. IndexStoreDB gives anchor points only — full enclosing ranges need source-file lexing. | MEDIUM | Would need source re-lexing or SwiftSyntax to get definition body bounds. Defer unless breadcrumb support is requested. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems — scope creep, complexity, or diminishing returns.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Demangled (human-readable) symbol names | Users see `_$s5Hello7GreeterC7sayHelloyySSF` in SCIP output and want `Hello.Greeter.sayHello()` | Requires the Swift compiler's mangling library (not publicly packaged for standalone use) or a custom demangler. ~20+ hours of work, fragile against mangling format changes, deferred to v1.0+ in roadmap. Correctness is unaffected — USRs resolve fine. | Defer to v1.0+. Keep `displayName` (already set from IndexStoreDB) as the human-readable label in the meantime. SCIP tools use `display_name` for rendering, not the raw symbol string. |
| Cross-run incremental indexing / caching | "Build is slow on every run" — users want to reuse prior IndexStore results | **No peer indexer does this.** scip-typescript's `--global-caches` is in-process only (CompilerHost cache for monorepo tsconfig projects). rust-analyzer's `scip` is a one-shot CLI. scip-python does full Pyright analysis each run. A cross-run cache adds a cache-invalidation layer (USR stability, toolchain versioning, IndexStore freshness) that is fragile and architecturally complex. | Let the *compiler* handle incrementalism: persistent scratch path so `swift build` itself reuses its incremental build cache. This is a flag/config change, not an indexer feature. Separate "index-only" mode (read existing IndexStore, skip build) is a cheaper win for CI. |
| Linux support | "Runs only on macOS is limiting" | `libIndexStore.dylib` and Apple SDKs are macOS-only. This is architectural, not a feature gap — documented and out of scope. | Keep macOS-only. Document the constraint. |
| Streaming protobuf serialization | "Large indexes use too much memory" | Only matters for 100k+ file codebases. Build time dominates far before memory does. Premature optimization for v0.2.0. | Defer to v0.2.0+. The in-memory approach works for typical repos. |
| Custom Swift source parser | "What if IndexStoreDB doesn't have what we need?" | The compiler's IndexStore is authoritative (zero false positives). Building a parallel parser duplicates work and creates drift. scip-typescript tried this route (compiler-backed, not regex). | Stay on IndexStoreDB. Use source re-lexing only for auxiliary data (docstrings, enclosing ranges), never for symbol resolution. |
| Call hierarchy (`Call` role) | "I want to see who calls this function" | **Unfixable in the SCIP spec.** `scip.proto` `SymbolRole` has no `Call` bit. Both scip-typescript and rust-analyzer drop call sites onto `.reference`. | Nothing to build. Document as a spec limitation. |
| Full `Relationship.is_type_definition` | "Go to type definition" | IndexStoreDB doesn't carry a clean "this variable's type definition is X" relation in the same way. Mapping would be lossy. `is_implementation` covers the high-value cases (inheritance, conformance). | Map `.baseOf`/`.extendedBy` to `is_implementation` and `.overrideOf` to `is_reference`. Leave `is_type_definition` empty unless a clear IndexStoreDB signal is found. |

## Feature Dependencies

```
[Relationships (inheritance/conformance/override)]
    └──unblocks──> [enclosing_symbol for locals]  (.childOf carries both)

[Relationships] ──enhances──> [isSystem external symbol classification]
                                       (both improve "Find implementations" accuracy)

[Expanded SymbolRole bits] (independent — pure mapper changes)

[Signature documentation] (independent — reconstructible from existing kind/subKind/name)

[Source-comment docstrings]
    └──requires──> [Source-file reading infrastructure] (new capability, no current dependency)
                          └──optional──> [enclosing_range on occurrences] (reuses same infra)

[Xcode end-to-end fixture] (independent — test infrastructure only)
```

### Dependency Notes

- **Relationships unblocks enclosing_symbol:** Both come from the same IndexStoreDB `occurrence.relations` array. `.childOf` → `enclosing_symbol`, `.baseOf`/`.extendedBy` → `is_implementation`, `.overrideOf` → `is_reference`. Build relationships first, get enclosing_symbol as a free byproduct.
- **Relationships enhances isSystem:** Both improve the accuracy of "Find implementations" — relationships add the links, `isSystem` corrects which symbols are external. Independent features but complementary in effect.
- **SymbolRole bits are fully independent:** Pure-function additions to `SymbolRoleMapping`. No dependency on anything else. Ship anytime.
- **Source-comment docstrings require a new capability:** scip-swift currently never reads source files beyond discovery. Docstring extraction needs line/column → source-line mapping + comment-block parsing. This infrastructure is a prerequisite for `enclosing_range` too, so building it once enables two features.

## MVP Definition

### Launch With (v0.2.0)

Minimum viable v0.2.0 — the set that closes the most impactful parity gaps without scope explosion. Rationale: relationships are the #1 gap (HIGH severity, data already fetched); the rest are low-cost mappers and one test-fixture addition.

- [ ] **Relationships** (inheritance, conformance, override) — the highest-impact missing feature; unlocks "Find implementations" and protocol/override navigation. Data already fetched, just needs mapping. Validate IndexStoreDB relation population for Swift empirically before committing.
- [ ] **enclosing_symbol for locals** — free byproduct of relationships work (`.childOf`). Populates the symbol hierarchy for local variables.
- [ ] **Expanded SymbolRole bits** — `Test`, `Generated`, `ForwardDefinition`. Easiest win; pure mapper changes. Tags Swift Testing symbols as tests.
- [ ] **Signature documentation** — basic signatures reconstructible from existing IndexStoreDB data. Improves hover tooltips from "bare" to "useful."
- [ ] **Xcode end-to-end fixture** — closes the last test-coverage gap in the build path. Prevents silent regressions for Xcode-only projects.
- [ ] **isSystem external symbol classification** — swap heuristic for authoritative flag. Cheap correctness win.

### Add After Validation (v0.2.x)

Features to add once core parity is validated — these need the source-reading infrastructure or deeper investigation.

- [ ] **Source-comment docstring extraction** — requires new source-file reading infrastructure. Adds hover docs from `///` comments. Build the infra once, reuse for `enclosing_range`.
- [ ] **typed_range adoption** — forward-looking quality signal. Costs little once the mappers are being touched.
- [ ] **Xcode `-destination` auto-resolution** — needs scheme parsing research. Improves iOS target coverage.
- [ ] **Index-only mode** (`--no-build`, reads existing IndexStore) — cheaper than full incremental indexing; lets CI reuse a build from a prior step. Avoids cache-invalidation complexity.

### Future Consideration (v1.0+)

Features to defer until post-v0.2.0 adoption is established.

- [ ] **Demangled symbol names** — hardest gap (20+ hours, compiler-library dependency or custom demangler). Deferred to v1.0+ in roadmap. Correctness unaffected; `displayName` covers rendering.
- [ ] **Cross-run incremental indexing / caching** — no peer does this; architecturally complex (cache invalidation, USR stability, toolchain versioning). Let the compiler handle incrementalism instead.
- [ ] **enclosing_range on occurrences** — needs source re-lexing. Low user demand unless breadcrumbs are explicitly requested.
- [ ] **Streaming protobuf serialization** — premature optimization; only relevant for 100k+ file repos.
- [ ] **Multi-repo indexing mode** — depends on stable symbol schemes across repos; useful for monorepos but not blocking single-repo adoption.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Relationships (inheritance/conformance/override) | HIGH | MEDIUM | P1 |
| enclosing_symbol for locals | MEDIUM | LOW (blocked by P1) | P1 |
| Expanded SymbolRole bits (Test/Generated/ForwardDefinition) | MEDIUM | LOW | P1 |
| Signature documentation (basic) | MEDIUM | MEDIUM | P1 |
| Xcode end-to-end fixture | MEDIUM | LOW | P1 |
| isSystem external symbol classification | LOW-MEDIUM | LOW | P2 |
| Source-comment docstring extraction | MEDIUM | MEDIUM (new infra) | P2 |
| Index-only mode (`--no-build`) | MEDIUM | LOW-MEDIUM | P2 |
| typed_range adoption | LOW | LOW | P2 |
| Xcode `-destination` auto-resolution | MEDIUM | MEDIUM | P2 |
| Demangled symbol names | HIGH | HIGH | P3 (v1.0+) |
| Cross-run incremental indexing | MEDIUM | HIGH | P3 |
| enclosing_range on occurrences | LOW | MEDIUM | P3 |
| Streaming serialization | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v0.2.0 launch (closes highest-impact parity gaps)
- P2: Should have, add when possible (quality + coverage improvements)
- P3: Nice to have, future consideration (high cost or deferred per roadmap)

## Competitor Feature Analysis

| Feature | scip-typescript | rust-analyzer (scip-rust) | scip-python | scip-swift (v0.1.2) | Our v0.2.0 Plan |
|---------|-----------------|---------------------------|-------------|---------------------|-----------------|
| **Data source** | tsc compiler API | rust-analyzer HIR (StaticIndex) | Pyright type checker | IndexStoreDB (compiler index) | Same (no change) |
| **Symbol names** | Human-readable descriptor chains | Human-readable moniker descriptors | Human-readable (Pyright) | ❌ Raw USR (opaque) | Keep USR; defer demangling to v1.0+ |
| **Relationships** | ✅ Ancestor walking (`is_implementation`/`is_reference`) | ❌ Hardcoded `Vec::new()` | Not verified (Pyright-based) | ❌ Dropped (data fetched, not mapped) | **Map from IndexStoreDB relations** |
| **Documentation** | ✅ Signature markdown + docstring | ✅ Doc comments + `signature_documentation` | ✅ Pyright docstrings | ❌ None | Basic signatures from kind/subKind/name; docstrings in v0.2.x |
| **signature_documentation** | Embedded in `documentation` | ✅ Separate `Signature` field | Not verified | ❌ Not set | Basic signatures (v0.2.0) |
| **enclosing_symbol** | Derived from descriptor chain | ✅ Via `enclosing_moniker` | Not verified | ❌ Not set | From `.childOf` relation |
| **enclosing_range** | ✅ AST node bounds | ✅ `definition_body` (incl. doc comments) | Not verified | ❌ Not set | Defer (needs source re-lexing) |
| **SymbolRole bits** | `Definition`, `ForwardDefinition` | `Definition` | `Definition`, `Test` | `Definition`, `Read`, `Write`, `Reference` (4 of ~20) | Add `Test`, `Generated`, `ForwardDefinition` |
| **External symbol classification** | Package resolution (`package.json`) | Moniker package (cargo) | pip environment | Heuristic (ref-but-not-def) | Use `isSystem` flag |
| **Cross-repo symbols** | `npm <name> <version>` scheme | `cargo <crate> <version>` scheme | `pip` + `--project-namespace` | `swift <module>` scheme (no version) | Stable module scheme |
| **Incremental indexing** | ❌ In-process cache only (`--global-caches`) | ❌ One-shot CLI (`prefill_caches`) | ❌ Full analysis each run | ❌ Full rebuild each run | Index-only mode (read existing IndexStore) |
| **Diagnostics** | ✅ `@deprecated` from JSDoc | Not emitted | Not verified | ❌ Not emitted | Not in scope (IndexStoreDB has diagnostics but not priority) |
| **typed_range** | ❌ (deprecated `repeated int32`) | ❌ (deprecated `repeated int32`) | Not verified | ❌ (deprecated `repeated int32`) | Adopt in v0.2.x (forward-looking) |

### Key Insight from Competitor Analysis

**rust-analyzer does NOT populate relationships** — its SCIP output hardcodes `relationships: Vec::new()`. This means scip-swift shipping without relationships is not unprecedented. However, scip-typescript (the most-used SCIP indexer) does populate them, and the `scip.proto` spec's own `Relationship` documentation is built around the inheritance/conformance use case. Relationships are the highest-value feature to add, but their absence is not a correctness violation — `scip lint` passes with zero relationships.

## Sources

- **SCIP spec (canonical proto):** `Protos/scip.proto` (local, vendored from scip-code/scip)
- **SCIP reference docs:** https://github.com/scip-code/scip/blob/main/docs/scip.md (HIGH confidence — official spec)
- **scip lint source:** `cmd/scip/lint.go` from scip-code/scip (HIGH — defines validation rules)
- **scip-typescript FileIndexer.ts:** `src/FileIndexer.ts` from sourcegraph/scip-typescript (HIGH — source code; relationships via `forEachAncestor`, documentation via `signatureForDocumentation` + `getDocumentationComment`)
- **scip-typescript ProjectIndexer.ts:** `src/ProjectIndexer.ts` (HIGH — `--global-caches` is in-process CompilerHost cache, not cross-run)
- **rust-analyzer SCIP CLI:** `crates/rust-analyzer/src/cli/scip.rs` (HIGH — source code; `relationships: Vec::new()` hardcoded, but populates `documentation`, `signature_documentation`, `enclosing_symbol`, `enclosing_range`, `display_name`)
- **scip-python README:** github.com/sourcegraph/scip-python (MEDIUM — Pyright-forked, `--project-name`/`--project-namespace` for cross-repo)
- **scip-rust README:** github.com/scip-code/scip-rust (HIGH — thin wrapper around `rust-analyzer scip`)
- **scip-typescript README:** github.com/sourcegraph/scip-typescript (HIGH — `--no-global-caches` flag for OOM mitigation confirms in-process cache nature)
- **Project limitations analysis:** `docs/research-scip-swift-limitations.md` (HIGH — code-grounded analysis of IndexStoreDB API surface)
- **Codebase concerns:** `.planning/codebase/CONCERNS.md` (HIGH — maps limitations to specific file/line locations)
- **Project roadmap:** `docs/project-roadmap.md` (MEDIUM — current v0.2.0 tentative scope)

---
*Feature research for: SCIP indexer for Swift (scip-swift v0.2.0)*
*Researched: 2026-08-11*
