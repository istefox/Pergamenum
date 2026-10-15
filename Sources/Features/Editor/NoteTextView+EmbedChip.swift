import AppKit

/// A plain click on an embed chip opens its file in Quick Look (ADR-0087 §D9), the route a drawn
/// embed's Cmd+click already takes (`onOpenEmbed`, which resolves the name through
/// `VaultBoundary`, ADR-0041 §D1). One more claimant of the `onClickInMargin` chain.
extension NoteTextView.Coordinator {
    /// Claims a click with no modifier on the pill of a chip whose paragraph is not revealed; a
    /// revealed paragraph shows the raw `![[…]]`, and a click there places the caret. `modifiers` are
    /// the click's flags; nil reads them off the current event, which is what the click chain passes.
    func previewChip(
        at point: CGPoint, in textView: NSTextView, modifiers: NSEvent.ModifierFlags? = nil
    ) -> Bool {
        guard decorations.hidesMarkup, Self.isPlainClick(modifiers ?? NSApp.currentEvent?.modifierFlags ?? []),
              let onOpenEmbed = parent.vault.onOpenEmbed,
              let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return false }
        let local = Self.inContainer(point, of: textView)
        guard let fragment = manager.textLayoutFragment(for: local),
              fragment.layoutFragmentFrame.contains(local),
              !decorations.revealedParagraphs.contains(
                  content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
              ),
              let name = Self.chipTarget(
                  at: CGPoint(
                      x: local.x - fragment.layoutFragmentFrame.minX, y: local.y - fragment.layoutFragmentFrame.minY
                  ),
                  in: fragment, padding: decorations.constructStyle.chip.padding
              )
        else { return false }
        onOpenEmbed(name)
        return true
    }

    /// Whether a click with `flags` is a plain one, the only kind a chip claims: Command, Shift,
    /// Option or Control leave the click to the text view. Other flags (Caps Lock, the function key)
    /// do not count.
    static func isPlainClick(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .shift, .option, .control]).isEmpty
    }

    /// The target of the embed chip whose pill holds `point`, in `fragment`'s own coordinates.
    private static func chipTarget(at point: CGPoint, in fragment: NSTextLayoutFragment, padding: CGFloat) -> String? {
        guard let text = fragment.textLineFragments.first?.attributedString else { return nil }
        var target: String?
        text.enumerateAttribute(.pergamenumChip, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            guard (value as? InlineChip.Style)?.symbolName != nil else { return }
            let pills = InlineChipPainter.rects(for: range, in: fragment, padding: padding)
            guard pills.contains(where: { $0.contains(point) }) else { return }
            let run = (text.string as NSString).substring(with: range)
            target = WikilinkParser.links(in: run).first(where: \.isEmbed)?.target
            stop.pointee = true
        }
        return target
    }
}
