import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D4 and §D11, plan
// docs/plans/contenitore.md, Task 7 - R-05, R-07, R-08, R-11, R-26; mockup 1e and 1h.

extension ContenitoreNotice {
    /// The sentence the strip shows, naming the file.
    var sentence: String {
        switch self {
        case .duplicate(let file, let existing):
            let title = NoteName.title(fromFileName: (existing as NSString).lastPathComponent)
            return "«\(file)» è già nel Contenitore come «\(title)»: resta nella cartella di raccolta."
        case .failed(let file, let reason):
            return "«\(file)» non importato: \(reason)."
        case .placeholder(let file):
            return "«\(file)» è solo in iCloud: scaricalo nel Finder e verrà importato."
        case .subfolder(let name):
            return "«\(name)» è una cartella: il Contenitore non entra nelle cartelle della cartella di raccolta."
        case .unreadableDropFolder:
            return "La cartella di raccolta non si può leggere. Nessun file viene importato finché non concedi l'accesso."
        case .refusedNote(let file):
            return "«\(file)» non importato: note e board non entrano nel Contenitore."
        case .extractionFailed(let file):
            return "Estrazione del testo non riuscita per «\(file)». Il documento resta cercabile per nome, descrizione e tag."
        }
    }

    /// The SF Symbol beside the sentence: a cloud for a placeholder, a warning otherwise.
    var symbol: String {
        switch self {
        case .placeholder: "icloud.and.arrow.down"
        case .duplicate, .subfolder, .refusedNote: "info.circle"
        case .failed, .unreadableDropFolder, .extractionFailed: "exclamationmark.triangle"
        }
    }
}

/// The notices, above the list; each stays until closed (mockup 1e).
struct ContenitoreNoticeStrip: View {
    @Environment(\.theme) private var theme
    @Environment(ContenitoreController.self) private var contenitore
    let actions: ContenitoreCommandActions

    var body: some View {
        if !contenitore.notices.isEmpty || contenitore.dropFolderRefusal != nil {
            VStack(spacing: theme.spacing(.xs)) {
                if let refusal = contenitore.dropFolderRefusal {
                    line(symbol: "exclamationmark.triangle", text: "Cartella di raccolta non valida: \(refusal.sentence)") {
                        SettingsLink { Text("Impostazioni…") }
                    }
                }
                ForEach(Array(contenitore.notices.enumerated()), id: \.offset) { _, notice in
                    line(symbol: notice.symbol, text: notice.sentence) {
                        trailing(for: notice)
                        Button {
                            contenitore.dismiss(notice)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Chiudi")
                        .accessibilityLabel("Chiudi")
                    }
                }
            }
            .padding(.horizontal, theme.spacing(.l))
            .padding(.bottom, theme.spacing(.s))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("contenitore-notices")
        }
    }

    @ViewBuilder
    private func trailing(for notice: ContenitoreNotice) -> some View {
        switch notice {
        case .duplicate(_, let existing):
            Button("Mostra") {
                contenitore.scope = .all
                contenitore.filter = ContenitoreFilter()
                contenitore.selection = existing
            }
            .buttonStyle(.link)
        case .failed:
            Button("Riprova") { Task { await contenitore.retryImports(after: notice) } }
                .buttonStyle(.link)
        case .extractionFailed(let file):
            Button("Riprova") { contenitore.retryExtraction(of: file) }
                .buttonStyle(.link)
        case .unreadableDropFolder:
            SettingsLink { Text("Impostazioni…") }
                .buttonStyle(.link)
        case .placeholder, .subfolder, .refusedNote:
            EmptyView()
        }
    }

    private func line(
        symbol: String, text: String, @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
            Image(systemName: symbol).foregroundStyle(theme.color(.textSecondary))
            Text(text)
                .themedText(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.surfaceSunken), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
    }
}
