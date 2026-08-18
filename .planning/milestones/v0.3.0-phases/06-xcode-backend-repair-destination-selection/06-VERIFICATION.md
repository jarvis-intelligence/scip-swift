---
phase: 06-xcode-backend-repair-destination-selection
verified: 2026-08-16T12:05:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 6: Xcode Backend Repair & Destination Selection Verification Report

**Phase Goal:** Xcode-project repos index again, and users can point xcodebuild at an explicit destination so iOS-only targets fully index
**Verified:** 2026-08-16T12:05:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | `indexOneRepo` on `Fixtures/XcodeTestProject` with no cache flags dispatches to `XcodebuildBuildRunner` and returns an index with documents (REPAIR-01) | ✓ VERIFIED | `Sources/scip-swift/Commands/IndexCommand.swift:103-115` temp branch calls shared `produceIndexStore`; live test `indexOneRepo builds an Xcode fixture through the xcodebuild backend` passed (28.1s, real xcodebuild) |
| 2 | `indexOneRepo` with a `cacheDir` also dispatches to `XcodebuildBuildRunner`, derived data under the cache dir | ✓ VERIFIED | `IndexCommand.swift:91-99` persistent branch calls same helper; live test passed (28.7s) asserting `cacheDir/derived-data` exists |
| 3 | SwiftPM repos keep dispatching to `SwiftPMBuildRunner` (existing suites green) | ✓ VERIFIED | `grep` shows exactly one `SwiftPMBuildRunner(` construction in Sources (inside the helper, `.swiftpm` case); `swift test --skip Xcode` ran 85/85 green in 14 suites including `IntegrationTests` |
| 4 | `--destination <spec>` splices `["-destination", spec]` after `-configuration`, before `-derivedDataPath` and `build` (REPAIR-02) | ✓ VERIFIED | `XcodebuildBuildRunner.swift:38-40` inserts at `-derivedDataPath` index; unit tests `destinationSplicesBetweenConfigurationAndDerivedDataPath` + `destinationPrecedesBuildAction` passed (12/12 suite green) |
| 5 | Omitting `--destination` keeps the xcodebuild argument list byte-identical to today | ✓ VERIFIED | Splice is gated on `if let destination` (nil leaves list element-for-element unchanged); `nilDestinationKeepsArgumentListIdentical` + all 7 pre-existing assertions passed unedited — they pin the no-destination list content/order |
| 6 | A `--destination` build failure surfaces full output + `-showdestinations` hint (REPAIR-03) | ✓ VERIFIED | Live test `bogus destination fails with the discoverable hint` passed (63.5s, real xcodebuild): thrown description contains `-showdestinations` and the real marker `Unable to find a device matching the provided destination specifier:`; `BuildError.swift:53-60` embeds untruncated output + copyable hint |
| 7 | Nil-destination failures still throw the existing `.buildFailed`, unchanged | ✓ VERIFIED | `XcodebuildBuildRunner.swift:53-65`: destination-gated `if let destination` throws `xcodebuildDestinationFailed`, else `.buildFailed` exactly as before; unit test `nonDestinationFailuresKeepBuildFailed` passed |
| 8 | `scip-swift index --build-tool xcodebuild --destination <spec>` reaches the runner from the CLI surface | ✓ VERIFIED | `.build/debug/scip-swift index --help` lists `--destination <destination>`; `IndexCommand.swift:26-27,45,62,97,111,162,189` threads it CLI → `indexOneRepo` → helper → runner init; live `platform=macOS` destination run produced an index (28.1s) |

**Score:** 8/8 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `Sources/scip-swift/Commands/IndexCommand.swift` | shared `produceIndexStore(tool:...)` helper called from both cache branches; `--destination` threaded | ✓ VERIFIED | Lines 155-194: single switch-tool helper, both branches (91-99, 103-115) call it; `@Option destination` at line 26 |
| `Sources/scip-swift/Build/XcodebuildBuildRunner.swift` | `destination: String? = nil` property, argument splice, destination-gated throw | ✓ VERIFIED | Line 15 var-default property; lines 38-40 splice; lines 53-60 throw gate |
| `Sources/scip-swift/Build/BuildError.swift` | `xcodebuildDestinationFailed` case with full-output description + hint | ✓ VERIFIED | Lines 20-24 case + doc comment; lines 53-60 description arm |
| `Tests/scip-swiftTests/XcodebuildBuildRunnerTests.swift` | 7 pre-existing + 5 new destination/error tests | ✓ VERIFIED | 12 tests enumerated, 12/12 passed <1s; 7 pre-existing assertions unedited |
| `Tests/scip-swiftTests/XcodeIntegrationTests.swift` | dispatch tests (both branches) + destination success/failure tests | ✓ VERIFIED | 5 tests enumerated, 5/5 passed (63.5s real xcodebuild) |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `indexOneRepo` both cache branches | `produceIndexStore(tool:...)` | direct call | ✓ WIRED | Both call sites pass `tool`, `destination`, `scratchPath`; helper switches on `BuildTool` |
| Helper `.xcodebuild` case | `XcodebuildBuildRunner` | `XcodeProjectLocator.workspaceOrProjectArguments` → `resolveScheme` → init with `derivedDataPath` beside scratch dir | ✓ WIRED | `IndexCommand.swift:172-193`; derived-data-under-cache-dir asserted by live test |
| `IndexCommand @Option destination` | `XcodebuildBuildRunner(destination:)` arguments splice | defaulted params through `indexOneRepo` → helper → init | ✓ WIRED | `IndexManyCommand.swift:41` call site compiles unchanged via default; live macOS-destination run proves end-to-end |
| `produceIndexStore()` non-zero exit + destination | `BuildError.xcodebuildDestinationFailed` | strict `destination != nil` gate (no string-matching of xcodebuild output) | ✓ WIRED | Live bogus-destination run threw the hint-carrying error |

