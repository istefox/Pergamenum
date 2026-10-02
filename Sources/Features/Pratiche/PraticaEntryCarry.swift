import Foundation

// ADR-0076 §D6 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 5 -
// R-14, R-15, R-18, R-19.
//
// «Sposta in…» carries the entries anchored to the moved message from the source
// `pratica.md` to the destination's: append first, and only once that landed, remove. Each
// step is a fresh read, a pure transform of `PraticaEntryEdit` and one `VaultSession.write`
// `expecting:` the hash just read, so a writer that got in between is refused, never
// overwritten. A refusal is an outcome with its sentence, never an error thrown past the verb,
// and the order is what keeps every refusal on the safe side: the worst case is the same block
// in both files, declared, never a block in neither.
//
// Every path argument here is a pratica's folder path (`PraticaListItem.id`); the files are
// `PraticaNaming.praticaNotePath(of:)` of it.
@MainActor
struct PraticaEntryCarry {
    let pratiche: PraticheController
    let vault: VaultController

    /// Where a carry step stands when `PraticheController.testOnlyCarryHook` is awaited:
    /// after its fresh read, before its write.
    enum Phase: Equatable, Sendable {
        case willAppend(notePath: String)
        case willRemove(notePath: String)
    }

    /// What the pre-flight decided before anything moved.
    enum Preflight: Equatable {
        /// No entry is anchored to the message: the move is today's, exactly (R-18).
        case nothingToCarry
        /// These blocks travel with the message.
        case carry(blocks: [String])
        /// Nothing may move; the sentence says why.
        case refused(String)
    }

    /// What travels, and between which two pratiche: the blocks anchored to `messageID`, from
    /// `source` to `destination` (both pratica folder paths).
    struct Transfer: Sendable {
        let blocks: [String]
        let messageID: String
        let source: String
        let destination: String
    }

    /// How far a carry got.
    enum Outcome: Equatable, Sendable {
        /// Appended to the destination and removed from the source.
        case carried(count: Int)
        /// Appended to the destination, but `missing` of them could not be removed from the
        /// source: they are in both files.
        case appendedOnly(count: Int, missing: Int)
        /// The destination write did not land: the entries stay in the source, orphaned.
        case notCarried
    }

    // MARK: - Sentences (ADR-0076 §D5/§D6)

    /// §D5's stale sentence, shared by every write that checks `timelineOrigin`.
    static let staleTimelineSentence = "«pratica.md» è cambiato: la cronologia è stata ricaricata, riprova."

    static func unsavedSentence(notePath: String) -> String {
        "Salva «\(notePath)» prima di spostare un messaggio con voci collegate: non è stato spostato nulla."
    }

    /// What a carry that did not fully land reports; nil for one that did.
    static func sentence(for outcome: Outcome, source: String, destination: String) -> String? {
        let sourceNote = PraticaNaming.praticaNotePath(of: source)
        let destinationNote = PraticaNaming.praticaNotePath(of: destination)
        switch outcome {
        case .carried:
            return nil
        case .appendedOnly:
            return "Le voci collegate sono ora sia in «\(sourceNote)» sia in «\(destinationNote)»: "
                + "non è stato possibile toglierle dall'origine."
        case .notCarried:
            // §D6's sentence, with the file that refused named after it.
            return "Il messaggio è stato spostato, ma le voci collegate sono rimaste in «\(sourceNote)»: "
                + "non è stato possibile aggiungerle a «\(destinationNote)»."
        }
    }

    // MARK: - The move

    /// Whether the message note itself is among `moved`: `moveFiles` moves the `.md` and the
    /// `.eml` independently, so a non-empty list does not say the message moved. The carry
    /// starts only when it did.
    static func noteMoved(
        in moved: [PraticaFileOperations.MovedFile], of detail: PraticaRowDetail, under root: URL?
    ) -> Bool {
        // In the boundary's spelling, the one `moveFiles` records `MovedFile.from` in (PG-360).
        guard let root, let note = try? VaultBoundary(root: root).url(for: detail.notePath) else { return false }
        return moved.contains { $0.from == note }
    }

