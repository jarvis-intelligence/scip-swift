import Foundation
import IndexStoreDB

/// Resolve identities before emitting documents, including reference-only and relation-only
/// symbols, so every compiler USR renders one string at definitions, references,
/// relationships and enclosing symbols alike.
///
/// Colliding private declarations are already apart via `PrivateContextTable`. Any canonical
/// collision that remains gains a short discriminator on the colliding descriptor's own name.
///
/// Raw-USR fallback symbols keep location-based attribution (the referencing document's module
/// header), except when the USR is defined in this index: then every occurrence uses the
/// defining document's spelling, so references resolve to the definition.
struct SymbolIdentityTable {
  struct Candidate {
    let usr: String
    let canonical: String
    let fallback: String
    /// True when this candidate comes from a definition occurrence of `usr`.
    var isDefinition = false
  }

  let symbolsByUSR: [String: String]
  let fallbackUSRs: Set<String>

  init(candidates: [Candidate]) {
    var canonicalByUSR: [String: String] = [:]
    var fallbackOnly: [String: (defined: String?, seen: Bool)] = [:]
    for candidate in candidates {
      if candidate.canonical == candidate.fallback {
        // Unparsed USR: unify only on an in-index definition (deterministic if several).
        var entry = fallbackOnly[candidate.usr] ?? (nil, true)
        if candidate.isDefinition {
          entry.defined = min(entry.defined ?? candidate.fallback, candidate.fallback)
        }
        fallbackOnly[candidate.usr] = entry
      } else {
        // Normalize header variants (system vs. target location) of one parsed identity.
        canonicalByUSR[candidate.usr] = min(
          canonicalByUSR[candidate.usr] ?? candidate.canonical, candidate.canonical)
      }
    }
    var fallbacks: Set<String> = []
    for (usr, entry) in fallbackOnly where canonicalByUSR[usr] == nil {
      guard let defined = entry.defined else { continue }  // external: location-based
      canonicalByUSR[usr] = defined
      fallbacks.insert(usr)
    }

    var groups: [String: [String]] = [:]
    for (usr, canonical) in canonicalByUSR { groups[canonical, default: []].append(usr) }
    var symbols = canonicalByUSR
    var reserved = Set(canonicalByUSR.values)
    for (canonical, usrs) in groups.sorted(by: { $0.key < $1.key }) where usrs.count > 1 {
      for usr in usrs.sorted() {
        let digest = ContentHasher.sha256Hex(of: Data(usr.utf8))
        let discriminator = String((Self.privateDiscriminator(in: usr) ?? digest).prefix(8))
        var resolved = Self.renamingLastDescriptor(of: canonical, suffix: "@" + discriminator)
        // Distinct declarations can share a discriminator prefix. Check generated spellings
        // against each other AND existing canonical symbols.
        var ordinal = 1
        while reserved.contains(resolved) {
          resolved = Self.renamingLastDescriptor(
            of: canonical, suffix: "@\(discriminator)_\(ordinal)")
          ordinal += 1
        }
        symbols[usr] = resolved
        reserved.insert(resolved)
      }
    }
    symbolsByUSR = symbols
    fallbackUSRs = fallbacks
  }

  private static func privateDiscriminator(in usr: String) -> String? {
    guard let range = usr.range(of: "_[0-9A-Fa-f]{32}LL", options: .regularExpression) else {
      return nil
    }
    return String(usr[range].dropFirst().dropLast(2))
  }

