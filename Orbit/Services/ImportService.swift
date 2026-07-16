import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct ImportSummary {
    let habits: Int
    let ideas: Int
    let tasks: Int
    let contacts: Int

    var message: String {
        "Restored \(habits) habits, \(ideas) ideas, \(tasks) tasks, and \(contacts) people."
    }
}

enum ImportService {
    enum ImportError: LocalizedError {
        case invalidFile
        case unsupportedApp
        case missingRelationship(String)

        var errorDescription: String? {
            switch self {
            case .invalidFile: "The selected file is not a valid Orbit backup."
            case .unsupportedApp: "This JSON file was not created by Orbit."
            case .missingRelationship(let item): "The backup contains a missing relationship: \(item)."
            }
        }
    }

    @MainActor
    static func restore(into context: ModelContext) throws -> ImportSummary? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Restore Orbit backup"
        panel.message = "Choose an Orbit JSON export. Current personal content will be replaced after validation."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = try Data(contentsOf: url)
        return try restore(data: data, into: context)
    }

    @MainActor
    static func restore(data: Data, into context: ModelContext) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: Backup
        do { backup = try decoder.decode(Backup.self, from: data) }
        catch { throw ImportError.invalidFile }
        guard backup.app.lowercased() == "orbit" else { throw ImportError.unsupportedApp }

        try validate(backup)

        do {
            try eraseCurrentContent(in: context)

            var habitsByID: [UUID: Habit] = [:]
            for item in backup.habits {
                let habit = Habit(id: item.id, name: item.name, icon: item.icon, color: item.color, targetPerDay: item.targetPerDay ?? 1, targetPerWeek: item.targetPerWeek, createdAt: item.createdAt ?? .now)
                context.insert(habit)
                habitsByID[item.id] = habit
            }
            for item in backup.habitLogs {
                guard let habit = habitsByID[item.habitId] else { throw ImportError.missingRelationship("habit log") }
                context.insert(HabitLog(id: item.id, dateKey: item.date, habit: habit, createdAt: item.createdAt ?? .now))
            }
            let folderIDs = Set((backup.ideaFolders ?? []).map(\.id))
            for item in backup.ideaFolders ?? [] {
                context.insert(IdeaFolder(id: item.id, name: item.name, createdAt: item.createdAt ?? .now))
            }
            for item in backup.ideas {
                let folderID = item.folderId.flatMap { folderIDs.contains($0) ? $0 : nil }
                context.insert(Idea(id: item.id, title: item.title, content: item.content, tags: item.tags, pinned: item.pinned, createdAt: item.createdAt ?? .now, updatedAt: item.updatedAt ?? .now, canvasX: item.canvasX, canvasY: item.canvasY, parentID: item.parentId, folderID: folderID))
            }
            for item in backup.ideaLinks {
                context.insert(IdeaLink(id: item.id, ideaAID: item.ideaAId, ideaBID: item.ideaBId, createdAt: item.createdAt ?? .now))
            }
            for item in backup.tasks {
                context.insert(OrbitTask(id: item.id, title: item.title, note: item.note, done: item.done, canvasX: item.canvasX, canvasY: item.canvasY, createdAt: item.createdAt ?? .now, completedAt: item.completedAt))
            }
            for item in backup.taskSteps {
                context.insert(OrbitTaskStep(id: item.id, taskID: item.taskId, parentID: item.parentId, title: item.title, done: item.done, orderIndex: item.orderIdx, canvasX: item.canvasX, canvasY: item.canvasY, createdAt: item.createdAt ?? .now))
            }
            for item in backup.stepLinks {
                context.insert(StepLink(id: item.id, taskID: item.taskId, sourceID: item.sourceId, targetID: item.targetId, createdAt: item.createdAt ?? .now))
            }
            for item in backup.boardStrokes {
                context.insert(BoardStroke(id: item.id, taskID: item.taskId, scopeID: item.scopeId, points: item.points, color: item.color, lineWidth: item.lineWidth, createdAt: item.createdAt ?? .now))
            }
            for item in backup.boardNotes {
                context.insert(BoardNote(id: item.id, taskID: item.taskId, scopeID: item.scopeId, text: item.text, color: item.color, canvasX: item.canvasX, canvasY: item.canvasY, createdAt: item.createdAt ?? .now))
            }
            for item in backup.contacts {
                context.insert(Contact(id: item.id, name: item.name, email: item.email, phone: item.phone, company: item.company, role: item.role, tags: item.tags, favorite: item.favorite, lastContactedKey: item.lastContactedAt, nextFollowUpKey: item.nextFollowUp, createdAt: item.createdAt ?? .now))
            }
            for item in backup.interactions {
                context.insert(Interaction(id: item.id, contactID: item.contactId, kind: item.kind, note: item.note, dateKey: item.date, createdAt: item.createdAt ?? .now))
            }
            for (key, value) in backup.settings { context.insert(AppSetting(key: key, value: value)) }

            try context.save()
            if let theme = backup.settings["theme"] { UserDefaults.standard.set(theme, forKey: "orbit:theme") }
            if let accent = backup.settings["accent"] { UserDefaults.standard.set(accent, forKey: "orbit:accent") }
            UserDefaults.standard.set(true, forKey: "orbit:tasks-seeded")
            UserDefaults.standard.set(true, forKey: "orbit:people-seeded")
            return ImportSummary(habits: backup.habits.count, ideas: backup.ideas.count, tasks: backup.tasks.count, contacts: backup.contacts.count)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func validate(_ backup: Backup) throws {
        let habitIDs = Set(backup.habits.map(\.id))
        let ideaIDs = Set(backup.ideas.map(\.id))
        let taskIDs = Set(backup.tasks.map(\.id))
        let stepIDs = Set(backup.taskSteps.map(\.id))
        let contactIDs = Set(backup.contacts.map(\.id))
        guard backup.habitLogs.allSatisfy({ habitIDs.contains($0.habitId) }) else { throw ImportError.missingRelationship("habit") }
        guard backup.ideaLinks.allSatisfy({ ideaIDs.contains($0.ideaAId) && ideaIDs.contains($0.ideaBId) }) else { throw ImportError.missingRelationship("idea") }
        guard backup.ideas.allSatisfy({ $0.parentId == nil || ($0.parentId != $0.id && ideaIDs.contains($0.parentId!)) }) else { throw ImportError.missingRelationship("idea page") }
        guard backup.taskSteps.allSatisfy({ taskIDs.contains($0.taskId) && ($0.parentId == nil || stepIDs.contains($0.parentId!)) }) else { throw ImportError.missingRelationship("task step") }
        guard backup.stepLinks.allSatisfy({ taskIDs.contains($0.taskId) && stepIDs.contains($0.sourceId) && stepIDs.contains($0.targetId) }) else { throw ImportError.missingRelationship("workflow") }
        guard backup.interactions.allSatisfy({ contactIDs.contains($0.contactId) }) else { throw ImportError.missingRelationship("contact") }
    }

    @MainActor
    private static func eraseCurrentContent(in context: ModelContext) throws {
        try context.delete(model: HabitLog.self)
        try context.delete(model: Habit.self)
        try context.delete(model: IdeaLink.self)
        try context.delete(model: Idea.self)
        try context.delete(model: IdeaFolder.self)
        try context.delete(model: StepLink.self)
        try context.delete(model: BoardStroke.self)
        try context.delete(model: BoardNote.self)
        try context.delete(model: OrbitTaskStep.self)
        try context.delete(model: OrbitTask.self)
        try context.delete(model: Interaction.self)
        try context.delete(model: Contact.self)
        try context.delete(model: AppSetting.self)
    }
}

