import AppKit
import SwiftUI

/// The Scorciatoie tab of the settings window (SPEC §12).
///
/// Every command in `ShortcutCommand` is listed and every one of them can be changed,
/// cleared or put back. The list is generated from the catalogue rather than written
/// out here, so a command added to the menu bar cannot quietly fail to appear.
struct ShortcutSettings: View {
    @Environment(\.theme) private var theme
    @Environment(ShortcutStore.self) private var shortcuts
    /// What the system did with the global capture shortcut (ADR-0008 §D2). Injected
    /// into this scene as well as the main window: an object put into one is not
    /// visible in the other, and reading a missing one is a trap at run time.
    @Environment(GlobalHotkey.self) private var hotkey

    var body: some View {
        Form {
            ForEach(ShortcutCommand.Section.allCases) { section in
                Section(section.title) {
                    ForEach(ShortcutCommand.allCases.filter { $0.section == section }) { command in
                        row(command)
                    }
                }
            }

            Section {
                Button("Ripristina tutte le scorciatoie") { shortcuts.resetAll() }
                    .disabled(shortcuts.overrides.isEmpty)
                Text("""
                Una scorciatoia già usata da macOS o da un'altra app resta a loro: il menu \
                la mostra e non si attiva. Il segnale di conflitto qui sopra riguarda solo \
                Pergamenum.
                """)
                    .themedText(.caption, color: .textTertiary)
                // Learned by trying it: Craft holds ⌃Spazio without asking the system
                // for exclusivity, so Pergamenum's own request succeeded, the row looked
                // right, and only Craft's panel opened. The registration cannot detect
                // that case, so the pane says it instead of implying otherwise.
                Text("""
                «Cattura rapida» è registrata a livello di sistema e funziona anche quando \
                Pergamenum non è in primo piano. Se un'altra app tiene già la stessa \
                combinazione, la registrazione può riuscire lo stesso e l'altra app \
                continuare a rispondere: il modo per accorgersene è premerla. In quel caso \
                cambiala qui.
                """)
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ command: ShortcutCommand) -> some View {
        let conflicts = shortcuts.conflicts(with: command)
        return LabeledContent {
            HStack(spacing: theme.spacing(.xs)) {
                // The global shortcut is the one case where the row can be right and the
                // shortcut still dead: the system may have refused it. What is shown is
                // the registration, never the intention (ADR-0008 §D2).
                if command == .globalCapture, let refusal = hotkey.state.explanation {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.color(.taskOverdue))
                        .help("Non registrata: \(refusal)")
                        .accessibilityIdentifier("hotkey-refused")
                }
                if !conflicts.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.color(.taskOverdue))
                        .help("Stessi tasti di: \(conflicts.map(\.title).joined(separator: ", "))")
                        .accessibilityIdentifier("conflict-\(command.rawValue)")
                }
                KeyRecorder(binding: shortcuts.binding(for: command)) { recorded in
                    shortcuts.set(recorded, for: command)
                }
                .accessibilityIdentifier("shortcut-\(command.rawValue)")
                Button {
                    shortcuts.reset(command)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("reset-\(command.rawValue)")
                .help("Torna a \(command.defaultBinding.displayString)")
                .disabled(!shortcuts.isCustomised(command))
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(command.title)
                // Said in words as well as with the triangle: a badge alone is noticed
                // and not understood, and this is the state that makes the feature
                // look broken rather than unavailable.
                if command == .globalCapture, let refusal = hotkey.state.explanation {
                    Text(refusal).themedText(.caption, color: .taskOverdue)
                }
            }
        }
    }
}

/// A field that records the next key combination pressed.
///
/// The keys are taken with a local event monitor rather than with `onKeyPress` or a
/// first-responder view: while recording, the combination being typed is usually a
/// menu shortcut, and the menu bar claims those before any view in the window sees
/// them. A local monitor runs inside `NSApplication.sendEvent`, before that dispatch,
/// and returning nil from it swallows the event so the menu does not also fire.
private struct KeyRecorder: View {
    @Environment(\.theme) private var theme
    let binding: KeyBinding
    let onRecord: (KeyBinding) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .themedText(.body, color: isRecording ? .accentPrimary : .textPrimary)
                .frame(minWidth: 92)
        }
        .buttonStyle(.bordered)
        // The combination as its accessibility value: a button with a custom label
        // reports no title, so without this the shortcut on screen is not readable
        // from outside the app - by VoiceOver or by a test.
        .accessibilityValue(label)
        .help(isRecording
            ? "Premi la combinazione. Esc annulla, Backspace toglie la scorciatoia."
            : "Fai clic e premi la nuova combinazione")
        // Stopped when the pane goes away as well as when a key arrives: a monitor
        // left installed swallows the next keystroke of whatever the user does next.
        .onDisappear { stop() }
    }

    private var label: String {
        if isRecording { return "…" }
        return binding.isValid ? binding.displayString : "nessuna"
    }

    private func toggle() {
        if isRecording { stop() } else { start() }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors are delivered on the main thread; the isolation is real,
            // it is only the AppKit signature that does not carry it.
            MainActor.assumeIsolated {
                handle(event)
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyBinding.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }

        // Escape alone leaves the binding as it was, and Backspace alone removes it.
        // Both are still available as shortcuts with a modifier held.
        if modifiers.isEmpty, event.keyCode == 53 {
            stop()
            return
        }
        if modifiers.isEmpty, event.keyCode == 51 {
            stop()
            onRecord(KeyBinding(""))
            return
        }

        guard let key = Self.key(for: event) else { return }
        let recorded = KeyBinding(key, modifiers)
        guard recorded.isValid else { return }
        stop()
        onRecord(recorded)
    }

    /// The key this event names, in the spelling `KeyBinding` stores.
    ///
    /// Key codes rather than characters for the named keys: the character for Return
    /// is a control code and the arrows have no character at all. For everything else
    /// the character *without* modifiers is what is wanted, so Cmd+Shift+2 records as
    /// `2` rather than as `"`.
    private static func key(for event: NSEvent) -> String? {
        if let named = namedKeyCodes[event.keyCode] { return named }
        guard let characters = event.charactersIgnoringModifiers, let first = characters.first,
              !first.isNewline, !first.isWhitespace
        else { return nil }
        return String(first)
    }

    private static let namedKeyCodes: [UInt16: String] = [
        49: "space", 36: "return", 48: "tab", 53: "escape", 51: "delete",
        126: "up", 125: "down", 123: "left", 124: "right",
        115: "home", 119: "end", 116: "pageUp", 121: "pageDown",
    ]
}
