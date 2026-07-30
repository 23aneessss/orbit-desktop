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
    let rail: Bool
    /// Jump to the Ideas screen when a workspace is picked.
    let openIdeas: () -> Void

    @State private var renaming: Workspace?
    @State private var draftName = ""
    @State private var addingName = ""
    @State private var isAdding = false

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
        .alert("Rename workspace", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let workspace = renaming {
                    WorkspaceService.rename(workspace, to: draftName, context: modelContext)
                }
                renaming = nil
            }
        }
        .alert("New workspace", isPresented: $isAdding) {
            TextField("Name", text: $addingName)
            Button("Cancel", role: .cancel) { addingName = "" }
            Button("Create") {
                let created = WorkspaceService.create(name: addingName, icon: "🗂", context: modelContext)
                currentID = created.id.uuidString
                addingName = ""
                openIdeas()
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
                }
            }
            .foregroundStyle(isCurrent ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
            .padding(.horizontal, rail ? 18 : 16)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(isCurrent ? OrbitTheme.accentSoft(scheme) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, rail ? 9 : 16)
        .help(workspace.name)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                draftName = workspace.name
                renaming = workspace
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
        Button { isAdding = true } label: {
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
        .buttonStyle(.plain)
        .padding(.horizontal, rail ? 9 : 16)
        .help("Create a workspace")
    }
}