  /// Appends `suffix` to the name of the symbol's last descriptor, keeping its kind suffix
  /// (`#`, `.`, `(…).`, `/`, `!`, `[…]`, `(…)`).
  static func renamingLastDescriptor(of symbol: String, suffix: String) -> String {
    var body = Substring(symbol)
    var kindSuffix = ""
    for marker in ["#", "/", "!"] where body.hasSuffix(marker) {
      kindSuffix = marker
    }
    if kindSuffix.isEmpty, body.hasSuffix(")."), let open = body.lastIndex(of: "(") {
      kindSuffix = String(body[open...])
    } else if kindSuffix.isEmpty, body.hasSuffix(".") {
      kindSuffix = "."
    }
    body = body.dropLast(kindSuffix.count)

    // The name is either backtick-escaped (with doubled inner backticks) or a run of
    // identifier characters.
    var name: String
    if body.hasSuffix("`") {
      // Walk left from the closing backtick. Inner backticks come in doubled runs; the first
      // odd-length run holds the opening delimiter at its left end.
      var index = body.index(before: body.endIndex)
      var opening = body.startIndex
      while index > body.startIndex {
        index = body.index(before: index)
        guard body[index] == "`" else { continue }
        var runStart = index
        while runStart > body.startIndex, body[body.index(before: runStart)] == "`" {
          runStart = body.index(before: runStart)
        }
        if body.distance(from: runStart, to: index) % 2 == 0 {  // odd run length
          opening = runStart
          break
        }
        index = runStart
      }
      let escaped = body[opening...].dropFirst().dropLast()
      name = escaped.replacingOccurrences(of: "``", with: "`")
      body = body[..<opening]
    } else {
      var start = body.endIndex
      while start > body.startIndex,
        CanonicalSymbolFormatter.isIdentifierCharacter(body[body.index(before: start)])
      {
        start = body.index(before: start)
      }
      name = String(body[start...])
      body = body[..<start]
    }
    name += suffix
    return String(body) + CanonicalSymbolFormatter.escapeIdentifierName(name) + kindSuffix
  }

  func cacheValidationFingerprint() -> String {
    let entries = symbolsByUSR.sorted { $0.key < $1.key }
      .map { $0.key + "\u{0}" + $0.value }.joined(separator: "\u{1}")
    return ContentHasher.sha256Hex(of: Data(entries.utf8))
  }
}

extension SCIPIndexBuilder {
  func buildPrivateContextTable(indexStoreDB: IndexStoreDB) -> PrivateContextTable {
    var parsed: [String: USRSymbolParser.ParsedUSR] = [:]
    for path in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      for occurrence in indexStoreDB.symbolOccurrences(inFilePath: path) {
        for symbol in [occurrence.symbol] + occurrence.relations.map(\.symbol)
        where !symbol.properties.contains(.local) && parsed[symbol.usr] == nil {
          guard var usr = USRSymbolParser.parse(symbol.usr) else { continue }
          // After an initializer's type comes its first argument label, not a declared name;
          // its parameters (no canonical kind) carry the same word. Keep only their context.
          let kind = USRSymbolMapper.declKind(for: symbol)
          if kind == nil || kind == .constructor || kind == .destructor {
            usr = PrivateContextTable.contextOnly(usr)
          }
          parsed[symbol.usr] = usr
        }
      }
    }
    return PrivateContextTable(parsed: parsed.values.map { $0 })
  }

  func buildIdentityTable(indexStoreDB: IndexStoreDB, overloadTable: OverloadTable) -> SymbolIdentityTable {
    var candidates: [SymbolIdentityTable.Candidate] = []
    for path in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      for occurrence in indexStoreDB.symbolOccurrences(inFilePath: path) {
        for symbol in [occurrence.symbol] + occurrence.relations.map(\.symbol)
        where !symbol.properties.contains(.local) {
          let isSystem = Self.effectiveIsSystemLocation(
            for: symbol, storeReported: occurrence.location.isSystem, packageTargets: packageTargets)
          let canonical = canonicalSymbolString(
            for: symbol,
            isSystemLocation: isSystem,
            locationModuleName: occurrence.location.moduleName,
            overloadIndex: overloadTable.index(forUSR: symbol.usr),
            privateContexts: overloadTable.privateContexts,
            recordsFallback: false
          )
          let fallback = SCIPSymbolFormatter.fallbackSymbolString(
            isSystem: isSystem,
            moduleName: occurrence.location.moduleName,
            toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
            usr: symbol.usr
          )
          candidates.append(.init(
            usr: symbol.usr, canonical: canonical, fallback: fallback,
            isDefinition: symbol.usr == occurrence.symbol.usr
              && occurrence.roles.contains(.definition)))
        }
      }
    }
    return SymbolIdentityTable(candidates: candidates)
  }
}
