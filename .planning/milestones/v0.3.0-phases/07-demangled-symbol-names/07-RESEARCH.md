# Phase 7: Demangled Symbol Names - Research

**Researched:** 2026-08-16
**Domain:** Swift USR demangling (libswiftDemangle C ABI) → SCIP `SymbolInformation.display_name`
**Confidence:** HIGH (all load-bearing claims verified against repo source this session, or by compiling/running scratch binaries against the pinned Swift 6.2.4 / Xcode 26 toolchain)

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SYMBOL-01 | Demangled human-readable names replace raw `s:` USRs | dlopen+`swift_demangle_getDemangledName` verified on real index-store USRs (§D2); attach via `display_name` (§D1) |
| SYMBOL-02 | `c:`/undemanglable symbols keep opaque form; indexing never fails | `c:` inputs return 0 from the C ABI; closure/local-suffix USRs fail → fallback contract (§D3, Pitfall 2/3) |
| SYMBOL-03 | Wrapped USR stays canonical `symbol`; cache/merge unchanged | Formatter is the sole symbol-string chokepoint and stays untouched (§D1); cache bump via `converterVersion` (§D4) |
| SYMBOL-04 | `--no-demangle` reproduces v0.2.x output | Default-on flag threading via defaulted `indexOneRepo` param, Phase-6 pattern (§D5) |
</phase_requirements>

## Summary

SYMBOL-03 locks the canonical `symbol` field to today's wrapped-USR string, which forces the demangled text into `SymbolInformation.display_name` (field 6) — the field the vendored spec defines for exactly this purpose: `[VERIFIED: Protos/scip.proto:426-437]` — "(optional) The name of this symbol as it should be displayed to the user. For example, the symbol `com/example/MyClass#myMethod(+1).` should have the display name `myMethod`. The `symbol` field is not a reliable source of the display name..." Today the builder sets `symbolInformation.displayName = symbol.name` (IndexStoreDB short name) at `SCIPIndexBuilder.swift:157` and leaves external symbols' `displayName` empty. The change is confined to those display sites; every identity-bearing path (`document.symbols[].symbol`, occurrences, `enclosingSymbol`, relationships, `externalSymbols[].symbol`, merger dedup keys) routes through `SCIPSymbolFormatter.globalSymbolString` `[VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:135-146,164,177-182]` — verified the only 3 call sites in Sources — and is untouched.

Correction to milestone ARCHITECTURE.md: its "demangle the symbol string into descriptor chains inside SCIPSymbolFormatter" plan is incompatible with SYMBOL-03 and its `@_silgen_name("swift_demangle")` mention is not viable. Empirically: `nm` shows NO dylib (system or toolchain) exports the bare `_swift_demangle` symbol; a scratch `@_silgen_name` binary compiled but returned nil for every valid input `[VERIFIED: scratch run + nm scan]`. The working in-process path is `dlopen("<toolchain>/usr/lib/libswiftDemangle.dylib")` + `dlsym(handle, "swift_demangle_getDemangledName")`, verified exported `[VERIFIED: nm -gU ...libswiftDemangle.dylib → 00000000000015c0 T _swift_demangle_getDemangledName]` and called successfully.

**Primary recommendation:** New `USRDemangler` (SCIPMapping/, memoized class owned per-`build()`), dlopen via `xcrun --find swift` mirroring `ToolchainInfo.libIndexStoreDylibPath()`, C ABI `(const char*, char* buffer, size_t maxLen) -> size_t` (caller-owned buffer — **no free() needed**; returns full required length, 0 on failure), `s:`→`_$s` rewrite, output replaces `displayName` for non-local symbols + fills currently-empty external-symbol display names; `--no-demangle` restores `symbol.name`; bump `ScipSwiftVersion` 0.2.1→0.3.0.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| USR→demangled string | New `USRDemangler` (SCIPMapping/) | — | Pure transform + memoization; mappers stay stateless enums per codebase convention |
| Display-name attachment | `SCIPIndexBuilder.makeDocument` (:157) + externalSymbols loop (:84-92) | — | Only sites that build `SymbolInformation` |
| Canonical symbol identity | `SCIPSymbolFormatter` (UNCHANGED) | — | Sole chokepoint for symbol strings; untouched this phase |
| Dylib resolution | `ToolchainInfo`-style helper (xcrun) | — | Never hardcode `/Applications/Xcode.app` (ARCHITECTURE.md anti-pattern, re-confirmed) |
| Flag parsing | `IndexCommand` `@Flag` | — | Threaded as defaulted param; `IndexManyCommand` compiles unchanged |
| Cache invalidation | `ScipSwiftVersion` bump → `IndexManifest.converterVersion` | — | Existing 4-layer mechanism; no schema change |

