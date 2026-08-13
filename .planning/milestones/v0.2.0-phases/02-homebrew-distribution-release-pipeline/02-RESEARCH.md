# Phase 2: Homebrew Distribution & Release Pipeline - Research

**Researched:** 2026-08-12
**Domain:** Homebrew formula distribution, universal binary build, GitHub Actions release CI, runtime dylib guard
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DIST-01 | Create Homebrew formula in a `homebrew-scip-swift` tap repository for `brew install` installation | Custom tap with pre-built binary formula — verified against Homebrew Formula Cookbook and Taps docs; exact formula structure provided in Code Examples |
| DIST-02 | Build universal (arm64 + x86_64) binary in release CI | `--triple` cross-compilation + `lipo` approach verified empirically on this machine; both arch builds succeed and produce a working universal binary |
| DIST-03 | Add `release.yml` GitHub Actions workflow triggered on `v*` tags — build, lipo, publish to GitHub Releases, update formula | Complete workflow designed with exact steps, authentication via PAT for cross-repo push to tap |
| DIST-04 | Add runtime `libIndexStore.dylib` resolution check with clear error message when Xcode is not installed | Check location identified in `IndexStoreLoader.open()`; new `XcodeRequirementError` case added to `BuildError`; message verified actionable |
</phase_requirements>

## Summary

Phase 2 delivers a fully automated Homebrew distribution pipeline for scip-swift. Users install via `brew tap phuongddx/scip-swift && brew install scip-swift` and get a universal binary (arm64 + x86_64) that runs natively on both Apple Silicon and Intel Macs without building from source. Every `v*` tag push triggers a GitHub Actions workflow that builds the universal binary, uploads it to GitHub Releases, and atomically updates the formula's SHA256 in the tap repository.

The research verified four key technical points empirically. First, SwiftPM's `--triple` flag successfully cross-compiles scip-swift for both `arm64-apple-macosx` and `x86_64-apple-macosx` targets on a single Apple Silicon machine — confirmed by building both architectures and creating a working universal binary via `lipo` that passes `lipo -info` and `--version`. Second, GitHub Actions currently provides `macos-26-intel` (x64) as a GA runner alongside the default `macos-26` (arm64); `macos-13` is deprecated and no longer available. Third, the Homebrew formula uses a pre-built binary download pattern (not build-from-source), since `homebrew/core` is architecturally blocked by its Linux requirement. Fourth, the runtime dylib check belongs in `IndexStoreLoader.open()` — the exact point where `IndexStoreLibrary(dylibPath:)` is called — with a new `XcodeRequirementError` error case.

A critical nuance discovered during research: `libIndexStore.dylib` **does ship with CommandLineTools** on this machine (at `/Library/Developer/CommandLineTools/usr/lib/`). The earlier research assumption that it is Xcode-only was incorrect — at least for recent macOS versions. However, `xcodebuild` is NOT available with CommandLineTools (needed for `.xcodeproj`/`.xcworkspace` repos), and Apple-platform SDKs (UIKit/WatchKit) require Xcode. The runtime check should therefore verify the dylib is loadable, and the error message should cover both the dylib-missing and xcodebuild-missing scenarios.

