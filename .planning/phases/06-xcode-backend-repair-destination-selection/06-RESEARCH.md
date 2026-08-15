# Phase 6: Xcode Backend Repair & Destination Selection - Research

**Researched:** 2026-08-15
**Domain:** CLI build-backend dispatch (Swift ArgumentParser → xcodebuild subprocess)
**Confidence:** HIGH (every load-bearing claim verified against repo source, git history, or live xcodebuild runs)

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPAIR-01 | Restore `.xcodebuild` dispatch in `indexOneRepo`, verified by integration test vs fixture | Lost code recovered verbatim from `1c5ba8f` (§1); restoration point identified in current file |
| REPAIR-02 | `--destination <spec>` flag; nil default preserves behavior | Exact threading path + argument construction (§2); nil-identity regression guard identified |
| REPAIR-03 | Failed destination builds surface `xcodebuild -showdestinations` hint | Failure output captured live; error-case placement decided (§3) |
</phase_requirements>

## Summary

The xcodebuild backend is unreachable: `IndexCommand.indexOneRepo` constructs only `SwiftPMBuildRunner` in both cache branches, so any `.xcodeproj`/`.xcworkspace` repo gets `swift build` run against it and fails with a misleading SwiftPM error. Correction to prior research: git shows the `case .xcodebuild:` branch was dropped in commit **`0cdefd7`** (phase-3 cache integration, which rewrote `run()` around the cache branches), not `c06c050` — `c06c050` merely extracted the already-broken body into `indexOneRepo`. The exact lost code is recoverable verbatim from `1c5ba8f`.