    /// The undo's side of `noteMoved`: whether the message note itself is among what
    /// `moveBack` put back. The entries are carried back only when it is.
    static func noteRestored(in restored: Set<URL>, of detail: PraticaRowDetail, under root: URL?) -> Bool {
        // In the boundary's spelling, the one `moveFiles` records `MovedFile.from` in (PG-360).
        guard let root, let note = try? VaultBoundary(root: root).url(for: detail.notePath) else { return false }
        return restored.contains(note)
    }

    /// Before anything moves: the blocks anchored to `messageID` in the source, read fresh.
    /// With none, `.nothingToCarry` and nothing else is asked. With some, refused while either
    /// `pratica.md` has unsaved edits in a tab, or while the source changed since the timeline
    /// on screen read it - which also reloads the timeline, so a second try reads what is there.
    func preflight(messageID: String, from source: String, to destination: String) -> Preflight {
        let sourceNote = PraticaNaming.praticaNotePath(of: source)
        guard let session = vault.session,
              let read = try? session.read(sourceNote)
        else { return .nothingToCarry }
        let blocks = PraticaEntryEdit.blocks(anchoredTo: messageID, in: read.text)
        guard !blocks.isEmpty else { return .nothingToCarry }

        for notePath in [sourceNote, PraticaNaming.praticaNotePath(of: destination)]
        where vault.hasUnsavedTab(showing: notePath) {
            return .refused(Self.unsavedSentence(notePath: notePath))
        }
        // `timelineOrigin` describes the selected pratica only; a move is made from a row of
        // the timeline on screen, so the source is that pratica.
        if pratiche.selection == source, read.record.contentHash != pratiche.timelineOrigin {
            pratiche.reloadTimeline(from: vault)
            return .refused(Self.staleTimelineSentence)
        }
        return .carry(blocks: blocks)
    }

    /// After the message note moved and both dossiers were written: append the blocks to the
    /// destination, then, only once that landed, remove them from the source.
    ///
    /// `session` is the one the move started in, read before its first suspension: every step
    /// writes in it or refuses, never in whichever vault is current by then.
    func carry(_ transfer: Transfer, in session: VaultSession?) async -> Outcome {
        let blocks = transfer.blocks
        guard !blocks.isEmpty else { return .notCarried }
        let destinationNote = PraticaNaming.praticaNotePath(of: transfer.destination)
        let sourceNote = PraticaNaming.praticaNotePath(of: transfer.source)

        guard await step(
            .willAppend(notePath: destinationNote), in: session, { PraticaEntryEdit.appending(blocks, to: $0) }
        ) else { return .notCarried }

        var missing = blocks.count
        let removed = await step(.willRemove(notePath: sourceNote), in: session) { text in
            let removal = PraticaEntryEdit.removing(blocks, anchoredTo: transfer.messageID, from: text)
            missing = removal.missing.count
            return removal.text
        }
        guard removed, missing == 0 else {
            return .appendedOnly(count: blocks.count, missing: removed ? missing : blocks.count)
        }
        return .carried(count: blocks.count)
    }