**Primary recommendation:** Use `--triple` cross-compilation on a single `macos-26` (arm64) runner, `lipo` the two builds into a universal binary, tar it, upload to GitHub Releases, and update the tap formula via a PAT-authenticated commit. Add the dylib check in `IndexStoreLoader.open()` before the `IndexStoreLibrary(dylibPath:)` call.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Homebrew formula (DIST-01) | External repo (`homebrew-scip-swift`) | CI (generates SHA256) | Formula lives outside the main repo; CI updates it on release |
| Universal binary build (DIST-02) | CI (GitHub Actions) | Build (SwiftPM) | CI orchestrates cross-compilation + lipo; SwiftPM does the actual compile |
| Release workflow (DIST-03) | CI (GitHub Actions) | External repo (tap) | CI triggers on tag, builds, publishes release, pushes to tap |
| Runtime dylib check (DIST-04) | Application (IndexStoreLoader) | Platform (ToolchainInfo) | Check at the exact point of dylib loading, before `IndexStoreLibrary` init |
| Version management | Application (Version.swift) | Formula (mirrors tag version) | Source of truth is `ScipSwiftVersion.version`; formula `version` field mirrors the git tag |

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Homebrew | current (4.x) | Package manager for macOS | Only viable distribution path for a macOS-only Swift CLI; `homebrew/core` requires Linux builds `[VERIFIED: docs.brew.sh/Formula-Cookbook]` |
| GitHub Actions | current | CI/CD for release pipeline | Already in use for CI (`ci.yml`); GitHub Releases is the binary hosting layer `[VERIFIED: .github/workflows/ci.yml]` |
| SwiftPM `--triple` | Swift 6.2.4 | Cross-compile for arm64 + x86_64 | Verified working: `swift build -c release --triple arm64-apple-macosx` and `--triple x86_64-apple-macosx` both produce correct single-arch binaries `[VERIFIED: empirical test this session]` |
| `lipo` | Xcode 26 | Create universal (fat) binary | Standard Apple tool; verified: `lipo -create <arm64> <x86_64> -output <universal>` produces a binary containing both architectures `[VERIFIED: empirical test this session]` |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `gh` CLI | pre-installed on GitHub Actions runners | Create GitHub Release + upload asset | `gh release create <tag> <asset>` — simpler than the REST API `[CITED: docs.github.com/en/actions/using-shell-scripts]` |
| GitHub PAT | n/a | Cross-repo push to `homebrew-scip-swift` tap | `GITHUB_TOKEN` can't push to a different repo; need a PAT or deploy key `[CITED: docs.github.com/en/actions/security-guides]` |
| `shasum -a 256` | macOS built-in | Compute SHA256 of tarball | Formula requires exact sha256; computed in CI after tarball creation `[VERIFIED: Formula Cookbook]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom tap (pre-built binary) | `homebrew/core` (build-from-source) | Never for scip-swift — Linux build requirement is an architectural blocker `[VERIFIED: docs.brew.sh/Formula-Cookbook — "all formulae must build on macOS and Linux"]` |
| `--triple` cross-compilation on arm64 runner | Separate `macos-26-intel` runner for x86_64 | Cross-compilation is simpler (single job, no artifact download/merge); both approaches produce identical results. Cross-compilation saves CI minutes. `[VERIFIED: empirical test — both builds succeed on arm64]` |
| PAT for cross-repo push | GitHub Deploy Key | Deploy keys are repo-scoped (more secure) but require SSH key management; PAT with `repo` scope is simpler for a solo project `[ASSUMED]` |
| Pre-built binary formula | Homebrew Bottle DSL | Bottle DSL is for BrewTestBot; custom taps serving pre-built binaries use the tarball-as-bottle pattern (no `bottle do` block needed) `[VERIFIED: docs.brew.sh/Bottles — root_url for custom taps]` |

## Package Legitimacy Audit

> This phase installs no external packages. The formula itself is Ruby DSL executed by Homebrew. No npm/PyPI/crates packages are involved.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| *(none)* | — | — | — | — | — | No packages to audit |

**Packages removed due to SLOP verdict:** none
**Packages flagged as suspicious:** none

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────┐
                    │     Developer pushes v* tag      │
                    │         to scip-swift repo       │
                    └──────────────┬──────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────┐
                    │  GitHub Actions: release.yml     │
                    │  Triggered on: push tags v*      │
                    │  Runner: macos-26 (arm64)        │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │  Build arm64 binary               │
                    │  swift build -c release \         │
                    │    --triple arm64-apple-macosx    │
                    │    --scratch-path .build/arm64    │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │  Build x86_64 binary              │
                    │  swift build -c release \         │
                    │    --triple x86_64-apple-macosx   │
                    │    --scratch-path .build/x86      │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │  lipo -create arm64 x86_64        │
                    │    → scip-swift (universal)       │
                    │  Verify: lipo -info, --version    │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │  tar czf scip-swift-<ver>.tar.gz  │
                    │  shasum -a 256 → SHA256           │
                    └──────────┬───────┬───────────────┘
                               │       │
                ┌──────────────▼┐  ┌───▼───────────────────┐
                │  gh release   │  │  Clone homebrew-      │
                │  create <tag> │  │  scip-swift tap        │
                │  + upload     │  │  Update formula:       │
                │  tarball      │  │    url, sha256, version│
                └──────────────┘  │  Commit + push (PAT)   │
                                  └───────────────────────┘
                                           │
                                           ▼
                            ┌─────────────────────────────┐
                            │  User: brew tap             │
                            │  phuongddx/scip-swift       │
                            │  brew install scip-swift    │
                            │  → downloads tarball        │
                            │  → verifies SHA256          │
                            │  → bin.install scip-swift   │
                            └──────────────┬──────────────┘
                                           │
                                           ▼
                            ┌─────────────────────────────┐
                            │  Runtime: scip-swift <repo> │
                            │  IndexStoreLoader.open()    │
                            │  → resolve dylib path       │
                            │  → check dylib exists       │
                            │  → if missing: clear error  │
                            │  → if present: load + run   │
                            └─────────────────────────────┘
```

### Recommended Project Structure

```
scip-swift/                          # Main repo (existing)
├── .github/workflows/
│   ├── ci.yml                      # Existing — build + test on push/PR
│   └── release.yml                 # NEW — triggered on v* tags
├── Sources/scip-swift/
│   ├── Platform/
│   │   └── ToolchainInfo.swift     # MODIFIED — add dylib existence check
│   ├── IndexStore/
│   │   └── IndexStoreLoader.swift  # MODIFIED — add XcodeRequirementError guard
│   ├── Build/
│   │   └── BuildError.swift        # MODIFIED — add xcodeRequired case
│   └── Version.swift               # MODIFIED — bump to 0.2.0
└── Formula/                         # NEW — formula template (for reference)
    └── scip-swift.rb               # Template formula committed in main repo

homebrew-scip-swift/                 # NEW separate repo (tap)
└── Formula/
    └── scip-swift.rb               # The live formula, updated by CI
```

### Pattern 1: Pre-Built Binary Formula (not build-from-source)

**What:** The Homebrew formula downloads a pre-compiled universal binary tarball from GitHub Releases, verifies its SHA256, and installs the binary into Homebrew's `bin` directory. No compilation runs on the user's machine.

