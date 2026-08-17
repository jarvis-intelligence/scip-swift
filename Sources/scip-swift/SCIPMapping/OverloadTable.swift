import Foundation
import IndexStoreDB

/// Requirement: SYM-03 / D-07 — source-order overload disambiguation at symbol-table
/// assembly time.
///
/// Overload indices `(+N)` are assigned per (module, container path, name) group over the
/// Method declaration family: group members are sorted by the source position of their
/// DEFINITION occurrence — (relativePath, line, utf8Column) ascending, assumption A1 — and
/// indexed 0..N-1 from that order. Index 0 renders no disambiguator; index N renders `(+N)`.
/// Indices are NEVER derived from USR bytes (signature ordering, mangling): source order at
/// assembly time is the only rule (D-07). Because every occurrence of one USR looks up the
/// same table entry, definitions and references render identical strings by construction —
/// the `scip lint` `missingSymbolForOccurrenceError` contract.
///
/// A class (not the stateless enum-namespace mapper convention) because it is built once per
/// `build()` from a light definitions pre-pass and then read for the whole document-emission
/// phase, mirroring `USRDemangler`'s build-once memoization rationale.
final class OverloadTable {
  /// One definition occurrence: everything needed to group and order it.
  struct Definition {
    let usr: String
    let module: String
    let containerNames: [String]
    let name: String
    let kind: DeclKind
    let relativePath: String
    let line: Int
    let utf8Column: Int
  }

  /// The declaration kinds whose descriptors carry disambiguators (the frozen scheme renders
  /// `(+N)` solely on Method descriptors — namer.go's newDescriptor switch). Getter and
  /// zero-arg method of the same name share one group (they render the identical string).
  private static let methodFamily: Set<DeclKind> = [
    .func, .method, .operator, .constructor, .destructor, .getter, .setter, .subscript,
    .protocolMethod,
  ]

  private var indicesByUSR: [String: Int] = [:]
  /// Groups retained for the cache-validation fingerprint (02-02 Task 3): group key → member
  /// USRs in assigned (source) order, groups themselves sorted by key — a deterministic shape.
  private let orderedGroups: [(key: String, usrs: [String])]

  init(definitions: [Definition]) {
    struct Member {
      let usr: String
      let relativePath: String
      let line: Int
      let utf8Column: Int
    }

    var groups: [String: [Member]] = [:]
    for definition in definitions where Self.methodFamily.contains(definition.kind) {
      let key = Self.groupKey(definition)
      groups[key, default: []].append(
        Member(
          usr: definition.usr,
          relativePath: definition.relativePath,
          line: definition.line,
          utf8Column: definition.utf8Column
        ))
    }

    var capturedGroups: [(key: String, usrs: [String])] = []
    capturedGroups.reserveCapacity(groups.count)
    for (key, members) in groups.sorted(by: { $0.key < $1.key }) {
      // D-07 / assumption A1: source order of the definition occurrence — (relativePath,
      // line, utf8Column) — never store order and never USR bytes.
      let ordered = members.sorted {
        if $0.relativePath != $1.relativePath { return $0.relativePath < $1.relativePath }
        if $0.line != $1.line { return $0.line < $1.line }
        return $0.utf8Column < $1.utf8Column
      }
      for (index, member) in ordered.enumerated() {
        indicesByUSR[member.usr] = index
      }
      capturedGroups.append((key, ordered.map(\.usr)))
    }
    orderedGroups = capturedGroups
  }

  /// The overload index for a USR: 0 means no disambiguator (sole overload, or a USR the
  /// pre-pass never saw — non-Method families always take 0).
  func index(forUSR usr: String) -> Int {
    indicesByUSR[usr] ?? 0
  }

  /// Requirement: SYM-03 / D-10 (02-02 Task 3, T-02-04) — a stable fingerprint over the
  /// overload groups for global cache validation: SHA-256 over each group's identity and its
  /// source-ordered member USRs. Any overload change anywhere — including a lone member's
  /// group growing to two, which shifts its `(+0)` to `(+1)` — changes the fingerprint and
  /// wholesale-invalidates cached documents. Single-member groups are deliberately included:
  /// skipping them would hide exactly the 1→2 transition that changes a cached file's symbols
  /// from outside. The granularity is the conservative global shape; a per-group precise
  /// refinement is a recorded v2 follow-up (README).
  func cacheValidationFingerprint() -> String {
    let canonical = orderedGroups
      .map { $0.key + "\u{1}" + $0.usrs.joined(separator: "\u{1}") }
      .joined(separator: "\u{2}")
    return ContentHasher.sha256Hex(of: Data(canonical.utf8))
  }

  private static func groupKey(_ definition: Definition) -> String {
    // The family is part of the group identity implicitly: only Method-family kinds reach
    // the groups (see init). System-vs-target module distinction keeps same-named target and
    // SDK modules from merging.
    [
      definition.module,
      definition.containerNames.joined(separator: "."),
      definition.name,
    ].joined(separator: "\u{0}")
  }
}
