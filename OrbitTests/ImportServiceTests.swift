import SwiftData
import XCTest
@testable import Orbit

@MainActor
final class ImportServiceTests: XCTestCase {
    func testRestoreReplacesContentAndRebuildsRelationships() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Idea(title: "Old idea"))
        try context.save()

        let habitID = UUID()
        let logID = UUID()
        let ideaID = UUID()
        let payload: [String: Any] = [
            "app": "orbit",
            "version": "1.0.0",
            "habits": [["id": habitID.uuidString, "name": "Read", "icon": "book", "color": "violet", "targetPerWeek": 7, "createdAt": "2026-07-01T08:00:00Z"]],
            "habitLogs": [["id": logID.uuidString, "habitId": habitID.uuidString, "date": "2026-07-13", "createdAt": "2026-07-13T08:00:00Z"]],
            "ideas": [["id": ideaID.uuidString, "title": "Connected thought", "content": "Restored", "tags": ["orbit"], "pinned": true, "canvasX": 120, "canvasY": 240, "createdAt": "2026-07-01T08:00:00Z", "updatedAt": "2026-07-13T08:00:00Z"]],
            "ideaLinks": [], "tasks": [], "taskSteps": [], "stepLinks": [], "boardStrokes": [], "boardNotes": [], "contacts": [], "interactions": [],
            "settings": ["name": "Aness", "theme": "system", "accent": "#8B5CF6"]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let summary = try ImportService.restore(data: data, into: context)

        XCTAssertEqual(summary.habits, 1)
        XCTAssertEqual(summary.ideas, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Habit>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLog>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Habit>()).first?.targetPerDay, 1)
        let restoredIdeas = try context.fetch(FetchDescriptor<Idea>())
        XCTAssertEqual(restoredIdeas.map(\.title), ["Connected thought"])
        XCTAssertEqual(restoredIdeas.first?.tags, ["orbit"])
    }

    func testRestoreRejectsBrokenRelationshipsBeforeDeletingCurrentData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Idea(title: "Keep me"))
        try context.save()

        let payload: [String: Any] = [
            "app": "orbit", "version": "1.0.0", "habits": [],
            "habitLogs": [["id": UUID().uuidString, "habitId": UUID().uuidString, "date": "2026-07-13"]],
            "ideas": [], "ideaLinks": [], "tasks": [], "taskSteps": [], "stepLinks": [], "boardStrokes": [], "boardNotes": [], "contacts": [], "interactions": [], "settings": [:]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try ImportService.restore(data: data, into: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Idea>()).map(\.title), ["Keep me"])
    }

    func testRestorePreservesNestedPagesAndDirectedIdeaLinks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let parentID = UUID()
        let childID = UUID()
        let linkID = UUID()
        let payload: [String: Any] = [
            "app": "orbit", "version": "1.0.0", "habits": [], "habitLogs": [],
            "ideas": [
                ["id": parentID.uuidString, "title": "Parent", "content": "# Parent", "tags": [], "pinned": false],
                ["id": childID.uuidString, "title": "Child", "content": "> Nested", "tags": [], "pinned": false, "parentId": parentID.uuidString]
            ],
            "ideaLinks": [["id": linkID.uuidString, "ideaAId": parentID.uuidString, "ideaBId": childID.uuidString]],
            "tasks": [], "taskSteps": [], "stepLinks": [], "boardStrokes": [], "boardNotes": [], "contacts": [], "interactions": [], "settings": [:]
        ]

        _ = try ImportService.restore(data: try JSONSerialization.data(withJSONObject: payload), into: context)

        let ideas = try context.fetch(FetchDescriptor<Idea>())
        let links = try context.fetch(FetchDescriptor<IdeaLink>())
        XCTAssertEqual(ideas.first(where: { $0.id == childID })?.parentID, parentID)
        XCTAssertEqual(links.first?.sourceID, parentID)
        XCTAssertEqual(links.first?.targetID, childID)
    }

    func testRestoreRejectsMissingIdeaParentWithoutDeletingCurrentData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Idea(title: "Keep me"))
        try context.save()
        let payload: [String: Any] = [
            "app": "orbit", "version": "1.0.0", "habits": [], "habitLogs": [],
            "ideas": [["id": UUID().uuidString, "title": "Orphan", "content": "", "tags": [], "pinned": false, "parentId": UUID().uuidString]],
            "ideaLinks": [], "tasks": [], "taskSteps": [], "stepLinks": [], "boardStrokes": [], "boardNotes": [], "contacts": [], "interactions": [], "settings": [:]
        ]

        XCTAssertThrowsError(try ImportService.restore(data: try JSONSerialization.data(withJSONObject: payload), into: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Idea>()).map(\.title), ["Keep me"])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Habit.self, HabitLog.self, Idea.self, IdeaLink.self, IdeaFolder.self, OrbitTask.self, OrbitTaskStep.self, StepLink.self, BoardStroke.self, BoardNote.self, Contact.self, Interaction.self, AppSetting.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}

@MainActor
final class HabitProgressTests: XCTestCase {
    func testDailyGoalRequiresTheConfiguredNumberOfCheckIns() {
        let habit = Habit(name: "Hydrate", targetPerDay: 3, targetPerWeek: 7)
        let first = HabitLog(dateKey: OrbitDate.key(), habit: habit)
        let second = HabitLog(dateKey: OrbitDate.key(), habit: habit)

        XCTAssertEqual(HabitProgress.count(in: [first, second]), 2)
        XCTAssertFalse(HabitProgress.isComplete(habit, in: [first, second]))

        let third = HabitLog(dateKey: OrbitDate.key(), habit: habit)
        XCTAssertTrue(HabitProgress.isComplete(habit, in: [first, second, third]))
    }

    func testCountsAreGroupedByDateForHeatmapIntensity() {
        let habit = Habit(name: "Practice", targetPerDay: 2, targetPerWeek: 5)
        let yesterday = OrbitDate.key(OrbitDate.date(daysFromToday: -1))
        let logs = [
            HabitLog(dateKey: yesterday, habit: habit),
            HabitLog(dateKey: yesterday, habit: habit),
            HabitLog(dateKey: OrbitDate.key(), habit: habit)
        ]

        let counts = HabitProgress.counts(logs)
        XCTAssertEqual(counts[yesterday], 2)
        XCTAssertEqual(counts[OrbitDate.key()], 1)
    }
}
