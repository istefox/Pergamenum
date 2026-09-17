import Foundation
import Testing
@testable import Pergamenum

// The category sidebar's own drag gesture (R-01's gap, closed): dragging one category row
// onto another reorders it among siblings or reparents it under a top-level target. No UI
// test drives the gesture itself while PG-162 (the macOS 27 UI-test drag regression) is
// open - only `CategoryDropResolver`, the pure mapping the view calls, is exercised here,
// the same shape `TaskDropTests.swift` uses for the task-onto-category drop.

// MARK: - Il carico che la riga trascinata porta

@Test func theDraggedCategoryPayloadRoundTrips() throws {
    let payload = CategoryDragPayload(slug: "vibrofer")

    let parsed = try #require(CategoryDragPayload(text: payload.text))

    #expect(parsed.slug == "vibrofer")
}

@Test func anEmptyPayloadIsRefused() {
    #expect(CategoryDragPayload(text: "") == nil)
}

// MARK: - `CategoryDropResolver`

// `Pergamenum.Category`, qualified: a bare `[Category]` type annotation on a free function
// is ambiguous against the Objective-C runtime's opaque `Category` typedef
// (`objc/runtime.h`) here - the constructor calls below disambiguate on their own through
// argument labels and need no such qualification.
private func registry(_ entries: [Pergamenum.Category]) -> CategoryRegistry {
    CategoryRegistry(version: CategoryRegistry.currentVersion, entries: entries)
}

@Test func droppingATopLevelCategoryOntoAnotherReordersBothAsSiblings() {
    let reg = registry([
        Category(slug: "a", name: "A", color: "rosso", order: 0),
        Category(slug: "b", name: "B", color: "blu", order: 1),
    ])

    let action = CategoryDropResolver.resolve(dragged: "a", ontoTarget: "b", in: reg)

    #expect(action == .reorder(parent: nil, slugs: ["b", "a"]))
}

@Test func droppingAChildOntoItsSiblingReordersOnlyThatParentsChildren() {
    let reg = registry([
        Category(slug: "vibrofer", name: "Vibrofer", color: "rosso", order: 0),
        Category(slug: "figlio-a", name: "Figlio A", color: "blu", parent: "vibrofer", order: 0),
        Category(slug: "figlio-b", name: "Figlio B", color: "verde", parent: "vibrofer", order: 1),
    ])

    let action = CategoryDropResolver.resolve(dragged: "figlio-b", ontoTarget: "figlio-a", in: reg)

    #expect(action == .reorder(parent: "vibrofer", slugs: ["figlio-b", "figlio-a"]))
}

/// Two top-level categories share the same (`nil`) parent, so they are siblings by the
/// same rule that makes two children of one parent siblings - the drop reorders the top
/// row's own order and never nests one under the other. Reparenting a top-level category
/// under another one is not a drag gesture this resolver produces at all; it stays reachable
/// only through `CategoryEditor`'s parent picker, unaffected by this fix.
@Test func droppingOneUnrelatedTopLevelCategoryOntoAnotherReordersRatherThanReparents() {
    let reg = registry([
        Category(slug: "vibrofer", name: "Vibrofer", color: "rosso", order: 0),
        Category(slug: "altra", name: "Altra", color: "blu", order: 1),
    ])

    let action = CategoryDropResolver.resolve(dragged: "altra", ontoTarget: "vibrofer", in: reg)

    #expect(action == .reorder(parent: nil, slugs: ["altra", "vibrofer"]))
}

@Test func droppingAChildOntoADifferentTopLevelParentReparentsIt() {
    let reg = registry([
        Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"),
        Category(slug: "altra", name: "Altra", color: "blu"),
        Category(slug: "offerte", name: "Offerte", color: "verde", parent: "vibrofer"),
    ])

    let action = CategoryDropResolver.resolve(dragged: "offerte", ontoTarget: "altra", in: reg)

    #expect(action == .reparent(dragged: "offerte", parent: "altra"))
}

/// Dropping a category onto the parent it already sits under: not a sibling relationship
/// (their `parent` fields differ) and not a reparent either (it already is one) - a no-op,
/// not a crash.
@Test func droppingAChildOntoItsOwnParentIsRefused() {
    let reg = registry([
        Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"),
        Category(slug: "offerte", name: "Offerte", color: "verde", parent: "vibrofer"),
    ])

    #expect(CategoryDropResolver.resolve(dragged: "offerte", ontoTarget: "vibrofer", in: reg) == nil)
}

/// A child dropped onto a non-top-level target from a different parent matches neither
/// case: it is refused rather than guessed at, leaving `reparentCategory`'s own
/// `parentNotTopLevel` rule as the only place that ever would have refused it anyway.
@Test func droppingOntoANonTopLevelTargetFromADifferentParentIsRefused() {
    let reg = registry([
        Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"),
        Category(slug: "altra", name: "Altra", color: "blu"),
        Category(slug: "offerte", name: "Offerte", color: "verde", parent: "vibrofer"),
        Category(slug: "preventivi", name: "Preventivi", color: "giallo", parent: "altra"),
    ])

    #expect(CategoryDropResolver.resolve(dragged: "preventivi", ontoTarget: "offerte", in: reg) == nil)
}

@Test func droppingACategoryOntoItselfIsRefused() {
    let reg = registry([Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")])

    #expect(CategoryDropResolver.resolve(dragged: "vibrofer", ontoTarget: "vibrofer", in: reg) == nil)
}

/// Either slug no longer resolving - the registry moved on since the drag started - is
/// refused by name, the same shape `dropTask` uses for a task line that moved.
@Test func aDropWhoseSlugsDoNotResolveInTheRegistryIsRefused() {
    let reg = registry([Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")])

    #expect(CategoryDropResolver.resolve(dragged: "fantasma", ontoTarget: "vibrofer", in: reg) == nil)
    #expect(CategoryDropResolver.resolve(dragged: "vibrofer", ontoTarget: "fantasma", in: reg) == nil)
}
