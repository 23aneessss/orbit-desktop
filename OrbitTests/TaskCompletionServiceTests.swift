import XCTest
@testable import Orbit

@MainActor
final class TaskCompletionServiceTests: XCTestCase {
    func testTaskCompletesOnlyWhenEveryRootLeafIsComplete() {
        let task = OrbitTask(title: "Release")
        let first = OrbitTaskStep(taskID: task.id, title: "Build", done: true)
        let second = OrbitTaskStep(taskID: task.id, title: "Ship", done: false)

        TaskCompletionService.recompute(task: task, steps: [first, second])
        XCTAssertFalse(task.done)

        second.done = true
        TaskCompletionService.recompute(task: task, steps: [first, second])
        XCTAssertTrue(task.done)
        XCTAssertNotNil(task.completedAt)
    }

    func testCompositeCompletionRollsUpRecursively() {
        let task = OrbitTask(title: "Desktop")
        let parent = OrbitTaskStep(taskID: task.id, title: "Canvas")
        let childA = OrbitTaskStep(taskID: task.id, parentID: parent.id, title: "Nodes", done: true)
        let childB = OrbitTaskStep(taskID: task.id, parentID: parent.id, title: "Edges", done: true)

        TaskCompletionService.recompute(task: task, steps: [parent, childA, childB])

        XCTAssertTrue(parent.done)
        XCTAssertTrue(task.done)
    }

    func testReopeningChildReopensTaskAndClearsCompletionDate() {
        let task = OrbitTask(title: "Desktop", done: true, completedAt: .now)
        let parent = OrbitTaskStep(taskID: task.id, title: "Canvas", done: true)
        let child = OrbitTaskStep(taskID: task.id, parentID: parent.id, title: "Polish", done: false)

        TaskCompletionService.recompute(task: task, steps: [parent, child])

        XCTAssertFalse(parent.done)
        XCTAssertFalse(task.done)
        XCTAssertNil(task.completedAt)
    }
}
