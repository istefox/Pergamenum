import Foundation

// PG-387 (N4), ADR-0085 §D6/§D8, plan docs/plans/pg-387-n4-birth-of-note.md, Tasks 5 and 7:
// the two verbs the note's birth adds to the catalogue, reachable from `runFile` and `runEdit` so
// neither falls into its `assertionFailure` default (an assertion traps the Debug test host).
extension CommandActions {
    func runNoteBirth(_ command: ShortcutCommand) {
        switch command {
        case .classifyNote:
            runClassify()
        case .extractToNote:
            // The sheet rides on the Note pane's browser (`NoteBirthPresentation`), and the
            // selection it extracts is the focused tab's, which is only reported there.
            guard canRun(.extractToNote) else { return }
            _ = vault.beginExtraction()
        default:
            break
        }
    }

    /// Whether «Classifica…» has a subject: the selected row of «Da classificare» when that pane
    /// is in front, the Contenitore's selection when that one is, otherwise the open note.
    var canClassify: Bool {
        switch navigation.pane {
        case .unfiled:
            return navigation.unfiledSelection.map { vault.session?.exists($0) == true } ?? false
        case .contenitore:
            guard let actions = contenitoreActions, let selection = actions.contenitore.selection else { return false }
            return actions.canRun(.classify, on: selection)
        default:
            return vault.openNote != nil
        }
    }

    /// «Estrai in una nota»: the Note pane in front and a non-empty selection in its focused tab.
    var canExtract: Bool {
        navigation.pane == .notes && vault.focusedTab?.selection != nil
    }

    /// The sheet's subject for a note of the vault: a Contenitore scheda gets the scheda form,
    /// which has no folder field (SPEC edge case), anything else the note form.
    func classifySubject(for path: String) -> ClassificaSheet.Subject {
        vault.index.notes[path]?.contenitore != nil ? .scheda(path) : .note(path)
    }

    private func runClassify() {
        switch navigation.pane {
        case .unfiled:
            guard let path = navigation.unfiledSelection, canClassify else { return }
            navigation.classifying = classifySubject(for: path)
        case .contenitore:
            // ADR-0071 §D12: the pane's own sheet, presented from `contenitore.classifying`.
            if let actions = contenitoreActions, let selection = actions.contenitore.selection {
                actions.run(.classify, on: selection)
            }
        default:
            guard let path = vault.openNote?.relativePath else { return }
            navigation.classifying = classifySubject(for: path)
        }
    }
}
