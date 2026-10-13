import SwiftUI

/// `RootView.body`'s sheet modifiers - the help sheets (SPEC §10's Aiuto entries) and the
/// task/category pickers, six `.sheet` calls with nothing else in common (PG-035 - pure
/// code motion off `RootView.swift`, which crossed `file_length` the moment
/// `CategoryEditor`'s sheet, ADR-0047 §D6, was added to it).
///
/// Each picker is hosted here rather than by the view that opens it because more than
/// one surface reaches every one of them: `TaskCommand.linkBoard`/`.assignCategory` fire
/// from the row's context menu, the Attività toolbar, the Task menu and the "Task
/// collegati" panel alike (ADR-0039 §D3), and `CategorySidebarSection`'s "+" and a row's
/// "Modifica…" both open the same editor (ADR-0047 §D6).
extension RootView {
    func withSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: Bindable(navigation).isShowingTaskSyntaxHelp) {
                HelpSheet(topic: .taskSyntax) { navigation.isShowingTaskSyntaxHelp = false }
            }
            .sheet(isPresented: Bindable(navigation).isShowingConventionsHelp) {
                HelpSheet(topic: .conventions) { navigation.isShowingConventionsHelp = false }
            }
            .sheet(isPresented: Bindable(navigation).isShowingDiaryHelp) {
                HelpSheet(topic: .diary) { navigation.isShowingDiaryHelp = false }
            }
            .sheet(item: Bindable(navigation).taskPickingBoard) { task in
                WorkspacePicker(task: task) { navigation.taskPickingBoard = nil }
            }
            .sheet(item: Bindable(navigation).taskPickingCategory) { task in
                CategoryPicker(task: task) { navigation.taskPickingCategory = nil }
            }
            .sheet(item: Bindable(navigation).categoryEditorTarget) { target in
                CategoryEditor(target: target) { navigation.categoryEditorTarget = nil }
            }
            .sheet(item: Bindable(navigation).categoryLinkingNote) { request in
                CategoryNotePicker(request: request) { navigation.categoryLinkingNote = nil }
            }
            // A shared or dangling title followed from somewhere with no click point (ADR-0083 §D5).
            .sheet(item: Bindable(navigation).linkChoice) { request in
                LinkChoiceSheet(request: request) { navigation.linkChoice = nil }
            }
            // «Classifica…» on a note or, from «Da classificare», on a scheda (ADR-0085 §D5). The
            // Contenitore keeps presenting its own from `contenitore.classifying` (ADR-0071 §D12).
            .sheet(item: Bindable(navigation).classifying) { subject in
                ClassificaSheet(subject: subject)
            }
            .sheet(item: Bindable(navigation).praticaLinkRequest) { request in
                PraticaLinkPicker(
                    request: request,
                    actions: PraticaCommandActions(pratiche: pratiche, vault: vault, navigation: navigation)
                ) { navigation.praticaLinkRequest = nil }
            }
    }
}
