import SwiftData
import SwiftUI

struct IdeasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.orbitWidth) private var orbitWidth
    @Query(sort: \Idea.updatedAt, order: .reverse) private var storedIdeas: [Idea]
    @Query(sort: \IdeaFolder.name) private var storedFolders: [IdeaFolder]
    @Query private var settings: [AppSetting]
    @Query(sort: [SortDescriptor(\Workspace.orderIndex), SortDescriptor(\Workspace.createdAt)])
    private var workspaces: [Workspace]

    @AppStorage("orbit:workspace") private var currentWorkspaceRaw = ""

    private var currentWorkspaceID: UUID? { UUID(uuidString: currentWorkspaceRaw) }

    /// Scoped to the selected workspace. With no selection we deliberately show
    /// everything rather than risk hiding notes.
    private var ideas: [Idea] {
        guard let currentWorkspaceID else { return storedIdeas }
        return storedIdeas.filter { $0.workspaceID == currentWorkspaceID }
    }

    /// Folders belong to a workspace too, so one workspace never shows another's.
    private var folders: [IdeaFolder] {
        guard let currentWorkspaceID else { return storedFolders }
        return storedFolders.filter { $0.workspaceID == currentWorkspaceID }
    }
    @Binding var requestedIdeaID: UUID?

    @State private var query = ""
    @State private var selectedTags: Set<String> = []
    @State private var selectedFolderID: UUID?
    @State private var selectedIdeaID: UUID?
    @State private var folderDraft = ""
    @State private var creatingFolder = false
    @State private var renamingFolder: IdeaFolder?
    @State private var deletingFolder: IdeaFolder?

    init(requestedIdeaID: Binding<UUID?> = .constant(nil)) {
        _requestedIdeaID = requestedIdeaID
    }

    private var scopedIdeas: [Idea] {
        guard let selectedFolderID else { return ideas }
        return ideas.filter { $0.folderID == selectedFolderID }
    }

    private var filteredIdeas: [Idea] {
        let searching = !query.isEmpty || !selectedTags.isEmpty
        return scopedIdeas.filter { idea in
            let matchesQuery = query.isEmpty
                || idea.title.localizedStandardContains(query)
                || idea.content.localizedStandardContains(query)
                || idea.tags.contains(where: { $0.localizedStandardContains(query) })
            let matchesTags = selectedTags.allSatisfy { idea.tags.contains($0) }
            let matchesHierarchy = searching || idea.parentID == nil
            let matchesRoot = searching || selectedFolderID != nil || idea.folderID == nil
            return matchesQuery && matchesTags && matchesHierarchy && matchesRoot
        }
    }

    private var topTags: [String] {
        let counts = scopedIdeas.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map(\.key)
    }

    var body: some View {
        Group {
            if let selectedIdeaID, let idea = ideas.first(where: { $0.id == selectedIdeaID }) {
                IdeaEditorView(idea: idea, openIdea: { self.selectedIdeaID = $0 }) { self.selectedIdeaID = nil }
            } else {
                browser
            }
        }
        .onAppear { openRequestedIdea() }
        .onReceive(NotificationCenter.default.publisher(for: .closeOpenPage)) { _ in
            selectedIdeaID = nil
        }
        // A folder from the previous workspace would filter everything away.
        .onChange(of: currentWorkspaceRaw) { selectedFolderID = nil }
        .onChange(of: requestedIdeaID) { openRequestedIdea() }
    }

    private func openRequestedIdea() {
        guard let requestedIdeaID, ideas.contains(where: { $0.id == requestedIdeaID }) else { return }
        selectedIdeaID = requestedIdeaID
        self.requestedIdeaID = nil
    }

    private var browser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Ideas").font(.system(size: 27, weight: .semibold))
                        Text("Capture a thought, then connect it when the relationship becomes clear.")
                            .font(.system(size: 13.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    Spacer()
                    Button { createIdea() } label: { Label("New idea", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
                }

                HStack(spacing: 10) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(OrbitTheme.ink3(scheme))
                        TextField("Search titles, notes, and tags", text: $query).textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.orbitRow).foregroundStyle(OrbitTheme.ink3(scheme))
                        }
                    }
                    .padding(.horizontal, 13).frame(height: 40)
                    .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitTheme.line(scheme)) }

                    Button { folderDraft = ""; creatingFolder = true } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(OrbitTheme.ink2(scheme))
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitTheme.line(scheme)) }
                    }
                    .buttonStyle(.orbitRow).help("Create a folder to organize ideas")
                }

                if !folders.isEmpty { folderStrip }
                if !topTags.isEmpty { tagStrip }

                if filteredIdeas.isEmpty {
                    emptyState
                } else {
                    let pinned = filteredIdeas.filter(\.pinned)
                    let openFolderName = folders.first { $0.id == selectedFolderID }?.name
                    if !pinned.isEmpty {
                        ideaSection(title: "Pinned", ideas: pinned)
                    }
                    ideaSection(title: pinned.isEmpty ? (openFolderName ?? "All ideas") : "Everything else", ideas: filteredIdeas.filter { !$0.pinned })
                }
            }
            .padding(orbitWidth.pagePadding)
            .frame(maxWidth: 1220, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(OrbitTheme.canvas(scheme))
        .onChange(of: selectedFolderID) { selectedTags.formIntersection(topTags) }
        .alert("New folder", isPresented: $creatingFolder) {
            TextField("Folder name", text: $folderDraft)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) { folderDraft = "" }
        }
        .alert("Rename folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $folderDraft)
            Button("Rename") { renameFolder() }
            Button("Cancel", role: .cancel) { renamingFolder = nil; folderDraft = "" }
        }
        .confirmationDialog(
            "Delete folder “\(deletingFolder?.name ?? "")”?",
            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete folder", role: .destructive) { deleteFolder() }
        } message: {
            Text("Ideas inside move back to All ideas. No idea is deleted.")
        }
    }

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FolderChip(
                    title: "All ideas",
                    symbol: "tray.full",
                    count: nil,
                    selected: selectedFolderID == nil,
                    open: { selectedFolderID = nil },
                    drop: { moveIdea($0, to: nil) }
                )
                ForEach(folders) { folder in
                    FolderChip(
                        title: folder.name,
                        symbol: "folder",
                        count: ideas.count { $0.folderID == folder.id },
                        selected: selectedFolderID == folder.id,
                        open: { selectedFolderID = selectedFolderID == folder.id ? nil : folder.id },
                        drop: { moveIdea($0, to: folder.id) }
                    )
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { folderDraft = folder.name; renamingFolder = folder }
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingFolder = folder }
                    }
                }
            }
        }
    }

    private var tagStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(topTags, id: \.self) { tag in
                    let active = selectedTags.contains(tag)
                    Button("#\(tag)") {
                        if active { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                    }
                    .buttonStyle(.orbitRow)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(active ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(active ? OrbitTheme.accentSoft(scheme) : OrbitTheme.sunken(scheme), in: Capsule())
                }
                if selectedTags.count > 1 {
                    Button { selectedTags = [] } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                    .buttonStyle(.orbitRow)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OrbitTheme.ink3(scheme))
                    .padding(.horizontal, 9).frame(height: 32)
                }
            }
        }
    }

    private func createFolder() {
        let name = folderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        folderDraft = ""
        guard !name.isEmpty else { return }
        let folder = IdeaFolder(name: name, workspaceID: currentWorkspaceID ?? workspaces.first?.id)
        modelContext.insert(folder)
        try? modelContext.save()
        selectedFolderID = folder.id
    }

    private func renameFolder() {
        let name = folderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let renamingFolder, !name.isEmpty {
            renamingFolder.name = name
            try? modelContext.save()
        }
        renamingFolder = nil
        folderDraft = ""
    }

    private func deleteFolder() {
        guard let deletingFolder else { return }
        ideas.filter { $0.folderID == deletingFolder.id }.forEach { $0.folderID = nil }
        if selectedFolderID == deletingFolder.id { selectedFolderID = nil }
        modelContext.delete(deletingFolder)
        try? modelContext.save()
        self.deletingFolder = nil
    }

    @discardableResult
    private func moveIdea(_ id: UUID, to folderID: UUID?) -> Bool {
        guard let idea = ideas.first(where: { $0.id == id }), idea.folderID != folderID else { return false }
        idea.folderID = folderID
        idea.updatedAt = .now
        try? modelContext.save()
        return true
    }

    @ViewBuilder
    private func ideaSection(title: String, ideas: [Idea]) -> some View {
        if !ideas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 14.5, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 208), spacing: 11)], spacing: 11) {
                    ForEach(ideas) { idea in
                        IdeaBrowserCard(
                            idea: idea,
                            childCount: self.ideas.count { $0.parentID == idea.id },
                            parentTitle: self.ideas.first { $0.id == idea.parentID }?.title,
                            folders: folders,
                            icon: PageIcon.read(idea.id, from: settings),
                            open: { selectedIdeaID = idea.id },
                            delete: { delete(idea) },
                            moveToFolder: { moveIdea(idea.id, to: $0) },
                            workspaces: workspaces,
                            moveToWorkspace: { target in
                                WorkspaceService.move(ideaID: idea.id, to: target, context: modelContext)
                            }
                        )
                        .draggable(idea.id.uuidString)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        let unfiltered = query.isEmpty && selectedTags.isEmpty
        let inFolder = selectedFolderID != nil
        return VStack(spacing: 12) {
            Image(systemName: unfiltered ? (inFolder ? "folder" : "lightbulb") : "magnifyingglass")
                .font(.system(size: 21)).foregroundStyle(OrbitTheme.accent)
                .frame(width: 48, height: 48).background(OrbitTheme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: 13))
            Text(unfiltered ? (inFolder ? "This folder is empty" : "Capture your first idea") : "No ideas match")
                .font(.system(size: 17, weight: .semibold))
            Text(unfiltered
                 ? (inFolder
                    ? "Drag idea cards onto the folder chip above, or start a fresh idea here."
                    : "A title is enough. You can shape the thought later.")
                 : "Try a different phrase or clear the active tags.")
                .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
            if unfiltered {
                Button("New idea") { createIdea() }.buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private func createIdea() {
        let idea = Idea(
            title: "", content: "", canvasX: nil, canvasY: nil,
            folderID: selectedFolderID,
            workspaceID: currentWorkspaceID ?? workspaces.first?.id
        )
        modelContext.insert(idea)
        try? modelContext.save()
        selectedIdeaID = idea.id
    }

    private func delete(_ idea: Idea) {
        let ideaID = idea.id
        let descriptor = FetchDescriptor<IdeaLink>()
        if let links = try? modelContext.fetch(descriptor) {
            links.filter { $0.ideaAID == ideaID || $0.ideaBID == ideaID }.forEach(modelContext.delete)
        }
        ideas.filter { $0.parentID == ideaID }.forEach { $0.parentID = nil }
        modelContext.delete(idea)
        try? modelContext.save()
    }
}

private struct FolderChip: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let symbol: String
    let count: Int?
    let selected: Bool
    let open: () -> Void
    let drop: (UUID) -> Bool
    @State private var targeted = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10.5))
                Text(title)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(selected ? OrbitTheme.accent.opacity(0.75) : OrbitTheme.ink3(scheme))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(selected ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
            .padding(.horizontal, 11).frame(height: 32)
            .background(selected || targeted ? OrbitTheme.accentSoft(scheme) : OrbitTheme.sunken(scheme), in: Capsule())
            .overlay { Capsule().stroke(targeted ? OrbitTheme.accent : .clear, lineWidth: 1.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(.orbitRow)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            return drop(id)
        } isTargeted: { targeted = $0 }
        .help(count == nil ? "Show every idea. Drop a card here to take it out of its folder." : "Open folder. Drop an idea card here to file it.")
    }
}

