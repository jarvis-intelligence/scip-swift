import Foundation

/// Disambiguates `private`/`fileprivate` declarations whose canonical spelling another
/// declaration shares: two files that each declare `private struct Marker`, or a file-private
/// `logger` in several files.
///
/// The compiler keeps them apart with a per-file discriminator (`33_<hex>LL` in the USR). When
/// the same spelling path (module, header, ancestors, name) is declared with more than one
/// discriminator — or once privately and once without one — each private declaration's own
/// descriptor name gains `@<hex prefix>`. The renamed node is applied to every USR that passes
/// through it, so a disambiguated type's properties, accessors, initializers and methods all
/// live under that type's own disambiguated descriptor. `@` cannot occur in a Swift
/// identifier, so a renamed spelling never equals a source name. Non-colliding private
/// declarations keep their readable names.
struct PrivateContextTable {
  private struct Node {
    let name: String
    let discriminator: String?
  }

  /// Raw node path (discriminators included) → rendered descriptor name.
  private let renamedNames: [String: String]

  init(parsed: [USRSymbolParser.ParsedUSR]) {
    // Every distinct node path, keyed by its raw identity.
    var paths: [String: (parentKey: String?, depth: Int, node: Node, root: String)] = [:]
    for usr in parsed {
      let root = Self.rootKey(usr)
      var parentKey: String? = nil
      for (depth, node) in Self.nodes(of: usr).enumerated() {
        let key = Self.rawKey(parent: parentKey ?? root, node: node)
        if paths[key] == nil {
          paths[key] = (parentKey, depth, node, root)
        }
        parentKey = key
      }
    }

    // Resolve depth by depth, so a node's group uses its ancestors' rendered names.
    var rendered: [String: String] = [:]  // raw key → rendered path key
    var renamed: [String: String] = [:]
    let byDepth = Dictionary(grouping: paths.keys, by: { paths[$0]!.depth })
    for depth in byDepth.keys.sorted() {
      var groups: [String: [String]] = [:]  // rendered parent + name → raw keys
      for key in byDepth[depth]! {
        let entry = paths[key]!
        let parent = entry.parentKey.flatMap { rendered[$0] } ?? entry.root
        groups[parent + "\u{2}" + entry.node.name, default: []].append(key)
      }
      for (groupKey, keys) in groups {
        let discriminators = Set(keys.map { paths[$0]!.node.discriminator ?? "" })
        let privates = discriminators.filter { !$0.isEmpty }.sorted()
        let length = discriminators.count > 1 ? Self.uniquePrefixLength(privates) : 0
        let parent = String(groupKey[..<groupKey.lastIndex(of: "\u{2}")!])
        for key in keys {
          let node = paths[key]!.node
          var name = node.name
          if length > 0, let discriminator = node.discriminator {
            name += "@" + discriminator.prefix(length)
            renamed[key] = name
          }
          rendered[key] = parent + "\u{2}" + name
        }
      }
    }
    renamedNames = renamed
  }

  /// Returns the parse with every colliding private node renamed.
  func apply(_ usr: USRSymbolParser.ParsedUSR) -> USRSymbolParser.ParsedUSR {
    guard !renamedNames.isEmpty else { return usr }
    var key = Self.rootKey(usr)
    var containers: [CanonicalSymbolFormatter.Container] = []
    for container in usr.containers {
      key = Self.rawKey(parent: key, node: Node(
        name: container.name, discriminator: container.privateDiscriminator))
      containers.append(CanonicalSymbolFormatter.Container(
        name: renamedNames[key] ?? container.name, kind: container.kind,
        privateDiscriminator: container.privateDiscriminator))
    }
    var name = usr.name
    if !usr.name.isEmpty {
      key = Self.rawKey(parent: key, node: Node(
        name: usr.name, discriminator: usr.privateDiscriminator))
      name = renamedNames[key] ?? usr.name
    }
    return USRSymbolParser.ParsedUSR(
      module: usr.module, isSystemModule: usr.isSystemModule, containers: containers,
      name: name, extendingModule: usr.extendingModule, isOperator: usr.isOperator,
      privateDiscriminator: usr.privateDiscriminator)
  }

  /// The parse with its entity name removed, keeping only its containers as nodes.
  static func contextOnly(_ usr: USRSymbolParser.ParsedUSR) -> USRSymbolParser.ParsedUSR {
    USRSymbolParser.ParsedUSR(
      module: usr.module, isSystemModule: usr.isSystemModule, containers: usr.containers,
      name: "", extendingModule: usr.extendingModule, isOperator: usr.isOperator)
  }

  private static func nodes(of usr: USRSymbolParser.ParsedUSR) -> [Node] {
    var nodes = usr.containers.map {
      Node(name: $0.name, discriminator: $0.privateDiscriminator)
    }
    if !usr.name.isEmpty {
      nodes.append(Node(name: usr.name, discriminator: usr.privateDiscriminator))
    }
    return nodes
  }

  private static func rootKey(_ usr: USRSymbolParser.ParsedUSR) -> String {
    (usr.isSystemModule ? "swift\u{0}" : "swiftpm\u{0}") + usr.module
  }

  private static func rawKey(parent: String, node: Node) -> String {
    parent + "\u{2}" + node.name + "\u{1}" + (node.discriminator ?? "")
  }

  /// The shortest prefix (at least 8) that keeps every discriminator in the group distinct.
  private static func uniquePrefixLength(_ discriminators: [String]) -> Int {
    var length = 8
    while length < 32, Set(discriminators.map { $0.prefix(length) }).count < discriminators.count {
      length += 1
    }
    return length
  }
}