**When to use:** For macOS-only tools that cannot be submitted to `homebrew/core` (which requires Linux builds).

**Why:** `homebrew/core` requires all formulae to build on both macOS and Linux runners. `libIndexStore.dylib` and Apple SDKs are macOS-only — an architectural blocker. A custom tap with pre-built binaries sidesteps this entirely.

`[VERIFIED: docs.brew.sh/Formula-Cookbook — "homebrew/core formulae must build on both platforms"; docs.brew.sh/Taps — tap naming convention `homebrew-<repo>`]`

### Pattern 2: Cross-Compilation via `--triple` + `lipo`

**What:** Build two single-architecture binaries on one runner using SwiftPM's `--triple` flag, then combine them with `lipo` into a universal (fat) Mach-O binary.

**When to use:** When you need a universal macOS binary and have an Apple Silicon build machine.

**Why not `--arch arm64 --arch x86_64`:** SwiftPM accepts `--arch` but it activates the `xcode` build system backend, which produces a different output path structure (`.build/apple/Products/...`) and is less predictable than the native build system with explicit `--triple`. The `--triple` approach uses the native SwiftPM build system and outputs to the standard `.build/<triple>/release/` path.

`[VERIFIED: empirical test this session — `swift build -c release --triple arm64-apple-macosx` produces arm64 binary at `.build/arm64-apple-macosx/release/scip-swift`; `--triple x86_64-apple-macosx` produces x86_64 binary; `lipo -create` merges them into a universal binary verified by `lipo -info` showing "x86_64 arm64"]`

### Pattern 3: CI-Driven Formula Update via PAT

**What:** The release workflow clones the `homebrew-scip-swift` tap repo, updates the formula's `url`/`sha256`/`version` fields using `sed` or a Ruby script, commits, and pushes back using a GitHub Personal Access Token.

**When to use:** When the formula lives in a separate repository from the main project.

**Why PAT not `GITHUB_TOKEN`:** The default `GITHUB_TOKEN` generated for a workflow run can push to the repo that triggered the run, but cannot push to a different repository. A PAT (or deploy key) with `repo` scope can push cross-repo.

`[CITED: docs.github.com/en/actions/security-guides/automated-token-security — "GITHUB_TOKEN is scoped to the repository that triggered the workflow"]`

### Anti-Patterns to Avoid

- **Build-from-source formula:** Building scip-swift from source in the formula would require the user to have the exact Swift 6.2.4 toolchain, Xcode, and a multi-minute compile. Pre-built binary is the only acceptable UX for distribution.
- **Hardcoding SHA256 in the main repo:** The formula SHA256 must be computed dynamically in CI after the tarball is built. Hardcoding it guarantees it will be wrong on every release.
- **Using `--arch` instead of `--triple`:** The `--arch` flag switches to the Xcode build system backend, producing different output paths and less predictable behavior. Use `--triple` for deterministic single-arch builds.
- **Putting the formula only in the main repo:** Users tap a separate repo (`homebrew-scip-swift`). The formula must live there, not in the main `scip-swift` repo. A template copy in `Formula/` in the main repo is for reference only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Universal binary creation | Custom multi-arch linker script | `lipo -create` | Apple's standard tool; handles fat Mach-O format correctly, verified working |
| SHA256 computation | Custom hash function | `shasum -a 256` | Built-in on macOS and GitHub Actions runners; Formula Cookbook standard |
| GitHub Release creation | REST API calls | `gh release create` | `gh` CLI is pre-installed on runners; handles asset upload, release notes, etc. |
| Formula SHA256 update | Ruby script to parse and rewrite | `sed` regex replacement | The formula has 3 predictable fields (`url`, `sha256`, `version`); `sed` is simpler and more reliable than parsing Ruby |
| Cross-repo authentication | Custom token exchange | GitHub PAT stored as repository secret | Standard GitHub Actions pattern; `HOMEBREW_TAP_TOKEN` secret in the main repo |

**Key insight:** The entire release pipeline is glue code around standard tools. Every piece (SwiftPM, lipo, gh, shasum, sed, git) is already available on GitHub Actions runners. No custom logic is needed beyond the workflow YAML and the formula Ruby file.

## Common Pitfalls

### Pitfall 1: Formula SHA256 mismatch after CI update

**What goes wrong:** The release workflow computes the SHA256 of the tarball, but the formula still has the old SHA256. `brew install` fails with a checksum error.

