import AppKit
import Foundation

enum ExportService {
    @MainActor
    static func export(
        habits: [Habit],
        habitLogs: [HabitLog],
        ideas: [Idea],
        ideaLinks: [IdeaLink],
        tasks: [OrbitTask],
        taskSteps: [OrbitTaskStep],
        stepLinks: [StepLink],
        boardStrokes: [BoardStroke],
        boardNotes: [BoardNote],
        contacts: [Contact],
        interactions: [Interaction],
        settings: [AppSetting]
    ) throws {
        let iso = ISO8601DateFormatter()
        func json(_ value: Any?) -> Any { value ?? NSNull() }
        let payload: [String: Any] = [
            "app": "orbit",
            "version": "1.0.0",
            "exportedAt": iso.string(from: .now),
            "habits": habits.map { ["id": $0.id.uuidString, "name": $0.name, "icon": $0.icon, "color": $0.color, "targetPerWeek": $0.targetPerWeek, "createdAt": iso.string(from: $0.createdAt)] },
            "habitLogs": habitLogs.map { ["id": $0.id.uuidString, "habitId": $0.habit?.id.uuidString ?? "", "date": $0.dateKey, "createdAt": iso.string(from: $0.createdAt)] },
            "ideas": ideas.map { ["id": $0.id.uuidString, "title": $0.title, "content": $0.content, "tags": $0.tags, "pinned": $0.pinned, "canvasX": json($0.canvasX), "canvasY": json($0.canvasY), "createdAt": iso.string(from: $0.createdAt), "updatedAt": iso.string(from: $0.updatedAt)] },
            "ideaLinks": ideaLinks.map { ["id": $0.id.uuidString, "ideaAId": $0.ideaAID.uuidString, "ideaBId": $0.ideaBID.uuidString, "createdAt": iso.string(from: $0.createdAt)] },
            "tasks": tasks.map { ["id": $0.id.uuidString, "title": $0.title, "note": $0.note, "done": $0.done, "canvasX": json($0.canvasX), "canvasY": json($0.canvasY), "createdAt": iso.string(from: $0.createdAt), "completedAt": json($0.completedAt.map(iso.string))] },
            "taskSteps": taskSteps.map { ["id": $0.id.uuidString, "taskId": $0.taskID.uuidString, "parentId": json($0.parentID?.uuidString), "title": $0.title, "done": $0.done, "orderIdx": $0.orderIndex, "canvasX": json($0.canvasX), "canvasY": json($0.canvasY), "createdAt": iso.string(from: $0.createdAt)] },
            "stepLinks": stepLinks.map { ["id": $0.id.uuidString, "taskId": $0.taskID.uuidString, "sourceId": $0.sourceID.uuidString, "targetId": $0.targetID.uuidString, "createdAt": iso.string(from: $0.createdAt)] },
            "boardStrokes": boardStrokes.map { ["id": $0.id.uuidString, "taskId": json($0.taskID?.uuidString), "scopeId": json($0.scopeID?.uuidString), "points": $0.points, "color": $0.color, "lineWidth": $0.lineWidth, "createdAt": iso.string(from: $0.createdAt)] },
            "boardNotes": boardNotes.map { ["id": $0.id.uuidString, "taskId": json($0.taskID?.uuidString), "scopeId": json($0.scopeID?.uuidString), "text": $0.text, "color": $0.color, "canvasX": $0.canvasX, "canvasY": $0.canvasY, "createdAt": iso.string(from: $0.createdAt)] },
            "contacts": contacts.map { ["id": $0.id.uuidString, "name": $0.name, "email": json($0.email), "phone": json($0.phone), "company": json($0.company), "role": json($0.role), "tags": $0.tags, "favorite": $0.favorite, "lastContactedAt": json($0.lastContactedKey), "nextFollowUp": json($0.nextFollowUpKey), "createdAt": iso.string(from: $0.createdAt)] },
            "interactions": interactions.map { ["id": $0.id.uuidString, "contactId": $0.contactID.uuidString, "kind": $0.kind, "note": $0.note, "date": $0.dateKey, "createdAt": iso.string(from: $0.createdAt)] },
            "settings": Dictionary(uniqueKeysWithValues: settings.map { ($0.key, $0.value) })
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "orbit-export-\(OrbitDate.key()).json"
        panel.title = "Export Orbit data"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }
}