    /// The undo's half (§D6), after the files and the dossiers went back: `.carried` appends
    /// the blocks to the end of the source and then removes them from the destination;
    /// `.appendedOnly` removes them from the destination, first putting back in the source any
    /// the source no longer holds; `.notCarried` touches no body. A dirty tab on either file
    /// skips it, and every step that does not land says where the entries are.
    ///
    /// `movedSession` is the one the move was made in. The undo manager outlives a vault switch, and
    /// a same-named `pratica.md` in the other vault is not the file the blocks came from: with
    /// any other session current, nothing is written and the sentence says where the entries
    /// are (ADR-0067 §D4's guard shape). Checked here for the whole verb's sake and again inside
    /// every step, on the same side of the suspension as the write it guards.
    func carryBack(_ outcome: Outcome, _ transfer: Transfer, in movedSession: VaultSession?) async {
        let blocks = transfer.blocks
        let messageID = transfer.messageID
        guard !blocks.isEmpty, outcome != .notCarried else { return }
        let sourceNote = PraticaNaming.praticaNotePath(of: transfer.source)
        let destinationNote = PraticaNaming.praticaNotePath(of: transfer.destination)
        let whereTheyAre: String
        if case .carried = outcome {
            whereTheyAre = "«\(destinationNote)»"
        } else {
            whereTheyAre = "«\(sourceNote)» e in «\(destinationNote)»"
        }
        guard let session = movedSession, vault.session === session else {
            pratiche.report("Le voci collegate non sono state riportate indietro perché il vault è cambiato: "
                + "sono in \(whereTheyAre).")
            return
        }

        for notePath in [sourceNote, destinationNote] where vault.hasUnsavedTab(showing: notePath) {
            pratiche.report("Le voci collegate non sono state riportate indietro perché «\(notePath)» "
                + "ha modifiche non salvate: sono in \(whereTheyAre).")
            return
        }

        var returning = blocks
        if case .appendedOnly = outcome, let read = try? session.read(sourceNote) {
            returning = PraticaEntryEdit.removing(blocks, anchoredTo: messageID, from: read.text).missing
        }
        if !returning.isEmpty {
            guard await step(
                .willAppend(notePath: sourceNote), in: session, { PraticaEntryEdit.appending(returning, to: $0) }
            ) else {
                pratiche.report("Le voci collegate sono rimaste in \(whereTheyAre): "
                    + "non è stato possibile riportarle in «\(sourceNote)».")
                return
            }
        }

        var missing = blocks.count
        let removed = await step(.willRemove(notePath: destinationNote), in: session) { text in
            let removal = PraticaEntryEdit.removing(blocks, anchoredTo: messageID, from: text)
            missing = removal.missing.count
            return removal.text
        }
        if !removed || missing > 0 {
            pratiche.report("Le voci collegate sono ora sia in «\(sourceNote)» sia in «\(destinationNote)»: "
                + "non è stato possibile toglierle da «\(destinationNote)».")
        }
    }

    // MARK: - One step

    /// One guarded body write: a fresh read, the test hook, the transform, and one write
    /// `expecting:` the hash read. `true` once the write landed, or when the transform left
    /// the text as it was and there was nothing to write; `false` on any refusal or failure,
    /// which the caller turns into its outcome and sentence.
    private func step(
        _ phase: Phase, in session: VaultSession?, _ transform: (String) -> String
    ) async -> Bool {
        let notePath: String
        switch phase {
        case .willAppend(let path), .willRemove(let path): notePath = path
        }
        guard let session, vault.session === session,
              let read = try? session.read(notePath)
        else { return false }
        await pratiche.testOnlyCarryHook?(phase)
        // The pre-flight's and `carryBack`'s dirty-tab checks ran before the moves, the dossier
        // writes and the hook above: a tab can have become dirty since, and `expecting:` cannot
        // see it (the disk did not change). The same holds for the vault: a switch during the hook
        // leaves `session` writing into a vault that is no longer the one on screen, and a path
        // read from it is not the path the blocks came from. Both asked again here, on the same
        // side of the last suspension as the write they guard, with no `await` in between; a
        // refusal is an outcome every caller already turns into its sentence, and never a lost
        // block, since an append that did not land leaves the entries in the source and a removal
        // that did not land leaves them in both.
        guard vault.session === session, !vault.hasUnsavedTab(showing: notePath) else { return false }
        let updated = transform(read.text)
        guard updated != read.text else { return true }
        do {
            try await session.write(updated, to: notePath, expecting: read.record.contentHash)
            return true
        } catch {
            return false
        }
    }
}
