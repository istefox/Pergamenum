import Foundation

/// `perg lint [percorso]` - the conformance check of SPEC §4.7.
///
/// The same rules the Conformità pane applies, because it is the same code: names,
/// the closed four-key frontmatter, the tag vocabularies, and the two directions of a
/// structural link.
enum LintCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))

        if arguments.has("apply") || arguments["fix"] != nil {
            throw CommandError(
                "le correzioni automatiche non ci sono ancora: per ora `perg lint` riferisce e basta"
            )
        }

        let report = try VaultAPI.lint(session, at: arguments.word(1))

        if arguments.has("json") {
            Output.json(report)
        } else {
            printForReading(report)
        }
        // A clean vault judged without its tag tables is worth less than it looks, so
        // the caveat goes to stderr rather than into the report a person skims.
        if let warning = report.warning { Output.error(warning) }

        // Non-conformance is an answer, not a failure of the command - but a script
        // asking "is this vault clean" needs the exit code to say so.
        return report.findings.isEmpty ? .success : .failure
    }

    private static func printForReading(_ report: VaultAPI.LintReport) {
        guard !report.findings.isEmpty else {
            Output.line("\(report.checked) note, tutte conformi")
            return
        }
        for finding in report.findings {
            Output.line(finding.path)
            for problem in finding.name { Output.line("    nome           \(problem)") }
            for problem in finding.frontmatter { Output.line("    frontmatter    \(problem)") }
            for problem in finding.tags { Output.line("    tag            \(problem)") }
            for problem in finding.relatedMissingInSection {
                Output.line("    related        manca nella sezione: \(problem)")
            }
            for problem in finding.relatedMissingInFrontmatter {
                Output.line("    related        manca nel frontmatter: \(problem)")
            }
        }
        Output.line("\(report.findings.count) note non conformi su \(report.checked)")
    }
}