### Data-Flow Trace (Level 4)

Not applicable — CLI tool with no rendered dynamic data. All data flows are subprocess argv: `--destination` flows verbatim as a single argv element through `SubprocessRunner.run`'s argument array (`XcodebuildBuildRunner.swift:46-50`), no shell string composition (threat T-06-03 mitigated as planned).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Runner unit suite (arg construction + error descriptions) | `swift test --filter XcodebuildBuildRunnerTests` | 12/12 passed, 0.001s | ✓ PASS |
| Xcode end-to-end integration (real xcodebuild) | `swift test --filter XcodeIntegrationTests` | 5/5 passed, 63.5s — incl. bogus-destination failure with hint (63.5s) | ✓ PASS |
| Non-Xcode partition (SwiftPM regression + all unit suites) | `swift test --skip Xcode` | 85/85 passed in 14 suites, 5.6s | ✓ PASS |
| Xcode partition | `swift test --filter Xcode` | 19/19 passed in 3 suites, 65.3s | ✓ PASS |
| Full-suite coverage reconciliation | `swift test --list-tests` | 104 total; 85 + 19 = 104, complementary partitions, zero overlap | ✓ PASS |
| CLI surface exposes `--destination` | `.build/debug/scip-swift index --help` | flag listed with `generic/platform=iOS Simulator` guidance | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` declared by plans or conventional layout — SKIPPED (none exist).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| REPAIR-01 | 06-01 | Xcode-project repo indexes via xcodebuild backend (restore lost dispatch) | ✓ SATISFIED | Shared dispatch helper + two live-passing integration tests (truths 1-2) |
| REPAIR-02 | 06-02 | `--destination <spec>` flag; nil default preserves behavior | ✓ SATISFIED | Splice unit tests + nil-identity test + live `platform=macOS` run + CLI help (truths 4-5, 8) |
| REPAIR-03 | 06-02 | Failed destination builds surface `-showdestinations` hint | ✓ SATISFIED | Live bogus-destination failure asserting hint + real marker; nil path keeps `.buildFailed` (truths 6-7) |

No orphaned requirements: REQUIREMENTS.md maps exactly REPAIR-01/02/03 to Phase 6, all claimed by plans.

### Commits Verified

All 10 claimed commits exist and are ancestors of HEAD (`git cat-file -t` + `git merge-base --is-ancestor`): `e74d16b`, `9bcf168`, `028c35a`, `9200e70` (06-01 RED/GREEN pairs), `db4ac48`, `f65512e`, `d542e24`, `6991ffc`, `2cfff1e`, `34a6fc9` (06-02 RED/GREEN pairs). Working tree clean — every change is committed.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `Sources/scip-swift/Commands/IndexCommand.swift` | 53 | `print(...)` | ℹ️ Info | Pre-existing CLI success message, not debug output — not introduced by this phase |

No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK` markers, no skipped tests, no weakened assertions (the 7 pre-existing runner tests are byte-identical to before), no placeholder implementations.

### Human Verification Required

None. All behavior-dependent truths were exercised by live integration tests run during this verification (real `xcodebuild` against `Fixtures/XcodeTestProject`, including the failing-destination path).

### Warnings (non-blocking)

- **Stale phase tracking docs.** Code and commits for 06-02 exist, but `.planning/STATE.md` still says "Plan: 1 of 2 … 06-02 next" / "7-status: planning", `.planning/ROADMAP.md` Phase 6 section still shows "1/2 plans executed" with 06-02 unchecked and the progress table "In Progress", and `.planning/REQUIREMENTS.md` still has REPAIR-02/REPAIR-03 unchecked with Traceability "pending". These are bookkeeping, not code gaps — the orchestrator's phase-complete step should mark them.

### Gaps Summary

None. All 8 truths verified with behavioral evidence; all 5 artifacts substantive and wired; all 4 key links wired; all 3 requirements satisfied; all 104 tests green via complementary partitions (`--skip Xcode` 85/85 + `--filter Xcode` 19/19); all 10 commits present and reachable from HEAD; working tree clean.

---

_Verified: 2026-08-16T12:05:00Z_
_Verifier: gsd-verifier_