## Key Verified Facts (empirical, scratch binaries, Swift 6.2.4)

C ABI signature confirmed by calling it — 3 args, caller buffer `[VERIFIED: scratch run]`:
`swift_demangle_getDemangledName(mangledName, outputBuffer, maxLength) -> size_t`

Real USRs extracted from the fixture's index store, demangled via the rewrite `s:X` → `_$sX` `[VERIFIED: strings on /tmp build's index/store records + scratch run]`:
- `s:16MiniSwiftPackage7GreeterV` → `MiniSwiftPackage.Greeter`
- `s:16MiniSwiftPackage7GreeterV5greetSSyF` → `MiniSwiftPackage.Greeter.greet() -> Swift.String`
- `s:16MiniSwiftPackage7GreeterV4nameACSS_tcfc` → `MiniSwiftPackage.Greeter.init(name: Swift.String) -> MiniSwiftPackage.Greeter`
- `s:16MiniSwiftPackage7GreeterV4nameSSvg` → `MiniSwiftPackage.Greeter.name.getter : Swift.String` (`.SSvs` → `.setter`)
- `s:16MiniSwiftPackage7GreeterV4nameACSS_tcfcADL_SSvp` → `name #1 : Swift.String in MiniSwiftPackage.Greeter.init(...)`
- `s:SS` → `Swift.String`; `s:SS5countSivg` → `Swift.String.count.getter : Swift.Int`

Failure modes, all returning 0 (safe) `[VERIFIED: scratch run]`: `c:objc(cs)NSObject`, `c:@F@printf`, closure `_$s4null5greetyyFyS2ScfU_`, local-func `_$s4null5outer5inneryyFyyxlF`, empty/garbage. Buffer semantics: 4-byte buffer on a 66-byte result returns **66** with truncated content → retry with `n+1` when `n >= buffer.count`.

## Decisions

**D1 — Display layer, not symbol string (forced by SYMBOL-03).** `symbol` field stays `scip-swift swiftpm MiniSwiftPackage . \`s:...\`.` verbatim per `[VERIFIED: Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift:24-30]`: `return "\(escapeSpaceField(scheme)) \(manager) \(packageName) \(versionField) \(descriptor)"`. `SCIPSymbolFormatter` and all 11 of its tests are untouched. Merger dedup keys (`doc.symbols.map(\.symbol)`, `external.symbol` — `ScipIndexMerger.swift:28-38`) never see a difference.

**D2 — dlopen the dylib, not subprocess, not @_silgen_name.** `SubprocessRunner.run` has no stdin support `[VERIFIED: Sources/scip-swift/Build/SubprocessRunner.swift:22-63 — only stdout/stderr pipes]`, so the ARCHITECTURE.md batched-CLI fallback would need new plumbing; also the CLI echoes failures back unchanged (verified), making failure detection a string comparison. dlopen path: derive from `xcrun --find swift` exactly like `[VERIFIED: Sources/scip-swift/Platform/ToolchainInfo.swift:14-33]` (`usrRoot.deletingLastPathComponent` + `lib/libswiftDemangle.dylib`). If dlopen/dlsym fails → fall back to `symbol.name` (never throw; SYMBOL-02).

