import Foundation

/// The one place a grammar's token becomes a colour.
///
/// It lives here and not next to `CodeSyntax` because that file is `Core`, shared with
/// `perg` and `pergamenum-mcp`, and knows nothing about themes - it returns ranges, and
/// deciding what a keyword looks like is the design system's job (ADR-0001 §D1).
///
/// One mapping and not two: the editor colours an `NSTextStorage` and the reading view
/// builds an `AttributedString`, and if each carried its own switch the same code would
/// eventually be two different colours in the two panes of the same window.
extension CodeSyntax.Token {
    var colorToken: ColorToken {
        switch self {
        case .keyword: .codeKeyword
        case .string: .codeString
        case .comment: .codeComment
        case .number: .codeNumber
        case .type: .codeType
        }
    }
}
