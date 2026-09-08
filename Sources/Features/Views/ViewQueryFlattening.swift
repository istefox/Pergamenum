import Foundation

/// Whether a `where` expression is a flat conjunction of leaf terms, and if so what they
/// are (ADR-0034 §D5, R-06/R-07).
///
/// The query builder shows `where` as rows only when it can: `and` of leaf terms, in any
/// nesting parentheses produce (the parser discards them, ADR-0009's own grammar). `or` and
/// `not` are answered `nil`, which sends the Filtro section to its raw-text fallback rather
/// than guessing a row model that cannot represent them.
enum ViewQueryFlattening {
    /// The terms of a filter that is a flat conjunction of leaf terms, in source order.
    /// `nil` when the filter uses `or`, `not` or a nesting no row model can express.
    static func terms(of filter: ViewFilter) -> [ViewFilter]? {
        switch filter {
        case .all:
            []
        case .and(let lhs, let rhs):
            terms(of: lhs).flatMap { left in terms(of: rhs).map { left + $0 } }
        case .or:
            nil
        case .not:
            nil
        case .path, .tag, .linksTo, .linkedFrom, .task, .has, .text, .comparison:
            [filter]
        }
    }
}
