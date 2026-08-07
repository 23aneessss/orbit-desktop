import SwiftData
import SwiftUI

/// The "WORKSPACES" block in the sidebar: one row per workspace, an add row, and
/// rename/delete in each row's context menu. Selecting one scopes both the Ideas
/// list and the canvas to it.
struct WorkspaceSidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: [SortDescriptor(\Workspace.orderIndex), SortDescriptor(\Workspace.createdAt)])
    private var workspaces: [Workspace]

    /// Empty means "not chosen yet"; the views then show every idea rather than
    /// hiding anything.
    @AppStorage("orbit:workspace") private var currentID = ""
    @EnvironmentObject private var lock: WorkspaceLock
    let rail: Bool
    /// Jump to the Ideas screen when a workspace is picked.
    let openIdeas: () -> Void

    /// One sheet drives both creating and editing; `workspace == nil` means new.
    private struct Draft: Identifiable {
        let id = UUID()
        let workspace: Workspace?
        let name: String
        let icon: String
    }

    @State private var draft: Draft?

    var body: some View {
        VStack(spacing: 1) {
            if !rail {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(OrbitTheme.ink3(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
            }

            ForEach(workspaces) { workspace in
                row(workspace)
            }

            addRow
        }
        .sheet(item: $draft) { draft in
            WorkspaceEditorSheet(
                title: draft.workspace == nil ? "New workspace" : "Edit workspace",
                name: draft.name,
                icon: draft.icon
            ) { name, icon in
                if let workspace = draft.workspace {
                    WorkspaceService.update(workspace, name: name, icon: icon, context: modelContext)
                } else {
                    let created = WorkspaceService.create(name: name, icon: icon, context: modelContext)
                    currentID = created.id.uuidString
                    openIdeas()
                }
            }
        }
    }

    private func row(_ workspace: Workspace) -> some View {
        let isCurrent = currentID == workspace.id.uuidString

        return Button {
            currentID = workspace.id.uuidString
            openIdeas()
        } label: {
            HStack(spacing: 11) {
                Text(workspace.icon).font(.system(size: 14)).frame(width: 20)
                if !rail {
                    Text(workspace.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if workspace.locked {
                        Image(systemName: lock.isUnlocked(workspace.id) ? "lock.open" : "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(OrbitTheme.ink3(scheme))
                    }
                }
            }
            .foregroundStyle(isCurrent ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
            .padding(.horizontal, rail ? 18 : 16)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(isCurrent ? OrbitTheme.accentSoft(scheme) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.orbitRow)
        .padding(.horizontal, rail ? 9 : 16)
        .help(workspace.name)
        .draggable(workspace.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = UUID(uuidString: raw), dragged != workspace.id else { return false }

            // Ideas are draggable with the same payload shape, so the id tells us
            // which gesture this is: reorder a workspace, or rehome an idea.
            if workspaces.contains(where: { $0.id == dragged }) {
                WorkspaceService.reorder(dragged, toIndexOf: workspace.id, context: modelContext)
            } else {
                WorkspaceService.move(ideaID: dragged, to: workspace.id, context: modelContext)
            }
            return true
        }
        .contextMenu {
            Button("Rename or change icon", systemImage: "pencil") {
                draft = Draft(workspace: workspace, name: workspace.name, icon: workspace.icon)
            }
            Divider()
            if workspace.locked {
                // Re-locking is instant; it just forgets the in-memory unlock.
                Button("Lock now", systemImage: "lock.fill") { lock.lock(workspace.id) }
                    .disabled(!lock.isUnlocked(workspace.id))
                Button("Remove lock", systemImage: "lock.slash") {
                    workspace.locked = false
                    try? modelContext.save()
                }
            } else {
                Button("Require Touch ID", systemImage: "touchid") {
                    workspace.locked = true
                    lock.lock(workspace.id)
                    try? modelContext.save()
                }
            }
            Divider()
            // Disabled on the last workspace — the service also refuses it, so
            // its ideas can never be left without a home.
            Button("Delete", systemImage: "trash", role: .destructive) {
                if let fallback = WorkspaceService.delete(workspace, context: modelContext),
                   currentID == workspace.id.uuidString {
                    currentID = fallback.id.uuidString
                }
            }
            .disabled(workspaces.count <= 1)
        }
    }

    private var addRow: some View {
        Button { draft = Draft(workspace: nil, name: "", icon: "🗂") } label: {
            HStack(spacing: 11) {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).frame(width: 20)
                if !rail {
                    Text("Add workspace").font(.system(size: 13))
                    Spacer()
                }
            }
            .foregroundStyle(OrbitTheme.ink3(scheme))
            .padding(.horizontal, rail ? 18 : 16)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        }
        .buttonStyle(.orbitRow)
        .padding(.horizontal, rail ? 9 : 16)
        .help("Create a workspace")
    }
}

/// Name + icon, for both creating and editing. The icon grid is the same
/// `PageIconPicker` the page icons use.
private struct WorkspaceEditorSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let title: String
    @State private var name: String
    @State private var icon: String
    @State private var pickingIcon = false
    let save: (String, String) -> Void

    init(title: String, name: String, icon: String, save: @escaping (String, String) -> Void) {
        self.title = title
        _name = State(initialValue: name)
        _icon = State(initialValue: icon)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 15, weight: .semibold))

            HStack(spacing: 10) {
                Button { pickingIcon = true } label: {
                    Text(icon)
                        .font(.system(size: 21))
                        .frame(width: 42, height: 42)
                        .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.orbitRow)
                .help("Choose an icon")
                .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                    PageIconPicker(current: icon) { chosen in icon = chosen ?? "🗂" }
                }

                TextField("Workspace name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: commit).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func commit() {
        save(name, icon)
        dismiss()
    }
}
