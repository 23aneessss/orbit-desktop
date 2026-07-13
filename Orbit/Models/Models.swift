import Foundation
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var color: String
    var targetPerWeek: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog]

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "target",
        color: String = "accent",
        targetPerWeek: Int = 7,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.targetPerWeek = min(max(targetPerWeek, 1), 7)
        self.createdAt = createdAt
        self.logs = []
    }
}

@Model
final class HabitLog {
    @Attribute(.unique) var id: UUID
    var dateKey: String
    var createdAt: Date
    var habit: Habit?

    init(id: UUID = UUID(), dateKey: String, habit: Habit, createdAt: Date = .now) {
        self.id = id
        self.dateKey = dateKey
        self.habit = habit
        self.createdAt = createdAt
    }
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var tagsJSON: String
    var pinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var canvasX: Double?
    var canvasY: Double?

    init(
        id: UUID = UUID(),
        title: String,
        content: String = "",
        tags: [String] = [],
        pinned: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        canvasX: Double? = nil,
        canvasY: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tagsJSON = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canvasX = canvasX
        self.canvasY = canvasY
    }

    var tags: [String] {
        get {
            guard let data = tagsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            tagsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }
}

@Model
final class IdeaLink {
    @Attribute(.unique) var id: UUID
    var ideaAID: UUID
    var ideaBID: UUID
    var createdAt: Date

    init(id: UUID = UUID(), ideaAID: UUID, ideaBID: UUID, createdAt: Date = .now) {
        let ordered = [ideaAID, ideaBID].sorted { $0.uuidString < $1.uuidString }
        self.id = id
        self.ideaAID = ordered[0]
        self.ideaBID = ordered[1]
        self.createdAt = createdAt
    }
}

@Model
final class OrbitTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var done: Bool
    var canvasX: Double?
    var canvasY: Double?
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        done: Bool = false,
        canvasX: Double? = nil,
        canvasY: Double? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.done = done
        self.canvasX = canvasX
        self.canvasY = canvasY
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

@Model
final class OrbitTaskStep {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var parentID: UUID?
    var title: String
    var done: Bool
    var orderIndex: Int
    var canvasX: Double?
    var canvasY: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        taskID: UUID,
        parentID: UUID? = nil,
        title: String,
        done: Bool = false,
        orderIndex: Int = 0,
        canvasX: Double? = nil,
        canvasY: Double? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.taskID = taskID
        self.parentID = parentID
        self.title = title
        self.done = done
        self.orderIndex = orderIndex
        self.canvasX = canvasX
        self.canvasY = canvasY
        self.createdAt = createdAt
    }
}

@Model
final class StepLink {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var sourceID: UUID
    var targetID: UUID
    var createdAt: Date

    init(id: UUID = UUID(), taskID: UUID, sourceID: UUID, targetID: UUID, createdAt: Date = .now) {
        self.id = id
        self.taskID = taskID
        self.sourceID = sourceID
        self.targetID = targetID
        self.createdAt = createdAt
    }
}

@Model
final class BoardStroke {
    @Attribute(.unique) var id: UUID
    var taskID: UUID?
    var scopeID: UUID?
    var pointsJSON: String
    var color: String
    var lineWidth: Double
    var createdAt: Date

    init(id: UUID = UUID(), taskID: UUID? = nil, scopeID: UUID? = nil, points: [[Double]], color: String = "#8B5CF6", lineWidth: Double = 3, createdAt: Date = .now) {
        self.id = id
        self.taskID = taskID
        self.scopeID = scopeID
        self.pointsJSON = (try? String(data: JSONEncoder().encode(points), encoding: .utf8)) ?? "[]"
        self.color = color
        self.lineWidth = lineWidth
        self.createdAt = createdAt
    }

    var points: [[Double]] {
        guard let data = pointsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([[Double]].self, from: data)) ?? []
    }
}

@Model
final class BoardNote {
    @Attribute(.unique) var id: UUID
    var taskID: UUID?
    var scopeID: UUID?
    var text: String
    var color: String
    var canvasX: Double
    var canvasY: Double
    var createdAt: Date

    init(id: UUID = UUID(), taskID: UUID? = nil, scopeID: UUID? = nil, text: String = "New note", color: String = "#FEF3C7", canvasX: Double, canvasY: Double, createdAt: Date = .now) {
        self.id = id
        self.taskID = taskID
        self.scopeID = scopeID
        self.text = text
        self.color = color
        self.canvasX = canvasX
        self.canvasY = canvasY
        self.createdAt = createdAt
    }
}

@Model
final class Contact {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String?
    var phone: String?
    var company: String?
    var role: String?
    var tagsJSON: String
    var favorite: Bool
    var lastContactedKey: String?
    var nextFollowUpKey: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        phone: String? = nil,
        company: String? = nil,
        role: String? = nil,
        tags: [String] = [],
        favorite: Bool = false,
        lastContactedKey: String? = nil,
        nextFollowUpKey: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.company = company
        self.role = role
        self.tagsJSON = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        self.favorite = favorite
        self.lastContactedKey = lastContactedKey
        self.nextFollowUpKey = nextFollowUpKey
        self.createdAt = createdAt
    }

    var tags: [String] {
        get {
            guard let data = tagsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set { tagsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
}

@Model
final class Interaction {
    @Attribute(.unique) var id: UUID
    var contactID: UUID
    var kind: String
    var note: String
    var dateKey: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        contactID: UUID,
        kind: String = "note",
        note: String,
        dateKey: String = OrbitDate.key(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.contactID = contactID
        self.kind = kind
        self.note = note
        self.dateKey = dateKey
        self.createdAt = createdAt
    }
}

@Model
final class AppSetting {
    @Attribute(.unique) var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
