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
        let orphanIdeas = ideas.filter { $0.workspaceID == nil }
        for idea in orphanIdeas { idea.workspaceID = home.id }

        let folders = (try? context.fetch(FetchDescriptor<IdeaFolder>())) ?? []
        let orphanFolders = folders.filter { $0.workspaceID == nil }
        for folder in orphanFolders { folder.workspaceID = home.id }

        if !orphanIdeas.isEmpty || !orphanFolders.isEmpty || existing.isEmpty { try? context.save() }
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
    static func update(_ workspace: Workspace, name: String, icon: String, context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { workspace.name = trimmed }
        if !icon.isEmpty { workspace.icon = icon }
        try? context.save()
    }

    /// Drops the dragged workspace at the target's position and renumbers the
    /// whole list, so `orderIndex` stays contiguous however often it is moved.
    @MainActor
    static func reorder(_ draggedID: UUID, toIndexOf targetID: UUID, context: ModelContext) {
        var ordered = all(in: context)
        guard let from = ordered.firstIndex(where: { $0.id == draggedID }),
              let to = ordered.firstIndex(where: { $0.id == targetID }),
              from != to else { return }

        ordered.insert(ordered.remove(at: from), at: to)
        for (index, workspace) in ordered.enumerated() { workspace.orderIndex = index }
        try? context.save()
    }

    /// Moves an idea *and its sub-pages* so a page never ends up in a different
    /// workspace from its parent.
    @MainActor
    static func move(ideaID: UUID, to workspaceID: UUID, context: ModelContext) {
        let ideas = (try? context.fetch(FetchDescriptor<Idea>())) ?? []
        for idea in subtree(of: ideaID, in: ideas) {
            idea.workspaceID = workspaceID
            // Its folder stays behind in the old workspace, so drop the link
            // instead of leaving a reference the new workspace cannot show.
            idea.folderID = nil
        }
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
        let folders = (try? context.fetch(FetchDescriptor<IdeaFolder>())) ?? []
        for folder in folders where folder.workspaceID == workspace.id {
            folder.workspaceID = fallback.id
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