private struct IdeaBrowserCard: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var idea: Idea
    let childCount: Int
    let parentTitle: String?
    let folders: [IdeaFolder]
    let icon: String?
    let open: () -> Void
    let delete: () -> Void
    let moveToFolder: (UUID?) -> Void
    let workspaces: [Workspace]
    /// Sends this page — and its sub-pages — to another workspace.
    let moveToWorkspace: (UUID) -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    if idea.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(OrbitTheme.accent) }
                    if let icon { Text(icon).font(.system(size: 14)) }
                    Text(idea.title.isEmpty ? "Untitled" : idea.title)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(OrbitTheme.ink(scheme)).lineLimit(2)
                    Spacer()
                    Menu {
                        Button(idea.pinned ? "Unpin" : "Pin", systemImage: idea.pinned ? "pin.slash" : "pin") { idea.pinned.toggle() }
                        if !folders.isEmpty {
                            Menu("Move to folder") {
                                ForEach(folders) { folder in
                                    Button(folder.name) { moveToFolder(folder.id) }
                                        .disabled(idea.folderID == folder.id)
                                }
                                if idea.folderID != nil {
                                    Divider()
                                    Button("Remove from folder") { moveToFolder(nil) }
                                }
                            }
                        }
                        if workspaces.count > 1 {
                            Menu("Move to workspace") {
                                ForEach(workspaces) { workspace in
                                    Button("\(workspace.icon)  \(workspace.name)") { moveToWorkspace(workspace.id) }
                                        .disabled(idea.workspaceID == workspace.id)
                                }
                            }
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(OrbitTheme.ink3(scheme)).frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                HStack(spacing: 5) {
                    ForEach(idea.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 5))
                    }
                    if idea.tags.count > 2 { Text("+\(idea.tags.count - 2)").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)) }
                    if childCount > 0 {
                        Label("\(childCount)", systemImage: "doc.on.doc")
                            .font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme))
                    } else if let parentTitle, !parentTitle.isEmpty {
                        Label(parentTitle, systemImage: "arrow.turn.up.left")
                            .font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)).lineLimit(1)
                    }
                    if let folderName = folders.first(where: { $0.id == idea.folderID })?.name {
                        Label(folderName, systemImage: "folder")
                            .font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)).lineLimit(1)
                    }
                    Spacer()
                }
            }
            // 154pt was sized around the content preview; without it the card was
            // mostly empty space.
            .padding(13).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.orbitRow).orbitCard()
    }
}

