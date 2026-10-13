import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 §D1 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 2.
// R-03: a revision is unique per buffer value, so two buffers that differ in text never share one.

@Suite struct TextRevisionTests {
    // R-03: ten thousand draws on one thread are ten thousand distinct values.
    @Test func nextNeverRepeats() {
        let draws = (0..<10_000).map { _ in TextRevision.next() }
        #expect(Set(draws).count == draws.count)
    }

    // R-03: the counter is process-wide, so draws from tasks running at once never collide.
    @Test func nextIsUniqueAcrossTasks() async {
        let perTask = 2_000
        let tasks = 8
        let drawn = await withTaskGroup(of: [TextRevision].self) { group in
            for _ in 0..<tasks {
                group.addTask { (0..<perTask).map { _ in TextRevision.next() } }
            }
            var all: [TextRevision] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
        #expect(drawn.count == perTask * tasks)
        #expect(Set(drawn).count == drawn.count)
    }
}
