import Foundation
import Testing
@testable import Pergamenum

// PG-168 / #313, gap 2: «Rigenera» refused after a relocation used to let `restore`'s own
// generic sentence overwrite the actionable one. `restore` now reports nothing and returns
// what it could not put back; it must also never recreate the folder it is restoring into.

@MainActor @Suite(.serialized) struct PraticaFileOperationsRestoreTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func trashed(_ name: String, in root: URL, folderExists: Bool) throws -> PraticaFileOperations.TrashedFile {
        let folder = root.appending(path: "Pratica/email", directoryHint: .isDirectory)
        let inTrash = root.appending(path: "trash-\(name)", directoryHint: .notDirectory)
        try Data("x".utf8).write(to: inTrash)
        if folderExists { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return .init(original: folder.appending(path: name), inTrash: inTrash, relativePath: "Pratica/email/\(name)")
    }

    @Test func restorePutsAFileBackWhereItWas() throws {
        let root = try makeRoot()
        let file = try trashed("a.md", in: root, folderExists: true)

        let failures = PraticaFileOperations.restore([file])

        #expect(failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.original.path(percentEncoded: false)))
    }

    @Test func restoreReturnsTheFilesItCouldNotPutBackAndDoesNotRecreateTheFolder() throws {
        let root = try makeRoot()
        let file = try trashed("a.md", in: root, folderExists: false)

        let failures = PraticaFileOperations.restore([file])

        #expect(failures == [file])
        #expect(
            !FileManager.default.fileExists(atPath: root.appending(path: "Pratica").path(percentEncoded: false)),
            "restoring must not resurrect the vacated folder"
        )
        #expect(
            FileManager.default.fileExists(atPath: file.inTrash.path(percentEncoded: false)),
            "and the file stays where it can still be recovered"
        )
    }

    @Test func restoreFailureMessageCoversNoneOneAndMany() throws {
        let root = try makeRoot()
        let a = try trashed("a.md", in: root, folderExists: false)
        let b = try trashed("b.md", in: root, folderExists: false)

        #expect(PraticaFileOperations.restoreFailureMessage(for: []) == nil)
        #expect(
            PraticaFileOperations.restoreFailureMessage(for: [a])
                == "«Pratica/email/a.md» non è tornato al suo posto: resta nel Cestino, recuperabile da lì."
        )
        #expect(
            PraticaFileOperations.restoreFailureMessage(for: [a, b])
                == "2 file non sono tornati al loro posto: restano nel Cestino, recuperabili da lì."
        )
    }
}