struct IdeaEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.orbitWidth) private var orbitWidth
    @Query(sort: \Idea.updatedAt, order: .reverse) private var allIdeas: [Idea]
    @Query private var allLinks: [IdeaLink]
    @Query private var settings: [AppSetting]
    @Bindable var idea: Idea
    let openIdea: (UUID) -> Void
    let close: () -> Void

    @State private var tagDraft = ""
    @FocusState private var tagFieldFocused: Bool
    @State private var saveState = "Saved"
    @State private var showingRelations = false
    @State private var showingIconPicker = false
    @State private var hoveredCrumbID: UUID?
    @State private var autosaveTask: Task<Void, Never>?

    private var outgoingLinks: [IdeaLink] { allLinks.filter { $0.sourceID == idea.id } }
    private var incomingLinks: [IdeaLink] { allLinks.filter { $0.targetID == idea.id } }
    private var children: [Idea] { allIdeas.filter { $0.parentID == idea.id }.sorted { $0.updatedAt > $1.updatedAt } }
    private var parent: Idea? { allIdeas.first { $0.id == idea.parentID } }
    private var availableTargets: [Idea] {
        let linkedIDs = Set(outgoingLinks.map(\.targetID))
        return allIdeas.filter { $0.id != idea.id && !linkedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider().overlay(OrbitTheme.line(scheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleBlock

                    tags

                    BlockEditorView(
                        text: $idea.content,
                        createPage: makeSubpage,
                        pageTitle: { id in allIdeas.first { $0.id == id }?.title },
                        pageIcon: { id in PageIcon.read(id, from: settings) },
                        openPage: { openIdea($0) }
                    )
                    .onChange(of: idea.content) { scheduleSave() }
                }
                .padding(.horizontal, orbitWidth.readerPadding).padding(.top, orbitWidth.isCompact ? 20 : 34).padding(.bottom, 8)
                .frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .onDisappear { autosaveTask?.cancel(); saveNow() }
    }

    private var editorHeader: some View {
        HStack(spacing: 14) {
            // The path lives here now: it says where you are *and* gets you back,
            // so the old "‹ Ideas" button was doing half its job twice.
            pageBreadcrumb
            Spacer(minLength: 12)
            Text(saveState).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
            Button { showingRelations.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    let count = outgoingLinks.count + incomingLinks.count
                    if count > 0 {
                        Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    }
                }
            }
            .buttonStyle(.orbitRow)
            .foregroundStyle(showingRelations ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
            .help("Relationships")
            .popover(isPresented: $showingRelations, arrowEdge: .bottom) { relationsPopover }
            Button { idea.pinned.toggle(); scheduleSave() } label: { Image(systemName: idea.pinned ? "pin.fill" : "pin") }
                .buttonStyle(.orbitRow).foregroundStyle(idea.pinned ? OrbitTheme.accent : OrbitTheme.ink2(scheme)).help(idea.pinned ? "Unpin" : "Pin")
            Button(role: .destructive) { deleteIdea() } label: { Image(systemName: "trash") }
                .buttonStyle(.orbitRow).help("Delete idea")
        }
        .padding(.horizontal, orbitWidth.isCompact ? 14 : 28).frame(height: 54)
    }

    /// Notion's trail: `icon Name / icon Name / **Current page**`.
    ///
    /// The old version buried the path — every crumb looked alike, the *current*
    /// page was the faintest item of all, and an accent-coloured "Move to top
    /// level" button sat in the middle of the trail. Now ancestors are muted and
    /// hoverable, the current page is the strongest, and detaching moved to its
    /// right-click menu so the path reads as a path.
    @ViewBuilder private var pageBreadcrumb: some View {
        let trail = IdeaHierarchy.ancestors(of: idea, in: allIdeas)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                    rootCrumb
                    Text("/")
                        .font(.system(size: 14))
                        .foregroundStyle(OrbitTheme.ink3(scheme).opacity(0.55))

                    ForEach(trail) { ancestor in
                        crumb(id: ancestor.id, title: ancestor.title, isCurrent: false) {
                            openIdea(ancestor.id)
                        }
                        Text("/")
                            .font(.system(size: 14))
                            .foregroundStyle(OrbitTheme.ink3(scheme).opacity(0.55))
                    }

                crumb(id: idea.id, title: idea.title, isCurrent: true, action: nil)
                    .contextMenu {
                        Button("Move to top level", systemImage: "arrow.up.left") {
                            idea.parentID = nil
                            scheduleSave()
                        }
                    }
            }
        }
    }

    /// First link of the path: back to the Ideas list.
    private var rootCrumb: some View {
        Button(action: close) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb").font(.system(size: 12))
                Text("Ideas")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(OrbitTheme.ink2(scheme))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(
                hoveredCrumbID == Self.rootCrumbID ? OrbitTheme.sunken(scheme) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.orbitRow)
        .onHover { hovering in
            if hovering { hoveredCrumbID = Self.rootCrumbID }
            else if hoveredCrumbID == Self.rootCrumbID { hoveredCrumbID = nil }
        }
        .help("Back to Ideas")
    }

    /// Sentinel so the root shares the same hover state as the other crumbs.
    private static let rootCrumbID = UUID()

    @ViewBuilder
    private func crumb(id: UUID, title: String, isCurrent: Bool, action: (() -> Void)?) -> some View {
        let label = HStack(spacing: 5) {
            crumbIcon(for: id)
            // Truncating the string keeps every crumb readable without forcing a
            // fixed width, which would pad short titles inside the scroll view.
            Text(shortened(title.isEmpty ? (isCurrent ? "Untitled page" : "Untitled") : title))
                .lineLimit(1)
        }
        .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
        .foregroundStyle(isCurrent ? OrbitTheme.ink(scheme) : OrbitTheme.ink2(scheme))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            hoveredCrumbID == id && action != nil ? OrbitTheme.sunken(scheme) : .clear,
            in: RoundedRectangle(cornerRadius: 5)
        )

        if let action {
            Button(action: action) { label.contentShape(Rectangle()) }
                .buttonStyle(.orbitRow)
                .onHover { hovering in
                    if hovering { hoveredCrumbID = id } else if hoveredCrumbID == id { hoveredCrumbID = nil }
                }
                .help("Open “\(title.isEmpty ? "Untitled" : title)”")
        } else {
            label
        }
    }

    private func shortened(_ title: String, limit: Int = 26) -> String {
        title.count <= limit ? title : title.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    @ViewBuilder private func crumbIcon(for id: UUID) -> some View {
        if let icon = PageIcon.read(id, from: settings) {
            Text(icon).font(.system(size: 13.5))
        } else {
            Image(systemName: "doc.text").font(.system(size: 12))
        }
    }

    /// Notion puts the icon above the title, with an "Add icon" affordance that
    /// only shows up when the page has none.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            let icon = PageIcon.read(idea.id, from: settings)

            Button { showingIconPicker = true } label: {
                if let icon {
                    Text(icon).font(.system(size: 56)).frame(height: 66, alignment: .leading)
                } else {
                    Label("Add icon", systemImage: "face.smiling")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(OrbitTheme.ink3(scheme))
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .buttonStyle(.orbitRow)
            .help(icon == nil ? "Add a page icon" : "Change page icon")
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                PageIconPicker(current: icon) { chosen in
                    PageIcon.write(chosen, for: idea.id, settings: settings, context: modelContext)
                    scheduleSave()
                }
            }

            TextField("Untitled", text: $idea.title, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 34, weight: .bold))
                .onChange(of: idea.title) { scheduleSave() }
        }
    }

    private var tagSuggestions: [String] {
        let current = Set(idea.tags)
        var counts: [String: Int] = [:]
        for other in allIdeas {
            for tag in other.tags where !current.contains(tag) {
                counts[tag, default: 0] += 1
            }
        }
        let draft = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "#", with: "")
        return counts.keys
            .filter { draft.isEmpty || $0.localizedStandardContains(draft) }
            .sorted { lhs, rhs in
                counts[lhs] == counts[rhs] ? lhs < rhs : counts[lhs, default: 0] > counts[rhs, default: 0]
            }
            .prefix(8)
            .map { $0 }
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(idea.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                        Button { removeTag(tag) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.orbitRow).font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(OrbitTheme.sunken(scheme), in: Capsule())
                }
                TextField("Add tag", text: $tagDraft)
                    .textFieldStyle(.plain).frame(width: 110)
                    .focused($tagFieldFocused)
                    .onSubmit(addTag)
            }
            if tagFieldFocused || !tagDraft.isEmpty, !tagSuggestions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 9)).foregroundStyle(OrbitTheme.ink3(scheme))
                        .help("Click an existing tag to add it")
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button { addExistingTag(tag) } label: {
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(OrbitTheme.accent)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(OrbitTheme.accentSoft(scheme), in: Capsule())
                        }
                        .buttonStyle(.orbitRow)
                    }
                }
            }
        }
    }

    private var relationsPopover: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Relationships").font(.system(size: 13.5, weight: .semibold))
                Text("Directed links describe which ideas this page uses.")
                    .font(.system(size: 11)).foregroundStyle(OrbitTheme.ink3(scheme))
            }

            relationshipRow(title: "Uses", symbol: "arrow.right", links: outgoingLinks, targetKeyPath: \.targetID)
            relationshipRow(title: "Used by", symbol: "arrow.left", links: incomingLinks, targetKeyPath: \.sourceID)

            Divider().overlay(OrbitTheme.line(scheme))

            Menu {
                if availableTargets.isEmpty {
                    Text("No more ideas to connect")
                } else {
                    ForEach(availableTargets) { target in
                        Button(target.title.isEmpty ? "Untitled" : target.title) { addRelation(to: target) }
                    }
                }
            } label: {
                Label("Add relation", systemImage: "plus")
            }
            .buttonStyle(.bordered).controlSize(.small).fixedSize()
        }
        .padding(16)
        .frame(width: orbitWidth.isCompact ? 300 : 340, alignment: .leading)
    }

    private func relationshipRow(
        title: String,
        symbol: String,
        links: [IdeaLink],
        targetKeyPath: KeyPath<IdeaLink, UUID>
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(OrbitTheme.ink2(scheme))
                .frame(width: 62, alignment: .leading).padding(.top, 5)
            if links.isEmpty {
                Text("None").font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme)).padding(.top, 5)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(links) { link in
                            if let related = allIdeas.first(where: { $0.id == link[keyPath: targetKeyPath] }) {
                                HStack(spacing: 5) {
                                    Button(related.title.isEmpty ? "Untitled" : related.title) { openIdea(related.id) }
                                        .buttonStyle(.orbitRow).lineLimit(1)
                                    Button { removeRelation(link) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.orbitRow).font(.system(size: 8, weight: .bold))
                                        .help("Remove relationship")
                                }
                                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(OrbitTheme.ink2(scheme))
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(OrbitTheme.surface(scheme), in: Capsule())
                                .overlay { Capsule().stroke(OrbitTheme.line(scheme)) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let tag = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "#", with: "")
        guard !tag.isEmpty, !idea.tags.contains(tag) else { tagDraft = ""; return }
        idea.tags.append(tag); tagDraft = ""; scheduleSave()
    }

    private func addExistingTag(_ tag: String) {
        guard !idea.tags.contains(tag) else { return }
        idea.tags.append(tag)
        tagDraft = ""
        scheduleSave()
    }

    private func removeTag(_ tag: String) { idea.tags.removeAll { $0 == tag }; scheduleSave() }

    private func addRelation(to target: Idea) {
        guard target.id != idea.id,
              !allLinks.contains(where: { $0.sourceID == idea.id && $0.targetID == target.id }) else { return }
        modelContext.insert(IdeaLink(ideaAID: idea.id, ideaBID: target.id))
        try? modelContext.save()
    }

    private func removeRelation(_ link: IdeaLink) {
        modelContext.delete(link)
        try? modelContext.save()
    }

    /// Backs the `/page` block: creates the real sub-page record and hands its
    /// id back so the block can link to it.
    private func makeSubpage() -> UUID? {
        let offset = Double(children.count % 4) * 34
        let child = Idea(
            title: "Untitled page",
            canvasX: idea.canvasX.map { $0 + 280 + offset },
            canvasY: idea.canvasY.map { $0 + 150 + offset },
            parentID: idea.id,
            workspaceID: idea.workspaceID   // a sub-page lives where its parent lives
        )
        modelContext.insert(child)
        modelContext.insert(IdeaLink(ideaAID: idea.id, ideaBID: child.id))
        try? modelContext.save()
        return child.id
    }

    private func scheduleSave() {
        saveState = "Saving…"
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        idea.updatedAt = .now
        try? modelContext.save()
        saveState = "Saved"
    }

    private func deleteIdea() {
        let ideaID = idea.id
        allLinks.filter { $0.sourceID == ideaID || $0.targetID == ideaID }.forEach(modelContext.delete)
        children.forEach { $0.parentID = nil }
        PageIcon.clear(ideaID, settings: settings, context: modelContext)
        modelContext.delete(idea); try? modelContext.save(); close()
    }
}
