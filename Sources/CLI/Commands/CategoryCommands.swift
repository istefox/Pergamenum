import Foundation

/// `perg categories` / `perg category-tasks <slug>` - the two read-only category
/// surfaces of ADR-0047 §D9 (R-09). Two groups rather than `category list`/`category
/// tasks`, `PraticheCommands`'s own reason (`main.swift`): the plural lists and the
/// singular verb takes a name, which is how a person says it out loud.
enum CategoryCommands {
    @MainActor
    static func categories(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let categories = VaultAPI.categories(session)

        if arguments.has("json") {
            Output.json(categories)
        } else {
            for category in categories {
                var line = "\(category.slug): \(category.name)"
                if category.implicit { line += "  (implicita)" }
                if category.archived { line += "  (archiviata)" }
                line += "  \(category.progress.done)/\(category.progress.total)"
                Output.line(line)
            }
        }
        return .success
    }

    @MainActor
    static func categoryTasks(_ arguments: Arguments) async throws -> ExitCode {
        guard let slug = arguments.word(1), !slug.isEmpty else {
            throw CommandError("uso: perg category-tasks <slug>", code: .usage)
        }
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let payload = try VaultAPI.categoryTasks(session, slug: slug)

        if arguments.has("json") {
            Output.json(payload)
        } else {
            for group in payload.groups {
                if !group.label.isEmpty { Output.line(group.label) }
                for task in group.tasks {
                    Output.line("- [\(task.state)] \(task.text)")
                    Output.line("      \(task.path):\(task.line)")
                }
            }
        }
        return .success
    }
}
