import Foundation

/// `perg lint [percorso]` - the conformance check of SPEC §4.7.
///
/// The same rules the Conformità pane applies, because it is the same code: names,
/// the closed four-key frontmatter, the tag vocabularies, and the two directions of a
/// structural link.
///
/// One caveat worth knowing before trusting a clean run. The tag tables live in
/// `.pergamenum/vocabolari.json`, a replica of harness-system (SPEC §4.6). A vault the
/// app has never opened has no replica, and a command-line tool has no bundle to seed
/// one from - so the vocabulary is empty and the tag rules have nothing to judge
/// against. That is reported rather than passed over.
enum LintCommands {
    struct Finding: Encodable {
        let path: String
        let name: [String]
        let frontmatter: [String]
        let tags: [String]
        let relatedMissingInSection: [String]
        let relatedMissingInFrontmatter: [String]
        let count: Int
    }

    struct Report: Encodable {
        let checked: Int
        let conformant: Int
        let findings: [Finding]
    }

    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))

        if arguments.has("apply") || arguments["fix"] != nil {
            throw CommandError(
                "le correzioni automatiche non ci sono ancora: per ora `perg lint` riferisce e basta"
            )
        }

        let paths: [String]
        if let single = arguments.word(1) {
            guard session.exists(single) else { throw CommandError("«\(single)» non è nel vault") }
            paths = [single]
        } else {
            paths = session.index.allNotes.map(\.relativePath)
        }

        var findings: [Finding] = []
        for path in paths {
            guard let violations = session.violations(forRecordAt: path), !violations.isEmpty else { continue }
            findings.append(finding(path, violations))
        }

        if arguments.has("json") {
            Output.json(Report(
                checked: paths.count,
                conformant: paths.count - findings.count,
                findings: findings
            ))
        } else {
            printForReading(findings, checked: paths.count)
        }

        if session.vocabulary.isEmpty {
            Output.error(
                """
                nessun vocabolario in .pergamenum/vocabolari.json: le regole sui tag non \
                sono state applicate. Apri il vault in Pergamenum una volta, o copiaci il file.
                """
            )
        }

        // Non-conformance is an answer, not a failure of the command - but a script
        // asking "is this vault clean" needs the exit code to say so.
        return findings.isEmpty ? .success : .failure
    }

    private static func printForReading(_ findings: [Finding], checked: Int) {
        guard !findings.isEmpty else {
            Output.line("\(checked) note, tutte conformi")
            return
        }
        for finding in findings {
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
        Output.line("\(findings.count) note non conformi su \(checked)")
    }

    private static func finding(_ path: String, _ violations: NoteViolations) -> Finding {
        Finding(
            path: path,
            name: violations.name.map { "\($0)" },
            frontmatter: violations.frontmatter.map { "\($0)" },
            tags: violations.tags.map { "\($0)" },
            relatedMissingInSection: violations.relatedMissingInSection,
            relatedMissingInFrontmatter: violations.relatedMissingInFrontmatter,
            count: violations.count
        )
    }
}
