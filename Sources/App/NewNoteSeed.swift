import Foundation

/// Which folder Cmd+N points the new-note composer at, from what the Note pane's tree has
/// selected (n1-seams R-11).
///
/// The tree's ids are vault-relative paths: a folder's own, or a file's, which carries an
/// extension (a note's is `.md`). One selected known folder is the seed itself, one selected
/// file seeds its parent only when that parent is the vault root or a known folder, and
/// anything else - nothing, several rows, an id that is neither a known folder nor a file, a
/// file whose parent is not a known folder - seeds the vault root, `""`.
enum NewNoteSeed {
    static func folder(forSelection selection: Set<String>, knownFolders: Set<String>) -> String {
        guard selection.count == 1, let id = selection.first else { return "" }
        if knownFolders.contains(id) { return id }
        let path = id as NSString
        guard !path.pathExtension.isEmpty else { return "" }
        // The tree selection outlives a vault switch, so a parent must be proved a folder of this
        // vault: an unknown one would have `createNote` build it, intermediate folders and all.
        let parent = path.deletingLastPathComponent
        return parent.isEmpty || knownFolders.contains(parent) ? parent : ""
    }
}
