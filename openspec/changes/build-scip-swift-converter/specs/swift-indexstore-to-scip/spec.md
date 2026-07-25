## ADDED Requirements

### Requirement: Build-index generation
The system SHALL produce an IndexStore for a target Swift repo by invoking either `swift build -index-store-path <path>` (SwiftPM) or `xcodebuild -index-store-path <path>` (Xcode-project apps), per the caller's selected or detected build backend.

#### Scenario: SwiftPM repo indexed via `swift build`
- **WHEN** the CLI is invoked against a repo that builds via SwiftPM
- **THEN** it SHALL run `swift build -index-store-path <path>` and produce a valid IndexStore at that path

#### Scenario: Xcode-project repo indexed via `xcodebuild`
- **WHEN** the CLI is invoked against a repo that builds via an Xcode project/workspace (not SwiftPM)
- **THEN** it SHALL run `xcodebuild -index-store-path <path>` and produce a valid IndexStore at that path

#### Scenario: Build command fails
- **WHEN** the underlying `swift build` or `xcodebuild` invocation fails
- **THEN** the CLI SHALL surface a non-zero exit code and a clear error message identifying which build command failed and why

### Requirement: IndexStoreDB to SCIP protobuf conversion
The system SHALL read the generated IndexStore via `swiftlang/indexstore-db`'s `SymbolOccurrence` query API and emit genuine `scip.proto`-conformant output (`Document`, `Symbol`, `Occurrence` messages via `SwiftProtobuf`) — not a custom or SCIP-inspired schema.

#### Scenario: Successful conversion produces valid SCIP
- **WHEN** a valid IndexStore is read
- **THEN** the CLI SHALL emit a SCIP index whose `Document`/`Symbol`/`Occurrence` messages validate against `scip.proto` and are consumable by standard SCIP tooling (e.g. the `scip` CLI's own validation/inspection commands)

#### Scenario: Definition, write, and reference roles map correctly
- **WHEN** an IndexStoreDB occurrence has role `.definition`, `.write`, or `.reference` (without `.write`)
- **THEN** the corresponding SCIP `Occurrence.symbol_roles` SHALL be `Definition`, `WriteAccess`, or `ReadAccess` respectively

#### Scenario: Call role rides along on the occurrence's other roles
- **WHEN** an IndexStoreDB occurrence has role `.call` (a call site, which IndexStoreDB always pairs with `.reference` and/or `.read` on the same occurrence)
- **THEN** the CLI SHALL NOT invent a SCIP role bit for it — real `scip.proto`'s `SymbolRole` enum has no call-specific bit (call hierarchy in SCIP is derived from `Relationship`/enclosing-range data, not `symbol_roles`) — and the occurrence SHALL still carry whichever of `ReadAccess`/`WriteAccess`/`Definition` its other IndexStoreDB roles map to

### Requirement: Toolchain version pinning
The system SHALL pin the Swift toolchain version used to build and run the converter, and SHALL surface that pinned version in the CLI's own version output.

#### Scenario: Version mismatch is discoverable
- **WHEN** a user runs the CLI's `--version` (or equivalent) command
- **THEN** it SHALL report both the converter's own version and the Swift toolchain version it was built against

### Requirement: Platform constraint enforcement
The system SHALL clearly fail, rather than silently produce an incomplete index, when asked to index Apple-platform-dependent code on a host that cannot compile it (e.g. a non-macOS host indexing code that imports `UIKit`/`WatchKit`/`WidgetKit`).

#### Scenario: Non-macOS host attempts to index UIKit-dependent code
- **WHEN** the CLI is invoked on a non-macOS host against a repo that imports an Apple-platform-only framework
- **THEN** the underlying build command SHALL fail (since the iOS SDK is unavailable), and the CLI SHALL surface a clear error rather than a partial or misleading index
