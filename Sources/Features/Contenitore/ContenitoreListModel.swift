import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D7 and §D11,
// plan docs/plans/contenitore.md, Task 7 - R-13, R-14, R-15, R-19, R-25.
//
// Pure: every input is a value or a closure, so each rule runs in a test with no window and,
// for `containerTree`, no file system.

/// Which documents the pane's left column asks for.
enum ContenitoreScope: Hashable, Sendable {
    /// «Tutti»: every scheda under the root.
    case all
    /// «Da classificare»: the schede carrying `status-inbox` (R-14).
    case inbox
    /// One sub-container, a vault-relative folder path, with every container nested in it.
    case container(String)
}

/// The colour and tag filters above the list (R-15). Empty sets filter nothing.
struct ContenitoreFilter: Equatable, Sendable {
    /// A row passes when it has any of these colours.
    var colours: Set<ContenitoreColour> = []
    /// A row passes when it carries every one of these tags.
    var tags: Set<Tag> = []
    /// The search field: a row passes when its name, original name, a tag or its extracted text
    /// contains the query, ignoring case and accents. Empty filters nothing.
    var query: String = ""
    var sort: ContenitoreSort = .date

    /// Whether a colour or a tag narrows the list, which is what «Azzera filtri» clears.
    var isActive: Bool { !colours.isEmpty || !tags.isEmpty }
}

/// «Ordina»: newest first, or by name.
enum ContenitoreSort: String, CaseIterable, Sendable {
    case date
    case name

    var title: String {
        switch self {
        case .date: "data"
        case .name: "nome"
        }
    }
}

/// One document as the list and the grid draw it (R-13).
struct ContenitoreRow: Identifiable, Equatable, Sendable {
    /// The scheda's vault-relative path, which is also the row's selection tag.
    let schedaPath: String
    /// The scheda's title, which is the pair's stem.
    let name: String
    let date: CalendarDate?
    let colour: ContenitoreColour?
    let tags: [Tag]
    /// `ExtractionSummary.displayLabel` of the document's extraction.
    let extractionLabel: String
    /// The companion file is gone: the row reads «file mancante» (R-25).
    let isFileMissing: Bool
    /// The companion's vault-relative path, what `ThumbnailStore` and Quick Look read. Nil
    /// when the scheda names no file.
    let filePath: String?
    /// The sub-container the pair sits in, vault-relative, the root itself for a document
    /// at `<root>/YYYY/`.
    let container: String
    let originalName: String
    /// The document's hash, the key of its extraction and of the queue's progress (R-09).
    let sha256: String?

    var id: String { schedaPath }
    var isInbox: Bool { tags.contains(ContenitoreListModel.inboxTag) }
    /// The companion's extension, uppercased, as the row's subtitle shows it («PDF»).
    var kind: String {
        guard let filePath else { return "" }
        return (filePath as NSString).pathExtension.uppercased()
    }
}

/// A sub-container in the pane's tree: a folder under the root that is not a year folder.
struct ContainerNode: Identifiable, Equatable, Sendable {
    /// The vault-relative folder path, which is also the tree row's selection tag.
    let path: String
    let name: String
    /// 0 for a folder directly under the root.
    let depth: Int
    var children: [ContainerNode]

    var id: String { path }
}

/// Derives what the pane draws from the index (ADR-0071 §D11).
enum ContenitoreListModel {
    static let inboxTag = Tag(namespace: .status, value: "inbox")