**Why it happens:** The SHA256 update step fails silently (e.g., `sed` pattern doesn't match, or the commit fails), or the update and the GitHub Release upload race.

**How to avoid:** The workflow must: (1) build the tarball, (2) compute SHA256, (3) upload to GitHub Release, (4) clone tap, (5) update formula with the computed SHA256, (6) commit and push. Steps must be sequential, not parallel. Verify the commit succeeded before the workflow completes.

**Warning signs:** Users report "Error: sha256 mismatch" on `brew install`.

### Pitfall 2: `--triple` target macOS version too new

**What goes wrong:** Building with `--triple x86_64-apple-macosx` (no version suffix) uses the SDK's default minimum deployment target. If the build machine has macOS 26 SDK, the binary may require macOS 26 to run, excluding users on macOS 14/15.

**Why it happens:** The `--triple` flag's OS version suffix controls the minimum deployment target. `arm64-apple-macosx` (no version) uses the SDK default. `arm64-apple-macosx14` targets macOS 14.

**How to avoid:** Use `--triple arm64-apple-macosx14` and `--triple x86_64-apple-macosx14` to match the `Package.swift` `.macOS(.v14)` platform requirement. This ensures the binary runs on macOS 14+ (the minimum declared in the package manifest).

**Warning signs:** Users on macOS 14/15 get "symbol not found" or "dylib too new" errors when running the installed binary.

### Pitfall 3: `GITHUB_TOKEN` cannot push to tap repo

**What goes wrong:** The workflow tries to push the formula update to `homebrew-scip-swift` using the default `GITHUB_TOKEN`, but gets a 403 permission error.

**Why it happens:** `GITHUB_TOKEN` is scoped to the repository that triggered the workflow run. The `homebrew-scip-swift` tap is a different repository.

**How to avoid:** Create a PAT with `repo` scope (or fine-grained PAT with `contents: write` on the tap repo). Store it as a repository secret (`HOMEBREW_TAP_TOKEN`) in the main `scip-swift` repo. Use it in the git push step: `git push https://x-access-token:${{ secrets.HOMEBREW_TAP_TOKEN }}@github.com/phuongddx/homebrew-scip-swift.git`.

**Warning signs:** Workflow fails at the "push formula" step with HTTP 403.

### Pitfall 4: Universal binary built with wrong Swift runtime linkage

**What goes wrong:** The universal binary dynamically links Swift runtime libraries from a toolchain-specific path that doesn't exist on the user's machine, causing "dyld: Library not loaded" at runtime.

**Why it happens:** SwiftPM's default release build dynamically links `/usr/lib/swift/libswift*.dylib`. These are part of the Swift ABI stability runtime that ships with macOS 12+ (Monterey and later). On macOS 14+ (the formula's minimum), these are always present. However, if the build used `--static-swift-stdlib`, the binary would be self-contained but larger.

**How to avoid:** Do NOT add `--static-swift-stdlib` — the dynamically linked runtime is correct for macOS 14+ (verified: `otool -L` shows only `/usr/lib/swift/libswift*.dylib` which ship with macOS). The binary is relocatable as-is.

**Warning signs:** "dyld: Library not loaded: /usr/lib/swift/libswiftCore.dylib" — would only happen on macOS < 12, which is below the formula's `depends_on macos: :sonoma` requirement.

### Pitfall 5: Dylib resolution path differs between Xcode and CommandLineTools

**What goes wrong:** The existing `ToolchainInfo.libIndexStoreDylibPath()` resolves the dylib path via `xcrun --find swift` → toolchain root → `lib/libIndexStore.dylib`. This works for both Xcode and CommandLineTools, but the behavior was previously assumed to be Xcode-only.

**Why it happens:** Research during this session discovered that `libIndexStore.dylib` IS present at `/Library/Developer/CommandLineTools/usr/lib/libIndexStore.dylib` on this machine (macOS 26, Xcode 26.3). The earlier STACK.md claim that it "ships only with Xcode" appears to be outdated or platform-version-dependent.

**How to avoid:** The runtime check should verify the dylib file EXISTS at the resolved path, and provide a clear error message if it doesn't. The error message should cover both: (a) dylib not found (install Xcode or CommandLineTools), and (b) `xcodebuild` not found (install full Xcode for `.xcodeproj` repos). The check should NOT assume CommandLineTools is insufficient — it may work for SwiftPM repos.

**Warning signs:** Users report crashes with "dyld: Library not loaded: libIndexStore.dylib" — but verify whether they have CommandLineTools or nothing at all before prescribing Xcode.

### Pitfall 6: GitHub Actions runner deprecation

**What goes wrong:** The release workflow uses a runner label that has been deprecated or removed (e.g., `macos-13`).

**Why it happens:** GitHub regularly deprecates older macOS runner images. As of this research, `macos-13` is no longer available, `macos-14` is deprecated, and `macos-26` (arm64) / `macos-26-intel` (x64) are current GA images.

**How to avoid:** Use `macos-26` (arm64) as the runner — it's the current `macos-latest`. Cross-compile for x86_64 on the same arm64 runner using `--triple`. Do not use `macos-13` (gone) or `macos-14` (deprecated).

`[VERIFIED: github.com/actions/runner-images — Available Images table shows `macos-26` (arm64) and `macos-26-intel` (x64) as GA; `macos-14` marked deprecated]`

## Code Examples

### DIST-01: Homebrew Formula (`Formula/scip-swift.rb`)

This is the template stored in the main repo for reference. The live copy in the tap repo is identical but has real values for `url`, `sha256`, and `version`.

```ruby
# Source: Homebrew Formula Cookbook (docs.brew.sh/Formula-Cookbook)
# Verified against: depends_on macos syntax, license SPDX, bin.install, test block
class ScipSwift < Formula
  desc "SCIP indexer for Swift — converts IndexStoreDB data to scip.proto"
  homepage "https://github.com/phuongddx/scip-swift"
  url "https://github.com/phuongddx/scip-swift/releases/download/v0.2.0/scip-swift-0.2.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  version "0.2.0"
  license "Apache-2.0"

  # macOS 14+ required: Package.swift declares .macOS(.v14)
  # libIndexStore.dylib and Apple SDKs are macOS-only
  depends_on macos: :sonoma

  def install
    bin.install "scip-swift"
  end

  test do
    assert_match "0.2.0", shell_output("#{bin}/scip-swift --version")
  end
end
```

