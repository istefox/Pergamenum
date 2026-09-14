import Foundation
import OSLog

/// What the capture panel holds while it is open, and the one call it makes.
///
/// Writes through `VaultAPI.capture` - the door built in the first slice of M7 - and not
/// through anything of its own. ADR-0008 §D4: a capture implemented in the panel is a
/// capture `perg` and the MCP server do not have.
///
/// Separate from the panel so what it decides can be tested: the destination it
/// remembers, the text it holds on to, and what it does with a refusal. What cannot be
/// tested is the window appearing over another application, and that is in the panel.
@MainActor
@Observable
final class CaptureController {
    /// The four destinations, in the order the panel shows them.
    ///
    /// A view-level enum rather than `VaultAPI.CaptureDestination` because this one has
    /// to be `CaseIterable` and carry a title and a symbol; it converts on the way out.
    enum Destination: String, CaseIterable, Identifiable {
        case note, task, today, existing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .note: "Nota nuova"
            case .task: "Task"
            case .today: "Oggi"
            case .existing: "In una nota"
            }
        }

        var symbol: String {
            switch self {
            case .note: "doc.badge.plus"
            case .task: "tray"
            case .today: "calendar"
            case .existing: "doc.text"
            }
        }

        /// Says where the text is going, which is the only thing the bar above does not
        /// already say.
        var placeholder: String {
            switch self {
            case .note: "Titolo della nota, poi il testo"
            case .task: "Che cosa c'è da fare"
            case .today: "Aggiungi alla nota di oggi"
            case .existing: "Aggiungi alla nota scelta"
            }
        }

        /// Only a task carries dates (ADR-0008 §D6, and `VaultAPI.capture` refuses them
        /// elsewhere rather than dropping them).
        var takesDates: Bool { self == .task }
    }

    /// How the last capture ended, for the line the panel shows before it closes.
    enum Outcome: Equatable {
        case wrote(path: String)
        case refused(String)
    }

    // MARK: State

    /// Remembered between invocations: the same destination is used twenty times in a
    /// row and then never again (§D6).
    var destination: Destination = .note
    var text = ""
    var scheduled: CalendarDate?
    var due: CalendarDate?
    /// Where `.existing` and `.task` both write, shared: for `.existing`, nil means the
    /// destination cannot be used yet; for `.task`, nil means the fixed inbox note - a
    /// usable default, not a refusal.
    var notePath: String?
    /// Where `.note` writes. Nil means the default folder (`VaultAPI.CaptureDestination.defaultFolder`).
    var folder: String?
    private(set) var outcome: Outcome?

    /// When the unsent text stops being worth keeping.
    ///
    /// A capture that loses what was typed is trusted once (§D3). Sixty seconds is
    /// Craft's own window and long enough to dismiss the panel by accident and come
    /// back for it.
    static let draftLifetime: TimeInterval = 60
    private var draftExpiry: Date?

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Opening and closing

    /// Prepares the panel for a new invocation, keeping a recent unsent draft.
    ///
    /// `now` is a parameter rather than `Date()` read inside, so the expiry is testable
    /// without waiting a minute.
    func prepare(now: Date = Date()) {
        if let expiry = draftExpiry, now > expiry {
            text = ""
            scheduled = nil
            due = nil
        }
        draftExpiry = nil
        outcome = nil
    }

    /// Dismissed without capturing: what was typed survives for a minute.
    func hold(now: Date = Date()) {
        draftExpiry = isEmpty ? nil : now.addingTimeInterval(Self.draftLifetime)
    }

    /// Clears everything, for after a capture that went through.
    func reset() {
        text = ""
        scheduled = nil
        due = nil
        draftExpiry = nil
    }

    // MARK: Writing

    /// Captures into the current destination and reports what happened.
    ///
    /// Returns whether the panel should close: it stays open on a refusal, because the
    /// text that was refused is still the only copy of it.
    @discardableResult
    func capture(into session: VaultSession?) async -> Bool {
        // Deferred rather than written at each `return`: there are five ways out of this
        // function and the one that would get forgotten is a failure path.
        defer { log(outcome) }

        guard let session else {
            outcome = .refused("nessuna cartella note aperta")
            return false
        }
        guard !isEmpty else { return false }

        do {
            let summary = try await VaultAPI.capture(
                session,
                to: try target(),
                text: text,
                // `description` is the ISO form F-03 requires, which is what
                // `VaultAPI.day` reads back.
                scheduled: destination.takesDates ? scheduled?.description : nil,
                due: destination.takesDates ? due?.description : nil
            )
            outcome = .wrote(path: summary.path)
            reset()
            return true
        } catch let refusal as ConnectorError {
            outcome = .refused(refusal.description)
            return false
        } catch {
            outcome = .refused("\(error)")
            return false
        }
    }

    /// Says where the capture went, or why it did not.
    ///
    /// The destination and the resulting path only. **Never the text**: it is the whole
    /// content of the capture and the system log is not the place for it.
    ///
    /// Worth the two lines because the panel closes over another application, so a
    /// refusal shown for a moment on top of Safari is a refusal nobody reads. This is
    /// also what makes the write verifiable when the vault is somewhere unreadable - a
    /// UI-test instance writes into the runner's container, which not even the person
    /// running it can open.
    private func log(_ outcome: Outcome?) {
        switch outcome {
        case .wrote(let path):
            Logger.capture.info(
                "scritto in \(self.destination.rawValue, privacy: .public): \(path, privacy: .public)"
            )
        case .refused(let reason):
            Logger.capture.error(
                "rifiutato in \(self.destination.rawValue, privacy: .public): \(reason, privacy: .public)"
            )
        case nil:
            break
        }
    }

    /// The connector's destination for the one on screen.
    private func target() throws -> VaultAPI.CaptureDestination {
        // Explicit `return` on every branch: one arm has to throw, and a switch that
        // mixes an implicit-return arm with a statement arm stops inferring the type.
        switch destination {
        case .note: return .newNote(folder: folder)
        case .task: return .task(note: notePath)
        case .today: return .today
        case .existing:
            guard let notePath, !notePath.isEmpty else {
                throw ConnectorError("scegli la nota in cui scrivere", usage: true)
            }
            return .note(notePath)
        }
    }
}