    /// Every scheda under `root` that `scope` and `filter` let through, newest first, then by
    /// name. `fileExists` answers for a vault-relative path; `status` and `text` for a SHA-256,
    /// the first for every row's label, the second only for a row a search query did not
    /// already match by name or tag, so listing never needs an extracted text.
    static func rows(
        index: IndexSnapshot,
        root: String,
        filter: ContenitoreFilter = ContenitoreFilter(),
        container scope: ContenitoreScope = .all,
        fileExists: (String) -> Bool,
        status: (String) -> ExtractionSummary?,
        text: (String) -> String?
    ) -> [ContenitoreRow] {
        let rootPath = trimmed(root)
        let query = filter.query.trimmingCharacters(in: .whitespaces)
        let rows = index.schede(underRoot: rootPath).compactMap { record -> ContenitoreRow? in
            guard let row = row(for: record, root: rootPath, fileExists: fileExists, status: status),
                  matches(row, scope: scope), matches(row, filter: filter)
            else { return nil }
            guard query.isEmpty || matches(row, query: query, sha256: record.contenitore?.sha256, text: text)
            else { return nil }
            return row
        }
        switch filter.sort {
        case .date: return rows.sorted(by: newestFirst)
        case .name: return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// The row for one scheda, or nil when the record carries no scheda facts.
    static func row(
        for record: NoteRecord,
        root: String,
        fileExists: (String) -> Bool,
        status: (String) -> ExtractionSummary?
    ) -> ContenitoreRow? {
        guard let facts = record.contenitore else { return nil }
        let folder = (record.relativePath as NSString).deletingLastPathComponent
        // The same rule `VaultSession.companion(ofScheda:)` applies, so a row reads «file mancante»
        // exactly when «Apri» is disabled: a scheda renamed alone in the Finder owns no file.
        let filePath = ContenitoreScheda.companionPath(ofSchedaAt: record.relativePath, fileName: facts.fileName)
        return ContenitoreRow(
            schedaPath: record.relativePath,
            name: record.title,
            date: record.frontmatter.date,
            colour: facts.colour,
            tags: record.frontmatter.tags,
            extractionLabel: ExtractionSummary.displayLabel(facts.sha256.flatMap(status)),
            isFileMissing: filePath.map { !fileExists($0) } ?? true,
            filePath: filePath,
            container: container(ofFolder: folder, root: root),
            originalName: facts.originalName,
            sha256: facts.sha256
        )
    }

    /// How many schede under `root` still carry `status-inbox` (R-14).
    static func inboxCount(index: IndexSnapshot, root: String) -> Int {
        index.schede(underRoot: trimmed(root)).count { $0.frontmatter.tags.contains(inboxTag) }
    }

    /// The sub-container tree under `root`, built from `folders` (vault-relative paths, in any
    /// order, ancestors optional). Year folders are not nodes, and nothing under a year folder
    /// is either: that is where documents live, never containers (ADR-0071 §D7).
    static func containerTree(root: String, folders: [String]) -> [ContainerNode] {
        let rootPath = trimmed(root)
        guard !rootPath.isEmpty else { return [] }
        let prefix = rootPath + "/"

        var paths = Set<String>()
        for folder in folders.map(trimmed) where folder.hasPrefix(prefix) {
            let components = folder.dropFirst(prefix.count).split(separator: "/").map(String.init)
            var current = rootPath
            for component in components {
                guard !ContenitoreNaming.isYearFolderName(component), !component.hasPrefix(".") else { break }
                current += "/" + component
                paths.insert(current)
            }
        }
        return children(of: rootPath, depth: 0, in: paths)
    }

    /// The tree as the flat rows ADR-0024 asks for: a node, then its children when it is
    /// expanded, depth first.
    static func flattened(_ nodes: [ContainerNode], expanded: Set<String>) -> [ContainerNode] {
        nodes.flatMap { node in
            [node] + (expanded.contains(node.path) ? flattened(node.children, expanded: expanded) : [])
        }
    }

    /// Every container path in the tree, depth first, for «Sposta in…».
    static func allPaths(_ nodes: [ContainerNode]) -> [ContainerNode] {
        nodes.flatMap { [$0] + allPaths($0.children) }
    }

    /// How many of `rows` sit in `container` or below it.
    static func count(of rows: [ContenitoreRow], in container: String) -> Int {
        rows.count { isInside($0.container, container) }
    }

    /// `folder` with a trailing year folder dropped: the container a document in it belongs to.
    static func container(ofFolder folder: String, root: String) -> String {
        let components = folder.split(separator: "/").map(String.init)
        guard let last = components.last, ContenitoreNaming.isYearFolderName(last) else {
            return folder.isEmpty ? root : folder
        }
        let parent = components.dropLast().joined(separator: "/")
        return parent.isEmpty ? root : parent
    }

    /// The container path shown as a breadcrumb under the root: `Amministrazione › Fatture`,
    /// empty for the root itself.
    static func breadcrumb(of container: String, root: String) -> String {
        let prefix = trimmed(root) + "/"
        guard container.hasPrefix(prefix) else { return "" }
        return container.dropFirst(prefix.count).split(separator: "/").joined(separator: " › ")
    }

    // MARK: - Pieces

    private static func matches(_ row: ContenitoreRow, scope: ContenitoreScope) -> Bool {
        switch scope {
        case .all: true
        case .inbox: row.isInbox
        case .container(let path): isInside(row.container, path)
        }
    }

    private static func matches(_ row: ContenitoreRow, filter: ContenitoreFilter) -> Bool {
        if !filter.colours.isEmpty {
            guard let colour = row.colour, filter.colours.contains(colour) else { return false }
        }
        return filter.tags.isSubset(of: Set(row.tags))
    }

    private static func matches(
        _ row: ContenitoreRow, query: String, sha256: String?, text: (String) -> String?
    ) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let fields = [row.name, row.originalName] + row.tags.map(\.description)
        if fields.contains(where: { $0.range(of: query, options: options) != nil }) { return true }
        guard let sha256, let text = text(sha256) else { return false }
        return text.range(of: query, options: options) != nil
    }

    private static func isInside(_ container: String, _ ancestor: String) -> Bool {
        container == ancestor || container.hasPrefix(ancestor + "/")
    }

    private static func newestFirst(_ lhs: ContenitoreRow, _ rhs: ContenitoreRow) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right: left > right
        case (.some, .none): true
        case (.none, .some): false
        default: lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func children(of parent: String, depth: Int, in paths: Set<String>) -> [ContainerNode] {
        paths
            .filter { ($0 as NSString).deletingLastPathComponent == parent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { path in
                ContainerNode(
                    path: path,
                    name: (path as NSString).lastPathComponent,
                    depth: depth,
                    children: children(of: path, depth: depth + 1, in: paths)
                )
            }
    }

    private static func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
    }
}
