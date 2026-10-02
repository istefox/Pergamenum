import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11, plan
// docs/plans/contenitore.md, Task 7 - R-16; ADR-0073 (a holder of unsaved state reviews itself
// in `QuitCoordinator`), ADR-0068 §D16 (the inspector reloads on a landed generation).
//
// Its own file because `ContenitoreController`'s body sits at SwiftLint's `type_body_length`.

extension ContenitoreController {
    /// What the inspector's `.task(id:)` reloads on: the selected scheda, its own landed
    /// generation (a write this app made, «Classifica…» included: ADR-0067 §D6) and the index
    /// generation (the watcher's report of an external edit, which advances no landed
    /// generation). Reloading is cheap and guarded - `ContenitoreEditor.refreshFromDisk()` does
    /// nothing when the file is what it already holds - so the wider key costs a read, not a
    /// write.
    struct InspectorKey: Hashable {
        var schedaPath: String
        var landed: UInt64
        var index: Int
    }

    func inspectorKey(for schedaPath: String) -> InspectorKey {
        InspectorKey(
            schedaPath: schedaPath,
            landed: vault.session?.landedGeneration(at: schedaPath) ?? 0,
            index: vault.indexGeneration
        )
    }

    /// True while an inspector edit is not on disk yet: what `QuitCoordinator` asks (ADR-0073).
    var hasUnsettledEdits: Bool {
        !(editor?.isSettled ?? true) || retiredEditors.contains { !$0.isSettled }
    }

    /// The scheda of the first editor still owing a write, the current one first: what a
    /// cancelled quit brings back on screen (ADR-0073 §D7).
    var firstUnsettledSchedaPath: String? {
        ([editor].compactMap { $0 } + retiredEditors).first { !$0.isSettled }?.schedaPath
    }

    /// The schede, current editor first, whose edit is owed but can never be written because
    /// the scheda is no longer at its path (PG-341). What the quit review names, so its «Non
    /// salvare» can let the app go instead of every Cmd+Q being cancelled by a write that cannot
    /// land. An edit to a scheda still there is not here: it is written in the quit's diary
    /// phase, as before, and only a write that then fails cancels the quit.
    var vanishedSchedaEdits: [String] {
        var paths: [String] = []
        for owed in [editor].compactMap({ $0 }) + retiredEditors
        where !owed.isSettled && owed.isSchedaGone && !paths.contains(owed.schedaPath) {
            paths.append(owed.schedaPath)
        }
        return paths
    }

    /// The quit's «Non salvare» over the schede it named (PG-341): their edits are dropped and a
    /// retired editor left with nothing to write is let go.
    func discardEdits(at schedaPaths: [String]) {
        for owed in [editor].compactMap({ $0 }) + retiredEditors where schedaPaths.contains(owed.schedaPath) {
            owed.discard()
        }
        retiredEditors.removeAll { $0.isSettled }
    }

    /// Makes the editor the inspector binds to the one for `schedaPath`: a new one reading the
    /// scheda, or the current one taking whatever landed on the disk since. The editor it
    /// replaces is retired, not dropped.
    func openEditor(for schedaPath: String) {
        guard let session = vault.session else { return }
        if let editor, editor.schedaPath == schedaPath {
            editor.refreshFromDisk()
            return
        }
        retireEditor()
        // An editor handed off with a write still owed (one whose save failed) comes back
        // rather than being read afresh over its draft.
        if let index = retiredEditors.firstIndex(where: { $0.schedaPath == schedaPath && !$0.isSettled }) {
            editor = retiredEditors.remove(at: index)
            editor?.refreshFromDisk()
            return
        }
        editor = ContenitoreEditor(session: session, schedaPath: schedaPath)
    }

    /// Writes every edit not on disk yet and returns when it has landed, for what must not
    /// leave one behind: the quit, a vault switch, and a verb that rewrites the scheda.
    func settleEditing() async {
        if let editor { await editor.settle() }
        for retired in retiredEditors { await retired.settle() }
        retiredEditors.removeAll { $0.isSettled }
    }

    /// `selection` moved: an editor for another scheda goes on saving in the background.
    func selectionChanged() {
        if editor?.schedaPath != selection { retireEditor() }
    }

    /// What a vault change (`releaseSession()`) says about an inspector edit it could not write.
    static func lostEditSentence(for schedaPath: String) -> String {
        let name = ((schedaPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return "Modifica alla scheda «\(name)» non salvata: il vault è cambiato prima che si potesse scrivere."
    }

    /// Lets go of the current editor. One with something to write is kept in `retiredEditors`
    /// and settled in a task the quit can also wait on; a settled one is simply dropped.
    private func retireEditor() {
        guard let old = editor else { return }
        editor = nil
        guard !old.isSettled else { return }
        retiredEditors.append(old)
        Task {
            await old.settle()
            // Only a settled one goes: a write that failed leaves the draft owed, and it must stay
            // where `openEditor(for:)` can adopt it and the quit can see it. `$0 === old` also
            // keeps this from touching an editor that was re-adopted and retired again.
            retiredEditors.removeAll { $0 === old && $0.isSettled }
        }
    }

    /// The scheda of an editor with an edit still owed on `schedaPath` itself, or nil. What a
    /// verb that rewrites or moves the scheda asks after `settleEditing()`: a write that failed
    /// leaves it owed, and the pair must not move from under it.
    func unsettledScheda(at schedaPath: String) -> String? {
        ([editor].compactMap { $0 } + retiredEditors).first { !$0.isSettled && $0.schedaPath == schedaPath }?.schedaPath
    }

    /// The first scheda of an editor with an edit still owed inside `container` (the folder
    /// itself excluded from being a scheda path, anything below it counting), or nil.
    func unsettledScheda(inside container: String) -> String? {
        ([editor].compactMap { $0 } + retiredEditors).first {
            !$0.isSettled && $0.schedaPath.hasPrefix(container + "/")
        }?.schedaPath
    }
}
