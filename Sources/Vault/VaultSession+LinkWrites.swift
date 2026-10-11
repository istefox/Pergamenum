import Foundation

// ADR-0084 §D3, §D4 (PG-386, N3 session A). Shared with `perg` and `pergamenum-mcp`
// (`sharedSources` in `Project.swift`): nothing here may reach for an app type.
extension VaultSession {
    /// How «Collega» ended.
    enum LinkMentionOutcome: Equatable, Sendable {
        case linked(WriteResult)
        case noMention
        case movedOn
        case failed(String)
    }

    /// What «Collega» would write into `path` for `title`, and the hash of the bytes that were
    /// read to compute it - the hash `addStructuralLink` computes its own `expecting:` from. Nil
    /// when no mention is left: the name went, or a link to it arrived.
    ///
    /// Remembers the hash of the `after` it returns under `(path, lowercased title)`, for the
    /// `linkMention` that follows. One entry per key, replaced by the next plan for it, consumed by
    /// `linkMention` and dropped by `forgetLinkMentionPlan`; a caller that abandons the diff should
    /// call the latter.
    func planLinkMention(
        in path: String, to title: String
    ) -> (before: String, after: String, hash: String)? {
        let key = Self.mentionPlanKey(path, title)
        // A file that exists but is no indexed note (a `.canvas`, a `.pergamenum/*.json`) is never
        // scanned: «Collega» rewrites prose, and only a note has any.
        guard linkEndRefusal(path) == nil,
              let (record, text) = try? read(path),
              let plan = mentionPlan(text: text, record: record, title: title)
        else {
            shownMentionPlans[key] = nil
            return nil
        }
        shownMentionPlans[key] = Self.shownHash(plan.after)
        return plan
    }

    /// Drops what `planLinkMention` remembered for `(path, title)`: the diff was cancelled and no
    /// `linkMention` will consume it. A no-op when nothing was remembered.
    func forgetLinkMentionPlan(in path: String, to title: String) {
        shownMentionPlans[Self.mentionPlanKey(path, title)] = nil
    }

    private static func mentionPlanKey(_ path: String, _ title: String) -> String {
        path + "\u{0}" + title.lowercased()
    }

    /// A shown plan is kept as a hash, not as the note's whole rewritten text.
    private static func shownHash(_ after: String) -> String {
        NoteStore.hash(Data(after.utf8))
    }

    /// Writes the planned link, once, expecting `hash` (ADR-0084 §D3).
    ///
    /// Reads and plans again, so what lands is computed from the bytes on disk now: no mention
    /// left is `.noMention`; a caller's hash that is not the read's is `.movedOn` with nothing
    /// written, and so is a refusal of the write itself, which carries `expecting:` the read's
    /// hash. The hash covers only the note's bytes, but the mention chosen also depends on the
    /// target's aliases in the index: when `planLinkMention` showed this caller a text and the
    /// plan now differs from it, that is `.movedOn` too, so only what the diff showed is
    /// written (R-26). Nothing read before the `await` is acted on after it (ADR-0043 §D7).
    func linkMention(in path: String, to title: String, expecting hash: String) async -> LinkMentionOutcome {
        let key = Self.mentionPlanKey(path, title)
        let shown = shownMentionPlans.removeValue(forKey: key)
        if let refusal = linkEndRefusal(path) { return .failed(refusal) }
        guard let (record, text) = try? read(path) else {
            return .failed("non riesco a leggere «\(path)»")
        }
        guard let plan = mentionPlan(text: text, record: record, title: title) else { return .noMention }
        guard plan.hash == hash else { return .movedOn }
        if let shown, shown != Self.shownHash(plan.after) { return .movedOn }
        do {
            return .linked(try await write(plan.after, to: path, expecting: plan.hash))
        } catch WriteRefusal.movedOn {
            return .movedOn
        } catch {
            return .failed("collegamento non scritto: \(error)")
        }
    }