private struct Backup: Decodable {
    let app: String
    let version: String
    let habits: [HabitItem]
    let habitLogs: [HabitLogItem]
    let ideas: [IdeaItem]
    let ideaLinks: [IdeaLinkItem]
    let ideaFolders: [IdeaFolderItem]?
    let tasks: [TaskItem]
    let taskSteps: [TaskStepItem]
    let stepLinks: [StepLinkItem]
    let boardStrokes: [BoardStrokeItem]
    let boardNotes: [BoardNoteItem]
    let contacts: [ContactItem]
    let interactions: [InteractionItem]
    let settings: [String: String]
}

private struct HabitItem: Decodable { let id: UUID; let name, icon, color: String; let targetPerDay: Int?; let targetPerWeek: Int; let createdAt: Date? }
private struct HabitLogItem: Decodable { let id, habitId: UUID; let date: String; let createdAt: Date? }
private struct IdeaItem: Decodable { let id: UUID; let title, content: String; let tags: [String]; let pinned: Bool; let parentId: UUID?; let folderId: UUID?; let canvasX, canvasY: Double?; let createdAt, updatedAt: Date? }
private struct IdeaLinkItem: Decodable { let id, ideaAId, ideaBId: UUID; let createdAt: Date? }
private struct IdeaFolderItem: Decodable { let id: UUID; let name: String; let createdAt: Date? }
private struct TaskItem: Decodable { let id: UUID; let title, note: String; let done: Bool; let canvasX, canvasY: Double?; let createdAt, completedAt: Date? }
private struct TaskStepItem: Decodable { let id, taskId: UUID; let parentId: UUID?; let title: String; let done: Bool; let orderIdx: Int; let canvasX, canvasY: Double?; let createdAt: Date? }
private struct StepLinkItem: Decodable { let id, taskId, sourceId, targetId: UUID; let createdAt: Date? }
private struct BoardStrokeItem: Decodable { let id: UUID; let taskId, scopeId: UUID?; let points: [[Double]]; let color: String; let lineWidth: Double; let createdAt: Date? }
private struct BoardNoteItem: Decodable { let id: UUID; let taskId, scopeId: UUID?; let text, color: String; let canvasX, canvasY: Double; let createdAt: Date? }
private struct ContactItem: Decodable { let id: UUID; let name: String; let email, phone, company, role: String?; let tags: [String]; let favorite: Bool; let lastContactedAt, nextFollowUp: String?; let createdAt: Date? }
private struct InteractionItem: Decodable { let id, contactId: UUID; let kind, note, date: String; let createdAt: Date? }
