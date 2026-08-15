# scip-swift: Project Roadmap

## Current Status

**Version**: 0.2.1 (current — see `Sources/scip-swift/Version.swift`)

**Status**: Shipped and available as a macOS arm64 binary via [GitHub Releases](https://github.com/phuongddx/scip-swift/releases). The initial release was v0.1.0; v0.1.1 and v0.1.2 are patch releases (the `index` subcommand as the `defaultSubcommand`, and disabled code signing for index-only `xcodebuild` runs so app-extension targets don't fail provisioning).

### What's Shipped

- Full end-to-end SCIP indexing pipeline for Swift
- Support for both SwiftPM and Xcode-based projects
- Automatic build system detection and scheme resolution
- IndexStoreDB integration for compiler-level symbol data
- Protobuf serialization via `SwiftProtobuf`
- Comprehensive test coverage (unit + integration tests)
- Well-documented limitations and design decisions

## Known Open Items

### 1. Homebrew Distribution Formula

**Status**: Shipped (v0.2.0; see `Formula/scip-swift.rb`)

**Description**: Currently, users must build from source or download the arm64 binary directly. A Homebrew formula would simplify distribution and make `scip-swift` easier to install via `brew install phuongddx/tap/scip-swift` or similar.

**Effort**: Low (~2-4 hours for formula + tap setup)

**Complexity**: Formulae automation is straightforward; may need to consider x86_64 support as well.

**Timeline**: Post-v0.1.0 nice-to-have; not blocking core functionality.

### 2. Exact Occurrence Range Recovery

**Status**: Deferred (design limitation documented)

**Description**: Currently, occurrence end-columns are approximated from symbol display-name length. A more exact approach would require:

- AST-level symbol location data (source line/column of the identifier itself, not just the anchor point)
- Extended IndexStore query API (may not be publicly available in IndexStoreDB)
- Fallback to source-file parsing (lexing to match symbol boundaries)

**Impact**: Low (ranges are correct 95% of the time for simple names; compound names like `greet(name:)` can be slightly off)

**Effort**: Medium (~8-16 hours research + implementation)

**Timeline**: Future enhancement; current approximation is acceptable for SCIP tools.

### 3. Demangled Symbol Names

**Status**: Deferred (design decision: keep USRs opaque)

**Description**: SCIP symbol identities currently use raw compiler USRs (e.g., `_$s5Hello7GreeterC7sayHelloyySSF`), which are not human-readable. A future version could offer demangled names (e.g., `Hello.Greeter.sayHello()`) by:

- Integrating the Swift compiler's mangling library (if made public)
- Parsing and demangling USRs using a custom demangler
- Providing both raw and demangled names in the SCIP output

**Impact**: Medium (aids human readability in SCIP output, but doesn't affect correctness or tool interoperability)

**Effort**: High (~20+ hours; compiler library integration or custom demangler)

**Timeline**: Post-v0.2.0; potential enhancement if community feedback warrants it.

### 4. USR Stability Across Toolchain Versions

**Status**: Ongoing risk to monitor

**Description**: Apple does not guarantee USR stability across Swift compiler versions. The project currently pins the toolchain to `6.2.4`. 

**Risk**: If a user rebuilds with a different Swift version, USRs may change, breaking symbol identity across indexes.

**Mitigation**:
- Document the toolchain pinning prominently in README and PDR ✅
- Test against older and newer Swift versions (periodic, not CI)
- Consider future versioning strategy for symbol identity changes

**Timeline**: Ongoing; monitoring with each Swift release.

## Potential Future Features

### A. Cross-Repository Symbol Resolution

**Status**: Shipped (v0.2.0) — `index-many` subcommand with `--merge` (`Commands/IndexManyCommand.swift`) and `SCIPMapping/ScipIndexMerger.swift`.

**Description**: Enable indexing multiple repositories and merging their SCIP outputs to resolve cross-repo symbol references (e.g., when RepoA references a type from RepoB).

**Approach**:
- Index each repo independently to produce separate `.scip` files
- Use SCIP's built-in symbol merging (external_symbols) to link repos
- Tool coordination (Sourcegraph can coordinate symbol resolution across merged indexes)

**Timeline**: Post-v0.2.0; useful for monorepo / workspace scenarios.

### B. Incremental Indexing

**Status**: Shipped (v0.2.0) — `Sources/scip-swift/Caching/` (`CacheStore.swift`, `ContentHasher.swift`, `IndexManifest.swift`) and the `--cache-dir` option in `IndexCommand.swift`.

**Description**: Avoid re-querying the entire IndexStore when only a few files changed. Cache IndexStore query results.

**Approach**:
- Detect which files changed since the last index
- Only reprocess changed files' symbol occurrences
- Merge new occurrences with cached ones

**Timeline**: Post-v0.1.0; optimization for large projects.

### C. Streaming Protobuf Serialization

**Feasibility**: Low

**Description**: For extremely large indexes, write protobuf messages to disk incrementally rather than building the entire `Scip_Index` in memory.

**Approach**:
- Implement custom protobuf writer for streaming
- Write documents as they complete, instead of accumulating in memory

**Timeline**: Post-v0.2.0; only if memory becomes a bottleneck for large codebases.

### D. Parallel Symbol Processing

**Feasibility**: Low

**Description**: Process symbol occurrences in parallel (per-file or per-symbol kind) to speed up conversion.

**Challenges**: SCIP symbol deduplication and external_symbols tracking would need synchronization.

**Timeline**: Post-v0.2.0; only if conversion becomes a bottleneck (currently build time dominates).

### E. Extended Symbol Metadata

**Status**: Partially shipped (v0.2.0) — minimal type signatures via `SCIPMapping/SignatureMapping.swift` and inheritance/`childOf` relationships via `SCIPMapping/RelationshipMapping.swift`; docstring extraction remains future work.

**Description**: Enhance SCIP output with additional metadata:

- Type signatures (return types, parameter types)
- Docstring extraction (from source comments)
- Inheritance relationships
- Protocol conformance

**Approach**: Extract from IndexStoreDB's extended attributes or parse source comments.

**Timeline**: Future enhancement; depends on SCIP spec extensions or custom extensions.

## Version Roadmap

### v0.1.0 ✅
- Core pipeline (build → IndexStore → SCIP)
- SwiftPM + Xcode support
- Comprehensive testing
- Documentation
- **Status**: Released

### v0.1.1 (If Needed)
- Bug fixes
- Improved error messages
- Minor UX improvements
- **Status**: Released. Followed by v0.1.2 (`index` subcommand as `defaultSubcommand`; disabled code signing for index-only `xcodebuild` runs).

### v0.2.0 (Tentative)
- Homebrew formula
- Incremental indexing (optional cache)
- Enhanced symbol metadata
- Cross-repo symbol linking (optional)
- **Estimate**: Q4 2026–Q1 2027

### v1.0.0 (Future)
- Demangled symbol names
- Exact occurrence ranges
- Performance optimizations
- Full feature parity with other SCIP indexers
- **Estimate**: H2 2027+

## Success Metrics

### Short-term (v0.1.x — achieved)
- ✅ Valid SCIP protobuf output (`scip lint` passes)
- ✅ End-to-end pipeline tested and documented
- ✅ Handles real Swift projects (both SwiftPM and Xcode)
- ✅ Published as open source with clear limitations

### Medium-term (v0.2.0)
- Homebrew availability
- Growing community adoption (GitHub stars, issues, contributions)
- Feedback on exact ranges and symbol names
- Integration with at least one public SCIP tool (Sourcegraph, editor plugin)

### Long-term (v1.0.0+)
- Feature parity with established indexers (Python, Go, TypeScript)
- Support for multiple Swift versions (toolchain version handling)
- Multi-repository indexing use cases
- Performance suitable for large codebases (100k+ files)

## Community Contributions

The project is open to community contributions. Areas where help would be particularly valuable:

1. **Homebrew formula** — Packaging and distribution
2. **x86_64 support** — Build and test on Intel Macs
3. **Linux investigation** — Assess feasibility of Linux support (likely requires vendored IndexStore bindings)
4. **Xcode plugin** — Integration with Xcode's code intelligence (if SCIP support is added to Xcode)
5. **Editor plugin examples** — Demonstrate SCIP usage in VS Code, JetBrains IDEs, etc.
6. **Documentation** — Tutorials, architecture guides, troubleshooting

See [CONTRIBUTING.md](../CONTRIBUTING.md) (if applicable) or open an issue on GitHub to discuss.

## Blockers & Risks

| Risk | Severity | Mitigation |
|---|---|---|
| IndexStore API changes in future Swift versions | Medium | Monitor Apple release notes; update IndexStoreDB dependency |
| USR format instability across toolchain versions | Medium | Document pinning; periodic compatibility testing |
| Large codebase performance (memory/time) | Low | Profile with real projects; implement streaming if needed |
| macOS/Xcode SDK availability for Apple frameworks | Fixed | Architectural decision; not a risk—platform is inherently macOS-only |
| Community adoption and feedback | Low | Active issue management, responding to questions |

## References

- **Design & Architecture**: [docs/system-architecture.md](./system-architecture.md)
- **Implementation Standards**: [docs/code-standards.md](./code-standards.md)
- **Project PDR**: [docs/project-overview-pdr.md](./project-overview-pdr.md)

## How to Contribute to the Roadmap

If you'd like to influence this roadmap or propose new features:

1. Open a [GitHub Issue](https://github.com/phuongddx/scip-swift) with your idea
2. Discuss trade-offs and priority
3. Help prioritize by indicating use cases and interest
4. Contribute code for any of the roadmap items above

---

*Last updated: August 2026 | v0.2.1*
