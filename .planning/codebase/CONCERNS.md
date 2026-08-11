---
title: CONCERNS
focus: concerns
last_mapped_commit: 34a8c1e
---

# CONCERNS

**Analysis Date:** 2026-08-11

Technical debt, known issues, fragile areas, and limitations for `scip-swift`.

Source of truth for the limitations below: the implementation itself plus
`docs/research-scip-swift-limitations.md` (a code-grounded deep dive that cross-references the
exact `indexstore-db` checkout), `README.md` "Known limitations", and `docs/project-roadmap.md`.

## Severity legend
🔴 High · 🟠 Medium · 🟡 Low

## Indexing fidelity gaps (data dropped that IndexStoreDB provides)

- 🔴 **Relationships (inheritance / conformance / override) are silently discarded.** IndexStoreDB
  exposes `relations` (`.baseOf`, `.overrideOf`, `.extendedBy`, `.childOf`), but `SCIPIndexBuilder`
  never queries them, so `Scip_Relationship` / `Scip_SymbolInformation.relationships` is never
  populated. Peer indexers (scip-typescript, scip-rust) emit these. Fixable with the existing
  dependency (`SCIPIndexBuilder.swift`).
- 🟠 **`documentation` and `signature_documentation` are never set.** `SymbolInformation` gets only
  `symbol`, `displayName`, `kind` (`SCIPIndexBuilder.makeDocument`). SCIP marks these fields
  "strongly recommended"; hover/signature tooltips in consumers are bare. A basic signature is
  reconstructible from kind/subKind/name; full docstrings need source-comment parsing.
- 🟠 **`SymbolRoleMapping` is lossier than necessary.** Only `.definition`/`.write`/`.reference`/
  `.read` are mapped. It drops `.declaration` (SCIP has `ForwardDefinition = 0x40` for it), `.implicit`,
  and never sets SCIP's `Generated = 0x10` / `Test = 0x20` bits — even though
  `SymbolProperty.unitTest` directly identifies test symbols. Easy pure-function fix
  (`SymbolRoleMapping.swift`).
- 🟡 **`enclosing_symbol` is never set for locals.** IndexStoreDB `.childOf` carries this; trivial
  once relations are read.
- 🟡 **`isSystem` location flag is ignored.** `SymbolLocation.isSystem` marks stdlib/framework
  occurrences — the precise signal for true external symbols. The project instead infers
  `external_symbols` by a referenced-but-not-defined heuristic
  (`SCIPIndexBuilder.build`).

## Fundamental / spec-driven limitations (documented, accurate)

- 🔴 **Opaque USR symbol names (no demangling).** `SCIPSymbolFormatter` embeds the raw compiler USR
  verbatim as an escaped descriptor term (`scip-swift <pm> <module> . <usr>.`). Correct and stable,
  but not human-readable like peer indexers' descriptor chains. **Hard to fix** — needs Swift's
  mangling library (not packaged standalone) or a custom demangler. Roadmap defers to v1.0+
  (`SCIPSymbolFormatter.swift`, `docs/project-roadmap.md`).
- 🟡 **Approximate occurrence ranges.** IndexStoreDB records only a single 1-based anchor point per
  occurrence (no end column). `PositionMapping` approximates the end from display-name length,
  stopping at the first `(`. Correct ~95% for simple identifiers; drifts for compound names
  (`greet(name:)`). Fix requires source re-lexing — genuinely hard
  (`PositionMapping.swift`).
- 🟡 **No call-hierarchy role.** Real `scip.proto` `SymbolRole` has no `Call` bit, so call sites
  ride along on `.reference`/`.read`. **Unfixable** (spec) — `SymbolRoleMapping` + tests encode this
  intentionally.
- 🟠 **USR stability across Swift toolchain versions is not guaranteed by Apple.** Mitigated by
  pinning the toolchain (`.swift-version` = 6.2.4, `ToolchainInfo.pinnedSwiftVersion`) — a process
  control, not a technical fix.

## Build-pipeline fragility

- 🟠 **xcodebuild path has no integration test.** Only SwiftPM has a fixture
  (`Fixtures/MiniSwiftPackage`). `XcodebuildBuildRunner` is validated by arg-list assertions only
  (`XcodebuildBuildRunnerTests`), never a real `xcodebuild` end-to-end in CI. iOS-specific target
  behavior is unverified.
- 🟠 **xcodebuild passes no `-destination`** (targets generic "My Mac"). The code comment justifies
  this (a forced iOS destination breaks macOS-app projects; disabling signing avoids provisioning
  failure), but it leans on the scheme's default SDK. iOS-specific target configs may not all index
  as intended (`XcodebuildBuildRunner.arguments`).
- 🟡 **SwiftPM IndexStore path discovery is heuristic.** `SwiftPMBuildRunner.findIndexStore` scans
  `<scratch>/<triple>/<config>/index/store` by listing directories; a change in SwiftPM's scratch
  layout could silently break it (no pinned SwiftPM version — branch-based `indexstore-db`).
- 🟡 **macOS-only host; full rebuild each run.** Every invocation rebuilds the target repo from
  scratch; there is no incremental/cached index. Architectural, documented.
- 🟡 **`SubprocessRunner` uses an `@unchecked Sendable` escape hatch.** `DataBox` is documented as
  safe via a happens-before relationship with `DispatchGroup.wait()`, but it's the one place the
  Swift 6 data-race checker is deliberately bypassed (`SubprocessRunner.swift`). Review carefully on
  any refactor.

## Testing gaps

- 🟡 No direct unit tests for `BuildBackendDetector`, `XcodeProjectLocator.resolveScheme`,
  `ToolchainInfo.libIndexStoreDylibPath`, or `SwiftFileDiscovery` (the last is covered only
  indirectly via the integration test).
- 🟡 No coverage measurement configured (no `.codecov.yml`, no `--enable-code-coverage` in CI).

## Process / distribution

- 🟡 **No Homebrew formula.** Distribution is manual binary upload to GitHub Releases (arm64 only).
  x86_64 support is an open consideration (`docs/project-roadmap.md`).
- 🟡 **No formatter/linter config in-repo.** 2-space style is convention-enforced; no SwiftFormat/
  SwiftLint/.swiftformat file. Drift risk as contributors grow.
- 🟡 **`indexstore-db` is pinned to `branch: "main"`** (not a tag) in `Package.swift`. Reproducible
  via `Package.resolved`, but upstream `main` moves under the lock — re-resolving could pull a
  breaking revision. `swift-lmdb` is similarly branch-pinned (transitive).

## Security

- ✅ **No secrets, tokens, or credentials** anywhere in the codebase or generated docs.
- ✅ **No network egress.** All integration is local subprocess + local dylib + local filesystem.
- 🟡 The tool executes arbitrary build commands (`swift build` / `xcodebuild`) against
  user-supplied repo paths — by design, but it means indexing an untrusted repo runs that repo's
  build scripts. Document as a trust boundary if ever exposed as a service.

## TODO / Open items (from roadmap)

- Exact occurrence range recovery (deferred; hard).
- Demangled symbol names (deferred to v1.0+; hard).
- Homebrew distribution formula (low effort, not yet done).

---
*concerns focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