**D3 — Scope: non-local symbols only.** Locals (`local <n>`, `LocalSymbolNumberer`) and closure/local-suffix USRs keep `symbol.name` — their manglings are the ones that fail to demangle (verified above), and local context already lives in `enclosingSymbol`. Fewer edge cases, exact v0.2.x parity for locals.

**D4 — Cache bump = version constant only.** Cached `Scip_Document`s embed the old `displayName` (`CacheStore.loadDocument` returns the whole document `[VERIFIED: Sources/scip-swift/Caching/CacheStore.swift:27-31]`), so a stale cache would serve non-demangled names forever. Bump `[VERIFIED: Sources/scip-swift/Version.swift:5]` — `static let version = "0.2.1"` — to `"0.3.0"`; the manifest check at `[VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:118-141]` compares `converterVersion: ScipSwiftVersion.version` and calls `store.invalidateAll()` on mismatch. Mechanism already proven by `[VERIFIED: Tests/scip-swiftTests/IndexManifestTests.swift:47]` ("isCompatibleWith returns false when converterVersion differs"). No `IndexManifest` schema change.

**D5 — `--no-demangle`, demangling default-on.** SYMBOL-04 says "User can disable demangling", so default is on. `@Flag(name: .long, help: "Emit v0.2.x opaque symbol display names instead of demangled ones.") var noDemangle = false` on `IndexCommand`, thread `demangle: !noDemangle` as a defaulted `indexOneRepo` param (→ `SCIPIndexBuilder(demangle:)`), exactly the Phase-6 `destination: String? = nil` pattern `[VERIFIED: Sources/scip-swift/Commands/IndexCommand.swift:64]`. `IndexManyCommand` gets no flag (Phase-6 precedent — deliberately excluded there).

**D6 — Memoization placement.** `build()` owns `var demangler = USRDemangler()` and passes it into `makeDocument` (which already takes `inout` accumulators `[VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:113-118]`) and consults it again in the externalSymbols loop for refs not seen as definitions. Deterministic pure function of the dylib → second-run byte-identity holds; toolchain drift is covered by the manifest's `toolchainVersion` layer.

**D7 — Externals gain display names.** `externalSymbols` entries are built with `info.symbol = sym` and no `displayName` today `[VERIFIED: Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift:84-92]`. Demangle mode fills them (`Swift.String.count.getter : Swift.Int` etc. — the most common hovers); `--no-demangle` leaves them empty (v0.2.x parity).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Demangling | Custom USR parser / descriptor-chain splitter | `swift_demangle_getDemangledName` via dlopen | Compiler's own printer; every hand-split edge case (generics, operators, accessors) already handled |
| Dylib location | Hardcoded `/Applications/Xcode.app/...` | `xcrun --find swift` → toolchain root | Multi-Xcode installs / CLT-only machines |
| Symbol identity | Rewriting `symbol` strings post-hoc | Keep formatter untouched | String is the cross-reference key in 5 places (ARCHITECTURE.md anti-pattern, confirmed in source) |

## Common Pitfalls

### Pitfall 1: Mangling drift (fallback contract)
**What goes wrong:** A future Swift mangling construct returns 0; code treats that as error and aborts, or emits empty `displayName`.
**Avoid:** Return `symbol.name` on ANY failure (0-length, dylib missing, non-`s:` prefix). Empty output must never reach the index. Corpus test asserts fallback on closure/`c:`/garbage inputs.
**Warning signs:** Empty `display_name` in a produced index; indexing run failing with demangle errors.

### Pitfall 2: Non-Swift USRs (`c:`, `so:`, `_:`)
**What goes wrong:** Passing `c:objc(cs)NSObject` to the demangler — returns 0 (verified), but code that rewrites prefixes blindly could corrupt it.
**Avoid:** Gate strictly on `usr.hasPrefix("s:")`; everything else falls back to `symbol.name` untouched.

### Pitfall 3: Closures and local-suffix USRs
**What goes wrong:** Closure USRs (`...cfU_`) and local-decl USRs (`...L...`) fail to demangle (verified); treating them as bugs or crashing.
**Avoid:** D3 scope (skip locals entirely). Globals whose demangle fails (rare) take the Pitfall-1 fallback.