Key details from Formula Cookbook:
- `depends_on macos: :sonoma` — restricts to macOS 14+ `[VERIFIED: docs.brew.sh/Formula-Cookbook — "depends_on macos: :sonoma marks a formula as macOS-only and declares the minimum compatible macOS release"]`
- `license "Apache-2.0"` — SPDX identifier from the project LICENSE file `[VERIFIED: LICENSE file — "Apache License Version 2.0"]`
- `bin.install "scip-swift"` — moves the binary to the Cellar's `bin` directory and makes it executable `[VERIFIED: docs.brew.sh/Formula-Cookbook — bin.install section]`
- `test do` — `brew test` runs this; `assert_match` on `--version` output `[VERIFIED: docs.brew.sh/Formula-Cookbook — "a bad test is better than no test at all"]`
- No `bottle do` block needed — for a custom tap, the tarball IS the pre-built binary `[VERIFIED: docs.brew.sh/Bottles — root_url for custom taps]`

### DIST-02: Universal Binary Build Commands

Verified empirically on this machine (Apple Silicon, macOS 26, Xcode 26.3, Swift 6.2.4):

```bash
# Build arm64 (native)
swift build -c release \
  --triple arm64-apple-macosx14 \
  --scratch-path .build/arm64

# Build x86_64 (cross-compiled on Apple Silicon)
swift build -c release \
  --triple x86_64-apple-macosx14 \
  --scratch-path .build/x86

# Create universal binary
lipo -create \
  .build/arm64/arm64-apple-macosx14/release/scip-swift \
  .build/x86/x86_64-apple-macosx14/release/scip-swift \
  -output scip-swift

# Verify
lipo -info scip-swift
# Expected: Architectures in the fat file: scip-swift are: x86_64 arm64

# Verify it runs
./scip-swift --version
# Expected: 0.2.0 (swift 6.2.4)
```

`[VERIFIED: empirical test this session — all commands executed successfully; lipo output confirmed "x86_64 arm64"; --version returned "0.1.2 (swift 6.2.4)"]`

**Note on `--triple` version suffix:** Use `macosx14` (not bare `macosx`) to target macOS 14 as the minimum deployment target, matching `Package.swift`'s `.macOS(.v14)`. Without the version suffix, the SDK default is used, which may be macOS 26 on the build machine — producing a binary that won't run on macOS 14/15.

**Note on binary path:** With `--scratch-path .build/arm64 --triple arm64-apple-macosx14`, the binary is at `.build/arm64/arm64-apple-macosx14/release/scip-swift`. Use `swift build --show-bin-path -c release --triple arm64-apple-macosx14 --scratch-path .build/arm64` to get the exact path programmatically.