    /// The scan's names for `title` - the title and the aliases of the note that carries it -
    /// and the rewrite of the first mention. A note never mentions itself, and a note that
    /// already links the title has no unlinked mention, as the inspector's list reads it.
    private func mentionPlan(
        text: String, record: NoteRecord, title: String
    ) -> (before: String, after: String, hash: String)? {
        guard record.title.lowercased() != title.lowercased(),
              BacklinkContext.lines(linking: title, in: text).isEmpty
        else { return nil }
        // The aliases of the one note that carries the title, which for that case is the
        // inspector's name list (`unlinkedMentions(for:)`). Two notes sharing it leave the alias
        // an ambiguous name, so none counts and a homonym's alias is never linked to the wrong
        // note; the inspector still passes the subject's aliases there, so an alias-only row of a
        // shared title answers `.noMention` here (ADR-0084 §D3).
        let carriers = index.resolve(title: title)
        let aliases = carriers.count == 1 ? (index.note(at: carriers[0])?.frontmatter.aliases ?? []) : []
        guard let mention = UnlinkedMentions.firstMention(of: [title] + aliases, in: text) else { return nil }
        return (text, MentionLink.rewrite(text, mention: mention, title: title), record.contentHash)
    }

    /// The sentence naming why `path` cannot be an end of a link, or nil when it is an indexed note.
    /// The invariant every link door holds, at the session so the app and a connector refuse the
    /// same way: a link end must be an indexed note, because a file that exists but is no note (a
    /// `.canvas`, a `.pergamenum/*.json`, a folder) must never receive frontmatter or a «Note
    /// correlate» bullet.
    func linkEndRefusal(_ path: String) -> String? {
        guard exists(path) else { return "nessuna nota in «\(path)»" }
        guard index.note(at: path) != nil else { return "«\(path)» non è una nota del vault" }
        return nil
    }

    /// «Scollega»: both notes lose the structural link, in two guarded writes (ADR-0084 §D4).
    ///
    /// `addStructuralLink`'s shape inverted (ADR-0057 §D8, ADR-0058 §D5): both removals are
    /// rendered before either write, each write carries `expecting:` its own read hash, a side
    /// that holds no link to the other is skipped rather than written, and neither side holding
    /// one is a problem. A refusal on the second write leaves the first landed, is named, and
    /// `written` holds what landed so the editor's tabs catch up. `removed` is true only when
    /// every side that held the link lost it.
    @discardableResult
    func removeStructuralLink(
        from sourcePath: String, toNoteAt targetPath: String
    ) async -> (removed: Bool, written: [WriteResult]) {
        if let refusal = [sourcePath, targetPath].lazy.compactMap({ self.linkEndRefusal($0) }).first {
            recordProblem(refusal)
            return (false, [])
        }
        guard targetPath != sourcePath else {
            recordProblem("\(RelatedLink.Error.linkingToItself)")
            return (false, [])
        }

        var written: [WriteResult] = []
        do {
            let source = try read(sourcePath)
            let target = try read(targetPath)
            let sourceTitle = source.record.title
            let targetTitle = target.record.title

            // The removal is by title, the doors take paths: with a homonym of either title in the
            // vault the entry found might point at the other note, so it is refused, not guessed.
            if let shared = [sourceTitle, targetTitle].first(where: { index.resolve(title: $0).count > 1 }) {
                recordProblem(
                    "legame strutturale non tolto: il titolo «\(shared)» è di più note, "
                        + "e il legame si toglie per titolo: rinomina una delle omonime"
                )
                return (false, [])
            }

            // Both renders happen before either write.
            let updatedSource = RelatedLink.remove(target: targetTitle, from: source.text)
            let updatedTarget = RelatedLink.remove(target: sourceTitle, from: target.text)
            let sourceHolds = updatedSource != source.text
            let targetHolds = updatedTarget != target.text
            guard sourceHolds || targetHolds else {
                recordProblem("nessun legame strutturale fra «\(sourceTitle)» e «\(targetTitle)»")
                return (false, [])
            }

            if sourceHolds {
                do {
                    written.append(
                        try await write(updatedSource, to: sourcePath, expecting: source.record.contentHash)
                    )
                } catch let refusal as WriteRefusal {
                    recordProblem("legame strutturale non tolto: \(refusal)")
                    return (false, written)
                }
            }
            if targetHolds {
                do {
                    written.append(
                        try await write(updatedTarget, to: targetPath, expecting: target.record.contentHash)
                    )
                } catch let refusal as WriteRefusal {
                    recordProblem(
                        written.isEmpty
                            ? "legame strutturale non tolto: \(refusal)"
                            : "legame strutturale tolto a metà: «\(sourceTitle)» "
                                + "non punta più a «\(targetTitle)», ma il ritorno resta - \(refusal)"
                    )
                    return (false, written)
                }
            }
            return (true, written)
        } catch {
            recordProblem("legame strutturale: \(error)")
            return (false, written)
        }
    }
}