### Pitfall 4: Cache serving stale display names
**What goes wrong:** Cached documents embed `displayName`; without invalidation, users see mixed old/new names indefinitely.
**Avoid:** D4 version bump lands in the SAME task set as the display change. Warning sign: `cacheMissThenHit`-style test showing a hit when it must miss after upgrade.

### Pitfall 5: Merge/dedup instability
**What goes wrong:** Any accidental change to the canonical `symbol` string breaks cross-repo dedup between v0.2.x- and v0.3.x-produced indexes and silently changes occurrence↔SymbolInformation joins.
**Avoid:** Formatter untouched; `ScipIndexMergerTests` (handcrafted `scip-swift swiftpm X . \`s:...\`.` strings `[VERIFIED: Tests/scip-swiftTests/ScipIndexMergerTests.swift:32,72,98,160,183-189]`) must pass unmodified — that's the regression guard. `MultiRepoMergeIntegrationTests` invariants must pass unchanged.

## Code Examples

### Demangler core (verified scratch logic, production skeleton)
```swift
// Sources/scip-swift/SCIPMapping/USRDemangler.swift
final class USRDemangler {
  private typealias Fn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, UInt) -> UInt
  private let fn: Fn?
  private var cache: [String: String] = [:]

  init?() { /* dlopen ToolchainInfo-style; dlsym "swift_demangle_getDemangledName" */ }

  // nil = "keep symbol.name" (fallback contract, SYMBOL-02)
  func demangledDisplayName(usr: String) -> String? {
    guard usr.hasPrefix("s:") else { return nil }
    if let hit = cache[usr] { return hit }
    let mangled = "_$s" + usr.dropFirst(2)
    var size = 1024
    var buf = [CChar](repeating: 0, count: size)
    let n = fn?(mangled, &buf, UInt(size)) ?? 0
    if n == 0 { cache[usr] = ""; return nil }          // 0 = failure
    if n >= size {                                      // truncated: retry with n+1
      buf = [CChar](repeating: 0, count: n + 1)
      _ = fn?(mangled, &buf, UInt(n + 1))
    }
    let out = String(cString: buf)
    cache[usr] = out
    return out.isEmpty ? nil : out
  }
}
```
Caller at `SCIPIndexBuilder.swift:157`: `symbolInformation.displayName = (demangle ? demangler?.demangledDisplayName(usr: symbol.usr) : nil) ?? symbol.name`.

## Validation Architecture

**Framework:** Swift Testing (`@Suite`/`@Test`), `Tests/scip-swiftTests/`. Quick: `swift test --filter USRDemangler`. Full: `swift test`.

| Req | Behavior | Type | Command | Exists? |
|-----|----------|------|---------|---------|
| SYMBOL-01 | real USRs → demangled strings (corpus incl. getter/setter/init/stdlib) | unit | `swift test --filter USRDemanglerTests` | ❌ Wave 0 |
| SYMBOL-02 | `c:`/closure/garbage/missing-dylib → `symbol.name`, no throw | unit | same suite | ❌ Wave 0 |
| SYMBOL-03a | second-run byte-identity WITH demangling on | integration | `swift test --filter IncrementalIntegrationTests` | ✅ (asserts `data1 == data2`; runs demangled path via default) |
| SYMBOL-03b | merge dedup unchanged | unit+integration | `swift test --filter ScipIndexMerger` | ✅ must pass unmodified |
| SYMBOL-03c | converterVersion bump invalidates cache | unit/integration | new test vs `IndexManifestTests.swift:47` + new cache-upgrade integration test | ❌ Wave 0 |
| SYMBOL-04 | `--no-demangle` output == v0.2.x displayName values | integration | new builder-level test comparing `demangle: false` run's `displayNames` to current expectations | ❌ Wave 0 |
| E2E | index contains `MiniSwiftPackage.Greeter.greet() -> Swift.String` | integration | extend `IntegrationTests.fullPipeline` | ✅ re-baseline |