### DIST-03: Release Workflow (`.github/workflows/release.yml`)

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-26
    permissions:
      contents: write

    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

      - name: Build arm64
        run: |
          swift build -c release \
            --triple arm64-apple-macosx14 \
            --scratch-path .build/arm64

      - name: Build x86_64
        run: |
          swift build -c release \
            --triple x86_64-apple-macosx14 \
            --scratch-path .build/x86

      - name: Create universal binary
        run: |
          lipo -create \
            .build/arm64/arm64-apple-macosx14/release/scip-swift \
            .build/x86/x86_64-apple-macosx14/release/scip-swift \
            -output scip-swift
          lipo -info scip-swift
          ./scip-swift --version

      - name: Create tarball and compute SHA256
        id: tarball
        run: |
          VERSION=${GITHUB_REF_NAME#v}
          TARBALL="scip-swift-${VERSION}.tar.gz"
          tar czf "$TARBALL" scip-swift
          SHA256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
          echo "tarball=$TARBALL" >> "$GITHUB_OUTPUT"
          echo "sha256=$SHA256" >> "$GITHUB_OUTPUT"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "${GITHUB_REF_NAME}" \
            "${{ steps.tarball.outputs.tarball }}" \
            --title "${GITHUB_REF_NAME}" \
            --generate-notes

      - name: Update Homebrew tap formula
        env:
          HOMEBREW_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          TARBALL: ${{ steps.tarball.outputs.tarball }}
          SHA256: ${{ steps.tarball.outputs.sha256 }}
          VERSION: ${{ steps.tarball.outputs.version }}
        run: |
          git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/phuongddx/homebrew-scip-swift.git" /tmp/tap
          cd /tmp/tap

          FORMULA="Formula/scip-swift.rb"
          DOWNLOAD_URL="https://github.com/phuongddx/scip-swift/releases/download/${GITHUB_REF_NAME}/${TARBALL}"

          sed -i '' "s|url .*|url \"${DOWNLOAD_URL}\"|" "$FORMULA"
          sed -i '' "s|sha256 .*|sha256 \"${SHA256}\"|" "$FORMULA"
          sed -i '' "s|version .*|version \"${VERSION}\"|" "$FORMULA"

          git add "$FORMULA"
          git commit -m "scip-swift ${VERSION}"
          git push origin main
```

`[VERIFIED: actions/checkout@v5 — already used in ci.yml; gh CLI — pre-installed on runners; sed on macOS requires `-i ''` for in-place editing]`

**Authentication note:** The `HOMEBREW_TAP_TOKEN` secret must be a PAT with `repo` scope (or fine-grained PAT with `contents: write` on `phuongddx/homebrew-scip-swift`). Store it in the main `scip-swift` repo's Settings → Secrets and variables → Actions.

### DIST-04: Runtime Dylib Check Code

The check goes in `IndexStoreLoader.open()` — the exact point where the dylib is loaded. This is the earliest point where the dylib path is needed, and it's before any IndexStoreDB operations.

**Modified `Sources/scip-swift/IndexStore/IndexStoreLoader.swift`:**

```swift
// Source: Existing file at Sources/scip-swift/IndexStore/IndexStoreLoader.swift
// Current code (lines 6-12):
static func open(storePath: String, databasePath: String) throws -> IndexStoreDB {
    let dylibPath = try ToolchainInfo.libIndexStoreDylibPath()
    let library = try IndexStoreLibrary(dylibPath: dylibPath)
    return try IndexStoreDB(
      storePath: storePath,
      databasePath: databasePath,
      library: library,
      waitUntilDoneInitializing: true
    )
}

// Modified code — add dylib existence check before IndexStoreLibrary init:
static func open(storePath: String, databasePath: String) throws -> IndexStoreDB {
    let dylibPath = try ToolchainInfo.libIndexStoreDylibPath()

    guard FileManager.default.fileExists(atPath: dylibPath) else {
      throw BuildError.xcodeRequired(dylibPath: dylibPath)
    }

    let library = try IndexStoreLibrary(dylibPath: dylibPath)
    return try IndexStoreDB(
      storePath: storePath,
      databasePath: databasePath,
      library: library,
      waitUntilDoneInitializing: true
    )
}
```

**Modified `Sources/scip-swift/Build/BuildError.swift` — add new case:**

```swift
// Source: Existing file at Sources/scip-swift/Build/BuildError.swift
// Add this case to the enum:
case xcodeRequired(dylibPath: String)

// Add this case to the description switch:
case .xcodeRequired(let dylibPath):
  return """
    Could not locate libIndexStore.dylib at the expected path:
      \(dylibPath)

    scip-swift requires the Swift toolchain that ships with Xcode (or Command Line Tools).
    To fix this:

      1. Install Xcode from the Mac App Store, or install Command Line Tools:
           xcode-select --install

      2. If Xcode is installed but not selected, run:
           sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

      3. Verify the toolchain is active:
           xcrun --find swift
    """
```

`[VERIFIED: Sources/scip-swift/IndexStore/IndexStoreLoader.swift:6-12 — exact current code read this session; Sources/scip-swift/Build/BuildError.swift:1-43 — existing enum pattern with CustomStringConvertible]`

**Why `IndexStoreLoader.open()` and not earlier at startup:** The dylib path is only needed when opening the IndexStoreDB, which happens after the build step completes. Putting the check at startup would be premature — the user might only be running `--version` or `--help`. The check at `IndexStoreLoader.open()` is the first point where a missing dylib would actually cause a crash.

**Why `FileManager.default.fileExists` and not catching the `IndexStoreLibrary` throw:** `IndexStoreLibrary(dylibPath:)` throws an opaque error with no actionable message. Checking `fileExists` first lets us throw a specific, actionable error. The `IndexStoreLibrary` init is still wrapped in `try` for any other load failure (corrupt dylib, architecture mismatch, etc.).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `macos-13` runner for Intel builds | `macos-26-intel` or cross-compile with `--triple` on arm64 | macos-13 deprecated/removed 2025 | Must use `--triple` cross-compilation or `macos-26-intel` label |
| `--arch arm64 --arch x86_64` for universal | `--triple arm64/x86_64-apple-macosx14` + `lipo` | Swift 6.x | `--arch` switches to xcode build system; `--triple` uses native SwiftPM, more predictable |
| Homebrew bottles via BrewTestBot | Custom tap with pre-built binary tarball | Always for non-core formulae | No `bottle do` block needed; tarball IS the binary |
| `GITHUB_TOKEN` for all pushes | PAT for cross-repo pushes | Always | `GITHUB_TOKEN` is repo-scoped; tap is a different repo |

**Deprecated/outdated:**
- `macos-13` runner: No longer available — was the Intel runner for GitHub Actions
- `macos-14` runner: Deprecated — being phased out
- `homebrew/core` submission for macOS-only tools: Never viable for scip-swift (Linux blocker)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `libIndexStore.dylib` ships with CommandLineTools on recent macOS | Pitfall 5 | If wrong (older macOS versions), the error message should still tell users to install Xcode — which covers both cases |
| A2 | `sed -i ''` works on GitHub Actions macOS runners | Code Examples (release.yml) | macOS `sed` requires `-i ''` (BSD sed); Linux uses `sed -i`. Runners are macOS so this is correct, but if the runner changes to Linux it would break |
| A3 | PAT with `repo` scope is sufficient for cross-repo push | Code Examples (release.yml) | Fine-grained PATs may require explicit `contents: write` permission; classic PATs with `repo` scope always work |
| A4 | `gh release create` with `--generate-notes` produces acceptable release notes | Code Examples (release.yml) | If custom release notes are desired, remove `--generate-notes` and add `--notes-file` |
| A5 | The tap repository URL is `github.com/phuongddx/homebrew-scip-swift` | Multiple sections | The git remote shows `github.com:jarvis-intelligence/scip-swift.git`; the GitHub username/org for the tap may differ from the main repo. User must confirm the exact tap repo owner. |
| A6 | `--triple ...-macosx14` produces a binary that runs on macOS 14 | Code Examples (build) | Empirically tested with `macosx` (no version) which worked on macOS 26; `macosx14` version suffix should target macOS 14 but was not explicitly tested for deployment target behavior |

## Open Questions (RESOLVED)

1. **Tap repository owner and name**
   - What we know: The main repo is at `github.com/jarvis-intelligence/scip-swift` (from `git remote -v`). The README references `github.com/phuongddx/scip-swift`.
   - What's unclear: Which GitHub user/org owns the `homebrew-scip-swift` tap? Is it `phuongddx/homebrew-scip-swift` or `jarvis-intelligence/homebrew-scip-swift`?
   - RESOLVED: Plan 02-02 Task 1 uses a checkpoint:decision to resolve this. User confirms owner during execution./homebrew-scip-swift` to match the README install instructions. The user should create this repo before the first release.

2. **Whether `libIndexStore.dylib` availability with CommandLineTools is macOS-version-dependent**
   - What we know: It exists at `/Library/Developer/CommandLineTools/usr/lib/libIndexStore.dylib` on this machine (macOS 26, Xcode 26.3). The earlier STACK.md research claimed it was Xcode-only.
   - What's unclear: Was this always the case, or is it a recent addition? Does it work on macOS 14/15 with older CommandLineTools?
   - RESOLVED: The runtime check (Plan 02-01) handles both cases gracefully — if the dylib is missing (regardless of cause), the error message tells the user to install Xcode or CommandLineTools. No need to resolve this definitively for the check to be correct.

3. **Static vs dynamic Swift runtime linking**
   - What we know: The binary dynamically links `/usr/lib/swift/libswift*.dylib` (verified via `otool -L`). These ship with macOS 12+.
   - What's unclear: Should we add `--static-swift-stdlib` for extra safety on older macOS?
   - RESOLVED: Do NOT add static linking. The formula requires `macos: :sonoma` (14+), where the Swift ABI runtime is always present. Static linking would bloat the binary by ~30MB for no benefit.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26 | Building arm64 + x86_64 binaries | ✓ | 26.3 | — |
| Swift 6.2.4 | Compiling scip-swift | ✓ | 6.2.4 | — |
| `lipo` | Creating universal binary | ✓ | Xcode 26 | — |
| GitHub Actions `macos-26` runner | Release CI | ✓ | GA | — |
| `gh` CLI | Creating GitHub Releases | ✓ | Pre-installed on runners | — |
| Homebrew tap repo (`homebrew-scip-swift`) | Formula hosting | ✗ | — | Must be created by user before first release |
| PAT (`HOMEBREW_TAP_TOKEN`) | Cross-repo push from CI | ✗ | — | Must be created and stored as repo secret |

**Missing dependencies with no fallback:**
- `homebrew-scip-swift` tap repository — must be created on GitHub before the first tagged release. The workflow will fail at the clone step if it doesn't exist.
- `HOMEBREW_TAP_TOKEN` secret — must be created in the main repo's Settings → Secrets. The workflow will fail at the push step if missing.

**Missing dependencies with fallback:**
- None — all other tools are available or pre-installed.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Suite`/`@Test`) — Swift's native testing framework |
| Config file | `Package.swift` (test target `scip-swiftTests`) |
| Quick run command | `swift test --filter ToolchainInfo` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DIST-01 | Formula passes `brew audit` | manual | `brew audit --strict Formula/scip-swift.rb` (local) | ❌ Wave 0 |
| DIST-02 | Universal binary contains both architectures | smoke | `lipo -info scip-swift` in release.yml | ❌ Wave 0 |
| DIST-02 | Universal binary runs `--version` | smoke | `./scip-swift --version` in release.yml | ❌ Wave 0 |
| DIST-03 | Release workflow triggers on `v*` tags | manual | Triggered manually via `git tag v0.2.0 && git push --tags` | ❌ Wave 0 |
| DIST-04 | Dylib missing → clear error | unit | `swift test --filter ToolchainInfoTests` | ❌ Wave 0 |
| DIST-04 | Error message mentions Xcode | unit | Assert error description contains "Xcode" | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `swift test` (full suite, ~30s for unit tests)
- **Per wave merge:** `swift test` + manual `brew audit` on formula
- **Phase gate:** Full suite green + universal binary verified + formula passes `brew audit`

### Wave 0 Gaps

- [ ] `Tests/scip-swiftTests/ToolchainInfoTests.swift` — unit tests for dylib path resolution and existence check (DIST-04)
- [ ] `Formula/scip-swift.rb` — template formula in main repo for reference (DIST-01)
- [ ] `.github/workflows/release.yml` — release workflow (DIST-03)
- [ ] `homebrew-scip-swift` tap repository — created externally on GitHub (DIST-01)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth in the tool itself; PAT auth is GitHub's responsibility |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | No access control in the tool |
| V5 Input Validation | yes | `xcrun` output is trimmed and validated before path derivation (existing pattern in `ToolchainInfo.swift`) |
| V6 Cryptography | no | No crypto operations |
| V8 Data Protection | yes | PAT (`HOMEBREW_TAP_TOKEN`) must be a GitHub secret, never hardcoded or logged |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tarball tampering in transit | Tampering | SHA256 verification in formula (Homebrew enforces this automatically) |
| PAT leaked in workflow logs | Information Disclosure | Use `${{ secrets.HOMEBREW_TAP_TOKEN }}` syntax (GitHub masks secrets in logs); never `echo` the token |
| Malicious tap injection | Spoofing | Users must explicitly `brew tap phuongddx/scip-swift`; Homebrew's tap trust model requires user confirmation |

## Sources

### Primary (HIGH confidence)

- **Homebrew Formula Cookbook** (`docs.brew.sh/Formula-Cookbook`) — fetched live this session. Verified: `depends_on macos: :sonoma` syntax, `license` SPDX requirement, `bin.install`, `test do` block, `sha256` mandatory, formula naming convention, `on_macos`/`on_intel` blocks.
- **Homebrew Taps docs** (`docs.brew.sh/Taps`) — fetched live. Verified: tap naming convention (`homebrew-<repo>` → `brew tap user/repo`), `brew install user/repo/formula` fully-qualified syntax.
- **Homebrew Bottles docs** (`docs.brew.sh/Bottles`) — fetched live. Verified: bottle DSL, `root_url` for custom taps, `cellar: :any_skip_relocation` — confirmed pre-built binary pattern is standard for custom taps.
- **GitHub Actions Runner Images** (`github.com/actions/runner-images`) — fetched live. Verified: `macos-26` (arm64) and `macos-26-intel` (x64) are GA; `macos-13` is gone; `macos-14` is deprecated. Full runner availability table confirmed.
- **Empirical build tests** — executed on this machine (Apple Silicon, macOS 26, Xcode 26.3, Swift 6.2.4):
  - `swift build -c release --triple arm64-apple-macosx` → arm64 binary ✅
  - `swift build -c release --triple x86_64-apple-macosx` → x86_64 binary ✅
  - `lipo -create arm64 x86_64 -output universal` → universal binary ✅
  - `lipo -info universal` → "x86_64 arm64" ✅
  - `./universal --version` → "0.1.2 (swift 6.2.4)" ✅
- **Project source files** (read this session):
  - `Sources/scip-swift/Platform/ToolchainInfo.swift:1-31` — dylib resolution via `xcrun --find swift`
  - `Sources/scip-swift/IndexStore/IndexStoreLoader.swift:1-12` — exact dylib loading point
  - `Sources/scip-swift/Build/BuildError.swift:1-43` — exhaustive error enum pattern
  - `Sources/scip-swift/Version.swift:1-5` — `ScipSwiftVersion.version = "0.1.2"`
  - `.github/workflows/ci.yml:1-30` — existing CI pattern (actions/checkout@v5, macos-26)
  - `Package.swift:1-29` — platforms: [.macOS(.v14)], swift-tools-version: 6.2
  - `.swift-version` — `6.2.4`
  - `LICENSE` — Apache License 2.0

### Secondary (MEDIUM confidence)

- `.planning/research/STACK.md` — prior Homebrew research (formula structure, tap rationale, `homebrew/core` blocker). Some claims about `libIndexStore.dylib` being Xcode-only were corrected by empirical testing this session.
- `.planning/research/PITFALLS.md` — Pitfall 5 (dylib not found) provided the original problem statement; the nuance about CommandLineTools was discovered during this research.
- GitHub Actions `GITHUB_TOKEN` scoping documentation — `[CITED: docs.github.com/en/actions/security-guides/automated-token-security]`

### Tertiary (LOW confidence)

- PAT vs deploy key tradeoff — `[ASSUMED]` based on general GitHub Actions knowledge, not verified against official docs this session.
- `sed -i ''` behavior on macOS runners — `[ASSUMED]` macOS runner uses BSD sed (same as local macOS); not explicitly tested in CI.

## Metadata

**Confidence breakdown:**
- Formula structure: HIGH — verified against official Formula Cookbook and Taps docs fetched live
- Universal binary approach: HIGH — empirically verified on this machine (both arch builds + lipo + run)
- Release workflow: HIGH — all components (actions/checkout, gh CLI, sed, git) are standard; workflow follows GitHub Actions conventions
- Dylib check location: HIGH — verified by reading exact source code of IndexStoreLoader.swift and BuildError.swift
- Runner availability: HIGH — fetched live from actions/runner-images README
- CommandLineTools dylib nuance: MEDIUM — discovered empirically on this machine but macOS-version-dependence unconfirmed

**Research date:** 2026-08-12
**Valid until:** 2026-09-12 (30 days — stable infrastructure; runner labels may change on GitHub's deprecation schedule)