`--destination` threading requires **no `BuildRunner` protocol change**: add a defaulted `let destination: String?` to the `XcodebuildBuildRunner` struct (Swift's memberwise init then keeps every existing call site and test compiling), insert `["-destination", value]` into the pure `arguments` property only when non-nil, and add an `@Option` to `IndexCommand` threaded through `indexOneRepo` (defaulted param keeps `IndexManyCommand` compiling). Verified live: explicit `-destination 'platform=macOS'` + the existing `CODE_SIGNING_ALLOWED=NO` overrides build the fixture and still produce `Index.noindex/DataStore`; a bogus destination fails with the exact marker `xcodebuild: error: Unable to find a device matching the provided destination specifier:`.

**Primary recommendation:** Restore dispatch first as a standalone fix (extract a `switch tool` helper both cache branches call), then thread `--destination`, then add a new `BuildError.xcodebuildDestinationFailed` case that fires only when `destination != nil` and the build exits non-zero, embedding full output plus a `-showdestinations` hint command.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Backend dispatch (.swiftpm vs .xcodebuild) | CLI orchestration (`IndexCommand`) | — | `indexOneRepo` owns runner construction and scratch/cache paths |
| Destination argument construction | `XcodebuildBuildRunner.arguments` (pure) | — | Pure property keeps it assertable without spawning Xcode |
| Destination failure hint | `BuildError` (new case) | Runner post-processing | `BuildError` is the project's exhaustive-error convention |
| Destination flag parsing | `IndexCommand` (ArgumentParser `@Option`) | — | Only consumer is the xcodebuild branch; `IndexManyCommand` deliberately excluded |

## 1. The Lost Dispatch Code (REPAIR-01)

**Bug verified in current source** `[VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:63-104]`: lines 89 and 99 each construct `SwiftPMBuildRunner(...)` unconditionally; no `switch tool` and no reference to `XcodebuildBuildRunner`/`XcodeProjectLocator` exists anywhere in the file.

**Lost code, verbatim from commit `1c5ba8f` (identical in `aadc82d`) `[VERIFIED: git show 1c5ba8f:Sources/scip-swift/Commands/IndexCommand.swift:46-74]`** — the `.xcodebuild` case of a private `produceIndexStore(tool:repoPath:workDirectory:)`:

```swift
case .xcodebuild:
  let projectArguments = try XcodeProjectLocator.workspaceOrProjectArguments(repoPath: repoPath)
  let resolvedScheme = try XcodeProjectLocator.resolveScheme(
    explicitScheme: scheme,
    projectArguments: projectArguments,
    repoPath: repoPath
  )
  let runner = XcodebuildBuildRunner(
    repoPath: repoPath,
    configuration: configuration,
    scheme: resolvedScheme,
    derivedDataPath: (workDirectory as NSString).appendingPathComponent("derived-data"),
    projectArguments: projectArguments
  )
  return try runner.produceIndexStore()
```

`XcodeProjectLocator` and `XcodebuildBuildRunner` still exist unchanged today `[VERIFIED: Sources/scip-swift/Build/XcodeProjectLocator.swift:1-64, Build/XcodebuildBuildRunner.swift:1-59]`, so restoration is pure wiring.

**Where to restore:** both the `persistentCache` else-branch (line ~88) and the no-cache branch (line ~98) currently inline `SwiftPMBuildRunner`. Extract one private static helper, e.g. `produceIndexStore(tool:repoPath:configuration:scheme:destination:scratchPath:) throws -> String`, called from both sites, with `switch tool` inside; for `.xcodebuild` use `derivedDataPath = (scratchPath as NSString).deletingLastPathComponent + "/derived-data"` (persistent-cache runs then keep derived data under the cache dir, temp runs under the temp dir — mirrors the original `(workDirectory)/derived-data` convention). Note `--index-only` currently only locates SwiftPM stores (`SwiftPMBuildRunner.findIndexStore`, line 76) — leave that asymmetry alone this phase.

## 2. `--destination` Threading (REPAIR-02)

**Protocol needs no change** `[VERIFIED: Sources/scip-swift/Build/IndexStoreBuildResult.swift:6-9]`: `protocol BuildRunner { func produceIndexStore() throws -> IndexStoreBuildResult }`. Destination is xcodebuild-specific config, not protocol surface.

**Runner change** `[VERIFIED: Sources/scip-swift/Build/XcodebuildBuildRunner.swift:6-38]` — struct fields are `repoPath, configuration, scheme, derivedDataPath, projectArguments`. Add:

```swift
let destination: String?  // default nil; Swift memberwise init makes it optional at call sites
```

In `arguments`, splice after `-configuration` / before `-derivedDataPath`:

```swift
var args = projectArguments + ["-scheme", scheme, "-configuration", xcodeConfiguration]
if let destination { args += ["-destination", destination] }
args += ["-derivedDataPath", derivedDataPath, /* existing settings..., */ "build"]
```

Nil must keep the list **byte-identical** to today — the seven existing `XcodebuildBuildRunnerTests` assertions are the regression guard. The comment block at `XcodebuildBuildRunner.swift:24-31` justifying no-destination must be rewritten to "no destination by default; `--destination` opts in" or the next reader will "fix" it back.

**CLI change** `[VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:25-27, 55-62]`: add `@Option(name: .long, help: "xcodebuild destination specifier...") var destination: String?` beside `scheme`; thread as a defaulted `destination: String? = nil` parameter on `indexOneRepo` (positional call sites in `IndexCommand.run()` line 36 and `IndexManyCommand.run()` `[VERIFIED: Sources/scip-swift/Commands/IndexManyCommand.swift:42-50]` then compile unchanged). Help text should recommend `generic/platform=iOS Simulator` for index builds; `IndexManyCommand` gets no flag (per-repo destinations are deferred scope). `CODE_SIGNING_ALLOWED=NO` et al. stay unconditional — empirically compatible with explicit destinations (see §5).

## 3. `-showdestinations` Hint (REPAIR-03)

**Live-captured failure output** (bogus destination, real fixture, Xcode 26.3) `[VERIFIED: local xcodebuild run 2026-08-15]`:

```
xcodebuild: error: Unable to find a device matching the provided destination specifier:
{ platform:iOS Simulator, OS:latest, name:Nonexistent Device 999 }
...
Available destinations for the "scip-swift-test" scheme:
{ platform:macOS, arch:arm64, id:..., name:My Mac }
```

**Placement:** new `BuildError` case, thrown from `XcodebuildBuildRunner.produceIndexStore()` — when `destination != nil && result.exitCode != 0`, throw `BuildError.xcodebuildDestinationFailed(exitCode:output:)` instead of `.buildFailed`. Rationale: `BuildError` is the project's exhaustive-error convention `[VERIFIED: Sources/scip-swift/Build/BuildError.swift:3-69]`, and the requirement says hint on *any* failed `--destination` build — matching specific xcodebuild error strings ("Unable to find a device", "ineligible destinations") is brittle across Xcode versions. Description embeds full untruncated `combinedOutput` (matching `.buildFailed`'s style, lines 43-47) plus a hint line like: `Hint: list valid destinations with: xcodebuild <projectArgs> -scheme <scheme> -showdestinations`. Verified `xcodebuild -showdestinations` exits 0 and prints `Available destinations for the "<scheme>" scheme:` `[VERIFIED: local run]`. Nil-destination failures keep the existing `.buildFailed` path untouched.

## 4. Tests & Fixtures Available

| Asset | State | Extension |
|---|---|---|
| `Tests/scip-swiftTests/XcodebuildBuildRunnerTests.swift` | 7 pure `arguments` assertions, helper `value(after:in:)` `[VERIFIED: file:1-73]` | Add: nil → no `-destination` token; non-nil → token + verbatim value, positioned after `-configuration`, before `CODE_SIGN` settings/`build`; memberwise-init call sites keep compiling via defaulted param |
| `Tests/scip-swiftTests/XcodeIntegrationTests.swift` | Real-xcodebuild fixture pipeline `[VERIFIED: file:1-63]` | Add: (a) REPAIR-01 end-to-end — call `IndexCommand.indexOneRepo(repoPath: fixture, ..., destination: nil)` (no cacheDir → temp dir) and assert `documents.count > 0`; (b) REPAIR-02 destination run with `platform=macOS` (verified builds + produces DataStore); (c) REPAIR-03 — bogus destination, assert thrown error is `xcodebuildDestinationFailed` and its description contains `-showdestinations` (run takes ~60s: xcodebuild spins on device matching; keep in this suite, not unit) |
| `Fixtures/XcodeTestProject` | macOS-only fixture: `SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 14.0` `[VERIFIED: project.pbxproj:111,113,162,166]`; single scheme `scip-swift-test` auto-resolvable via `resolveScheme` | No fixture changes needed — the macOS-only scheme is itself the natural REPAIR-03 failure case for an iOS destination |