**Re-baselining surface (measured blast radius):** `IntegrationTests.swift:42-45` (`#expect(displayNames.contains("Greeter"))` / `("greet()")` / `("name")` — exact-match Set.contains breaks when displayName becomes `MiniSwiftPackage.Greeter`) and `RelationSpikeTests.swift:117` (`#expect(displayNames.contains("Dog"))` in `dumpAllRelations` — becomes `RelationSpike.Dog`: the fixture module is `RelationSpike` per `Fixtures/RelationSpikeFixture/Package.swift`, `Dog` is a top-level class, and that suite's builder call passes no `demangle:` argument so it exercises default-on demangling; it is the suite's only SCIP display-name assertion — the rest match IndexStoreDB `occurrence.symbol.name`, untouched by demangling). `SCIPSymbolFormatterTests`, `CacheStoreTests`, `IndexManifestTests`, `ScipIndexMergerTests`: untouched. `IncrementalIntegrationTests`: no edit needed (equality assertions hold once demangling is deterministic), but must run green post-change.

**Sampling:** per task `swift test --filter <suite>`; phase gate `swift test` (CI runs full suite on macos-26).

**Wave 0 gaps:** `Tests/scip-swiftTests/USRDemanglerTests.swift` (SYMBOL-01/02 corpus), cache-upgrade invalidation test, `--no-demangle` parity test.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode toolchain (xcrun) | dylib resolution | ✓ | 6.2.4 pinned (`.swift-version`) | — |
| `libswiftDemangle.dylib` | SYMBOL-01 | ✓ (local toolchain, `nm`-verified export) | Xcode 26 | `symbol.name` fallback (nil-return contract) |
| `xcrun swift-demangle` CLI | none (rejected path) | ✓ | — | — |

No new Package.swift dependency — zero ecosystem packages installed this phase.

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | USRs are index-store-sourced, not user input; fixed-size caller buffers with retry bound the C call |
| V2/V3/V4/V6 | no | Local CLI, no auth/session/crypto surface; dlopen targets the toolchain's own dylib via `xcrun`, not a path from user input |

## Sources

### Primary (HIGH)
- Repo source read this session: `SCIPSymbolFormatter.swift`, `SCIPIndexBuilder.swift`, `IndexManifest.swift`, `IndexCommand.swift`, `ScipIndexMerger.swift`, `CacheStore.swift`, `ToolchainInfo.swift`, `SubprocessRunner.swift`, `Version.swift`, `Protos/scip.proto`, all affected test files
- Empirical (2026-08-16, Swift 6.2.4/Xcode 26): scratch `swiftc` binaries calling `swift_demangle_getDemangledName` via dlopen on real index-store-extracted USRs; `nm -gU` on toolchain dylibs (export table); buffer-truncation probe; `swift-demangle --compact` cross-check
- `.planning/research/ARCHITECTURE.md` (milestone research; two of its claims corrected here with evidence)

### Secondary (MEDIUM)
- [CITED: github.com/swiftlang/swift/blob/main/include/swift/Demangling/Demangle.h] — C++ DemangleOptions/Context API; notably does NOT declare the C `swift_demangle_getDemangledName` (consistent with the symbol living in the dylib's C export table, verified via nm)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | CI macos-26 image ships the same `libswiftDemangle.dylib` (same pinned toolchain) | Environment | Demangle silently off in CI; fallback contract covers correctness, SYMBOL-01 e2e would fail loudly |
| A2 | SCIP consumers render `display_name` when present (proto defines it for this purpose; specific consumer UI behavior not verifiable here) | D1 | If some consumer renders raw `symbol` only, readability win is partial — locked by SYMBOL-03 regardless |

## Metadata

**Confidence breakdown:** Demangler mechanics HIGH (empirical); integration sites HIGH (source-read); consumer display behavior MEDIUM (A2).
**Research date:** 2026-08-16. **Valid until:** 2026-09-15 (stable — toolchain-pinned).
