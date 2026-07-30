import Foundation
import SwiftData

/// Workspace lifecycle, plus the one-time adoption of ideas that were written
/// before workspaces existed.
///
/// The rule everywhere here: **an idea is never deleted and never left
/// orphaned.** Deleting a workspace rehomes its ideas; the last workspace
/// cannot be deleted at all.
enum WorkspaceService {
    /// The workspace every pre-existing idea lands in.
    static let legacyName = "ETIC"

    @MainActor
    static func all(in context: ModelContext) -> [Workspace] {
        let descriptor = FetchDescriptor<Workspace>(
            sortBy: [SortDescriptor(\.orderIndex), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Creates the first workspace when there is none and adopts every idea that
    /// still has no workspace. Safe to call on every launch.
    @MainActor
    @discardableResult
    static func bootstrap(context: ModelContext) -> Workspace? {
        let existing = all(in: context)
        let home: Workspace

        if let first = existing.first {
            home = first
        } else {
            let created = Workspace(name: legacyName, icon: "🗂", orderIndex: 0)
            context.insert(created)
            home = created
        }

        // Fetch-and-filter rather than a predicate on an optional:
        // straightforward, and these collections are small.
        let ideas = (try? context.fetch(FetchDescriptor<Idea>())) ?? []
        let orphans = ideas.filter { $0.workspaceID == nil }
        for idea in orphans { idea.workspaceID = home.id }

        if !orphans.isEmpty || existing.isEmpty { try? context.save() }
        return home
    }

    @MainActor
    @discardableResult
    static func create(name: String, icon: String, context: ModelContext) -> Workspace {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (all(in: context).map(\.orderIndex).max() ?? -1) + 1
        let workspace = Workspace(
            name: trimmed.isEmpty ? "New workspace" : trimmed,
            icon: icon.isEmpty ? "🗂" : icon,
            orderIndex: next
        )
        context.insert(workspace)
        try? context.save()
        return workspace
    }

    @MainActor
    static func rename(_ workspace: Workspace, to name: String, context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.name = trimmed
        try? context.save()
    }

    /// Moves an idea *and its sub-pages* so a page never ends up in a different
    /// workspace from its parent.
    @MainActor
    static func move(ideaID: UUID, to workspaceID: UUID, context: ModelContext) {
        let ideas = (try? context.fetch(FetchDescriptor<Idea>())) ?? []
        for idea in subtree(of: ideaID, in: ideas) { idea.workspaceID = workspaceID }
        try? context.save()
    }

    /// Deletes a workspace, rehoming its ideas into the first remaining one.
    /// Refuses to delete the only workspace, which would leave ideas homeless.
    @MainActor
    @discardableResult
    static func delete(_ workspace: Workspace, context: ModelContext) -> Workspace? {
        let others = all(in: context).filter { $0.id != workspace.id }
        guard let fallback = others.first else { return nil }

        let ideas = (try? context.fetch(FetchDescriptor<Idea>())) ?? []
        for idea in ideas where idea.workspaceID == workspace.id {
            idea.workspaceID = fallback.id
        }
        context.delete(workspace)
        try? context.save()
        return fallback
    }

    /// An idea plus every descendant, guarding against a cycle in `parentID`.
    @MainActor
    private static func subtree(of rootID: UUID, in ideas: [Idea]) -> [Idea] {
        var result: [Idea] = []
        var seen: Set<UUID> = []
        var queue: [UUID] = [rootID]

        while let id = queue.popLast() {
            guard seen.insert(id).inserted, let idea = ideas.first(where: { $0.id == id }) else { continue }
            result.append(idea)
            queue.append(contentsOf: ideas.filter { $0.parentID == id }.map(\.id))
        }
        return result
    }
}
