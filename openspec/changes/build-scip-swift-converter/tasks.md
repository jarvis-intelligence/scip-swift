## 1. Project scaffold

- [ ] 1.1 Create `Package.swift` (executable target `scip-swift`), depending on `swiftlang/indexstore-db`, `SwiftProtobuf`, and an argument-parsing library
- [ ] 1.2 Vendor or generate a Swift module from `scip.proto` (sourcegraph/scip) for `SwiftProtobuf` codegen
- [ ] 1.3 Pin the Swift toolchain version (`.swift-version` / CI image pin) per design Decision 5

## 2. Build-index generation

- [ ] 2.1 Implement `swift build -index-store-path <path>` invocation for SwiftPM repos
- [ ] 2.2 Implement `xcodebuild -index-store-path <path>` invocation for Xcode-project repos
- [ ] 2.3 Resolve open question: auto-detect SwiftPM vs. Xcode-project, or require an explicit flag
- [ ] 2.4 Surface clear, actionable errors when the underlying build command fails

## 3. IndexStoreDB → SCIP mapping

- [ ] 3.1 Resolve the open question: exact `Symbol.scip_symbol` string-mangling scheme derived from Swift's USR format
- [ ] 3.2 Implement `Symbol.name` → `Symbol.display_name` mapping
- [ ] 3.3 Implement occurrence-role mapping (`.definition`/`.reference`/`.call` → `Definition`/`ReadAccess`/`ForwardCall`)
- [ ] 3.4 Implement `Symbol.kind` → SCIP `Symbol.kind` enum mapping
- [ ] 3.5 Implement `SymbolOccurrence.location` → `Occurrence.range` mapping
- [ ] 3.6 Emit a complete `scip.proto` `Document`/`Index` structure from the mapped data

## 4. Validation

- [ ] 4.1 Validate emitted output against the `scip` CLI's own validation/inspection tooling
- [ ] 4.2 Validate emitted output is consumable end-to-end by a real downstream consumer's `scip expt-convert` step (e.g. `codeintel`)
- [ ] 4.3 Add unit tests for the USR-mangling and role/kind mapping logic
- [ ] 4.4 Add an integration test running the full pipeline (build → IndexStore → SCIP) against a small real Swift fixture repo

## 5. CLI polish & distribution

- [ ] 5.1 Implement `--version` output reporting both converter version and pinned Swift toolchain version
- [ ] 5.2 Write README covering install, usage, macOS-host requirement, and known limitations
- [ ] 5.3 Set up CI on a macOS runner (build + test on every push)
- [ ] 5.4 Publish a tagged release with a prebuilt macOS binary (GitHub Releases, optionally Homebrew)

## 6. Infra decision (tracked, not blocking v1)

- [ ] 6.1 Decide macOS build-host topology for ongoing CI/releases (self-hosted Mac mini vs. cloud Mac CI runner) — out of scope for code, but needed before recurring releases
