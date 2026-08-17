/// Requirement: Toolchain version pinning — the CLI's own version.
///
/// Bump this on tagged releases (Decision 4: distributed as a compiled binary release).
enum ScipSwiftVersion {
  static let version = "0.3.0"

  /// Requirement: D-14 (02-03) — the pinned `scip` CLI version the CI gate downloads
  /// (scip-code/scip releases, checksum-verified per D-12) and the engine surfaces in
  /// ToolInfo. Single source of truth: CI's `SCIP_CLI_VERSION` must match this value —
  /// the ScipCLIGate suite cross-checks the running binary's version against it. Bumps
  /// are explicit; Phase 6 aligns it with the orchestrator repo's cmd/scip/version.txt.
  static let scipCliVersion = "0.9.0"
}