## Common Pitfalls

- **Restoring from `aadc82d` verbatim misses the cache branches.** The pre-loss code predates `persistentCache`; the current file has two runner-construction sites (persistent line ~89, temp line ~99). Restore through one shared helper or the bug survives in the cache path.
- **Putting `-destination` after `build` or after build settings** — xcodebuild accepts options anywhere, but the existing test asserts `build` is last; splice into the middle of the array.
- **Deleting the CODE_SIGNING comment instead of updating it** — its rationale (signing is overhead; forced destination breaks macOS repos) is still half-true; rewrite, don't remove.
- **Hint on all build failures, not just destination ones** — pollutes SwiftPM/no-destination errors; gate strictly on `destination != nil`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| xcodebuild | REPAIR-01..03 integration tests | ✓ | Xcode 26.3 (Build 17C529) | — |
| Swift toolchain (pinned) | build/test | ✓ | 6.2.4 (= `.swift-version`) | — |

No missing dependencies. Note: bogus-destination runs take ~60s each (device-matching timeout observed live); budget integration-suite time accordingly.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Suite`/`@Test`), per project convention |
| Config file | none (Package.swift-based) |
| Quick run command | `swift test --filter XcodebuildBuildRunnerTests` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REPAIR-01 | xcodebuild repo dispatches to XcodebuildBuildRunner end-to-end | integration | `swift test --filter XcodeIntegrationTests` | ✅ extend |
| REPAIR-02 | nil destination → args byte-identical; non-nil → `-destination <value>` after `-configuration` | unit | `swift test --filter XcodebuildBuildRunnerTests` | ✅ extend |
| REPAIR-02 | explicit destination builds fixture + produces index store | integration | `swift test --filter XcodeIntegrationTests` | ✅ extend |
| REPAIR-03 | failed destination build throws error whose description contains `-showdestinations` | integration (~60s) | `swift test --filter XcodeIntegrationTests` | ✅ extend |
| REPAIR-03 | error case renders full output (unit-level description check) | unit | `swift test --filter BuildErrorTests` | ❌ optional (description assertable inside existing suites) |

### Sampling Rate
- **Per task commit:** `swift test --filter XcodebuildBuildRunnerTests` (pure, <5s)
- **Per wave merge:** `swift test --filter XcodeIntegrationTests`
- **Phase gate:** `swift test` full suite green

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements; only extensions to existing suites.

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2/V3/V4/V6 | no | CLI tool; no auth/sessions/crypto surface touched |
| V5 Input Validation | yes | `--destination` is user-supplied and reaches a subprocess via `Process`'s argument array (`SubprocessRunner.run`, no shell interpolation) `[VERIFIED: Sources/scip-swift/Build/SubprocessRunner.swift:13-35]` — no command-injection vector; pass verbatim, never `sh -c` |

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Argument injection via destination string | Tampering | `Process` argv array (already used); no shell string building |

## Sources

### Primary (HIGH confidence)
- Repo source read this session: `IndexCommand.swift`, `XcodebuildBuildRunner.swift`, `BuildError.swift`, `XcodeProjectLocator.swift`, `IndexStoreBuildResult.swift`, `SubprocessRunner.swift`, `IndexManyCommand.swift`, `BuildBackendDetector.swift`, both test files, fixture `project.pbxproj`
- Git history: `1c5ba8f`/`aadc82d` (dispatch present, verbatim recovered), `0cdefd7` (dispatch lost — corrects the "c06c050" attribution), `c06c050` (extraction preserved the broken state)
- Live xcodebuild 26.3 runs against `Fixtures/XcodeTestProject`: bogus-destination failure output captured; `-showdestinations` exit 0 + output shape; valid `-destination 'platform=macOS'` + signing overrides → BUILD SUCCEEDED + `Index.noindex/DataStore` present

### Secondary
- `.planning/research/ARCHITECTURE.md` §4 (prerequisite + destination integration) — its dispatch-loss commit attribution corrected by this research; its integration guidance otherwise confirmed

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `xcodebuildDestinationFailed` is the preferred new `BuildError` case name (case shape is a design choice, not a source-of-truth value) | §3 | trivial rename |
| A2 | Derived-data placement under cache dir for persistent runs (helper design) is the right convention — original code only ever used temp dirs | §1 | minor path-layout decision; planner may choose differently |

## Metadata

**Confidence breakdown:** Dispatch-loss archaeology HIGH (git-verified, with correction); destination threading HIGH (source-verified + live build confirmed); failure-hint HIGH (live output captured); test mapping HIGH (files read).
**Research date:** 2026-08-15
**Valid until:** 2026-09-15 (stable; xcodebuild behavior re-check if Xcode major bumps)
