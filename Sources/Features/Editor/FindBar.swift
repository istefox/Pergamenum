import AppKit
import SwiftUI

/// Trova e sostituisci inside one note (SPEC §10, M8), as the approved mockup drew it.
///
/// `FindBarMockup` in the design gallery is the reference and stays there: this draws the
/// same seven states from the same tokens, and the mockup is what was approved rather than
/// a picture of it.
///
/// It sits under the editor header and above the text, in the slot the conflict banner
/// occupies, and pushes the note down rather than floating over it - a bar that overlays
/// hides the note's first line, which is exactly where a search that has just wrapped round
/// is most likely to have landed.
struct FindBar: View {
    @Environment(\.theme) private var theme

    let session: FindSession
    let onStep: (Int) -> Void
    let onReplaceOne: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: theme.spacing(.xs)) {
            findRow(session: $session)
            if session.showsReplace { replaceRow(session: $session) }
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .accessibilityIdentifier("find-bar")
    }

    private func findRow(session: Bindable<FindSession>) -> some View {
        HStack(spacing: theme.spacing(.s)) {
            FindField(
                text: session.query,
                placeholder: "Trova",
                identifier: "find-query",
                isMonospaced: self.session.isRegex,
                focusRequest: self.session.focusRequest,
                onSubmit: { onStep(1) },
                onSubmitBackwards: { onStep(-1) },
                onCancel: onClose,
                trailing: AnyView(tally)
            )
            option(".*", isOn: session.isRegex, help: "Espressione regolare")
            option("Aa", isOn: session.isCaseSensitive, help: "Distingui maiuscole e minuscole")
            scope
            stepper
            Button("Fine", action: onClose)
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
                .accessibilityIdentifier("find-done")
        }
    }

    private func replaceRow(session: Bindable<FindSession>) -> some View {
        HStack(spacing: theme.spacing(.s)) {
            FindField(
                text: session.replacement,
                placeholder: "Sostituisci",
                identifier: "find-replacement",
                isMonospaced: self.session.isRegex,
                focusRequest: 0,
                onSubmit: onReplaceOne,
                onSubmitBackwards: nil,
                onCancel: onClose,
                trailing: nil
            )
            Button("Sostituisci", action: onReplaceOne)
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
                .disabled(self.session.currentMatch == nil)
                .accessibilityIdentifier("find-replace-one")
            Button("Tutti", action: onReplaceAll)
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
                .disabled(self.session.matches.isEmpty)
                .accessibilityIdentifier("find-replace-all")
            // Balances the find row's stepper and «Fine», so the two fields keep the same
            // width: a replace field narrower than the find field above it reads as a
            // different control rather than as the other half of one.
            Color.clear.frame(width: 96, height: 1)
        }
    }

    /// The count lives inside the field, at its trailing edge, and not beside it. Outside, it
    /// moves every time the number gains a digit and drags the buttons along with it.
    @ViewBuilder
    private var tally: some View {
        if let tally = session.tally {
            Text(tally)
                .themedText(.caption, color: session.tallyIsPlain ? .textTertiary : .taskOverdue)
                .accessibilityIdentifier("find-tally")
        }
    }

    /// A toggle labelled with what it does rather than with a word. `.*` is what a regular
    /// expression looks like and `Aa` is what case looks like; «Espressione regolare» spelled
    /// out would be the widest thing in the bar, and the bar has to leave room for the query.
    private func option(_ label: String, isOn: Binding<Bool>, help: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .themedText(.mono, color: isOn.wrappedValue ? .onAccent : .textSecondary)
                .padding(.horizontal, theme.spacing(.xs))
                .padding(.vertical, 3)
                .background(isOn.wrappedValue ? theme.color(.accentPrimary) : theme.color(.surfaceSunken))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityIdentifier("find-option-\(label == ".*" ? "regex" : "case")")
    }

    /// Says what it is scoped to and not merely that it is on: «Selezione» on its own is a
    /// control whose state has to be inferred from its shading.
    ///
    /// Read-only, because the scope is the selection captured when the bar opened. Turning it
    /// on later would have nothing to turn on to - the search moves the selection to each
    /// match as it goes.
    private var scope: some View {
        let isScoped = session.scope != nil
        return HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: isScoped ? "text.viewfinder" : "doc.text")
            Text(isScoped ? "Selezione" : "Nota").themedText(.caption)
        }
        .foregroundStyle(theme.color(isScoped ? .onAccent : .textSecondary))
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 3)
        .background(isScoped ? theme.color(.accentPrimary) : theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .help("L'ambito è la selezione che c'era quando la barra si è aperta")
        .accessibilityIdentifier("find-scope")
    }

    private var stepper: some View {
        HStack(spacing: theme.spacing(.s)) {
            Button { onStep(-1) } label: { Image(systemName: "chevron.up") }
                .accessibilityIdentifier("find-previous")
            Button { onStep(1) } label: { Image(systemName: "chevron.down") }
                .accessibilityIdentifier("find-next")
        }
        .buttonStyle(.plain)
        .disabled(session.matches.isEmpty)
        .foregroundStyle(theme.color(session.matches.isEmpty ? .textTertiary : .textSecondary))
    }
}

// MARK: - One of the two fields

/// A view rather than a method with eight arguments, which is what it was first and what
/// SwiftLint rightly stopped: the find field and the replace field differ in enough ways that
/// listing them at the call site says more than a shared helper hid.
private struct FindField: View {
    @Environment(\.theme) private var theme

    @Binding var text: String
    let placeholder: String
    let identifier: String
    /// Monospaced under the regex option: a pattern is read character by character, and `l1`
    /// against `I1` in a proportional face is a guess.
    let isMonospaced: Bool
    let focusRequest: Int
    let onSubmit: () -> Void
    let onSubmitBackwards: (() -> Void)?
    let onCancel: () -> Void
    /// The count, on the find field only. Inside the field at its trailing edge and not beside
    /// it: outside, it moves every time the number gains a digit and drags the buttons along.
    let trailing: AnyView?

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ComposerTextField(
                text: $text,
                placeholder: placeholder,
                font: theme.nsFont(isMonospaced ? .mono : .body),
                color: NSColor(theme.color(.textPrimary)),
                focusRequest: focusRequest,
                identifier: identifier,
                onSubmit: onSubmit,
                onSubmitBackwards: onSubmitBackwards,
                onCancel: onCancel
            )
            if let trailing { trailing }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}
