import AppKit

/// Two `NSTextField`s, tracer-bullet probe for ADR-0029 §D16 probe 2 - not the production
/// grid (Task 4/5's own `TableGridStore`/`TableEdit`, not built yet). Built only to answer:
/// does clicking a cell make it first responder, does Tab move to the next cell and
/// Shift-Tab to the previous, and do Tab from the last cell and Escape both hand first
/// responder back to the enclosing text view.
final class TableGridView: NSView, NSTextFieldDelegate {
    private let left = NSTextField(string: "Cella 1")
    private let right = NSTextField(string: "Cella 2")

    /// Called on Tab from the last cell and on Escape from either - the probe's own return
    /// path to the enclosing `CompletingTextView`, set by the Coordinator that owns it
    /// (`NoteTextView+Coordinator.swift`), the same closure-ownership shape `onEmbedResize`
    /// already uses: "this view has exactly one owner, and a closure makes that owner's
    /// identity a non-issue" (ADR §D6).
    var resignToTextView: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for field in [left, right] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.delegate = self
            addSubview(field)
        }
        // Forward Tab: AppKit walks a field editor's `nextKeyView` chain for free, both
        // ways - `right`'s implicit `previousKeyView` is the inverse of this, which is
        // what makes Shift-Tab from `right` land back on `left` with no code here at all.
        left.nextKeyView = right
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.widthAnchor.constraint(equalToConstant: 100),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 6),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.widthAnchor.constraint(equalToConstant: 100),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 216, height: 26) }

    /// Tab from the last cell and Escape from either cell both return to the text view
    /// (D16 probe 2's third pass criterion). Shift-Tab from `right` to `left` needs no case
    /// here - see `left.nextKeyView` above.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertTab(_:)) where control === right:
            resignToTextView?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            resignToTextView?()
            return true
        default:
            return false
        }
    }
}
