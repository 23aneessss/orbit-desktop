import SwiftData
import SwiftUI

struct IdeasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Idea.updatedAt, order: .reverse) private var ideas: [Idea]
    @Query(sort: \IdeaFolder.name) private var folders: [IdeaFolder]
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
                                .buttonStyle(.plain).foregroundStyle(OrbitTheme.ink3(scheme))
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
                    .buttonStyle(.plain).help("Create a folder to organize ideas")
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
            .padding(32)
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
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(active ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(active ? OrbitTheme.accentSoft(scheme) : OrbitTheme.sunken(scheme), in: Capsule())
                }
                if selectedTags.count > 1 {
                    Button { selectedTags = [] } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
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
        let folder = IdeaFolder(name: name)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(ideas) { idea in
                        IdeaBrowserCard(
                            idea: idea,
                            childCount: self.ideas.count { $0.parentID == idea.id },
                            parentTitle: self.ideas.first { $0.id == idea.parentID }?.title,
                            folders: folders,
                            open: { selectedIdeaID = idea.id },
                            delete: { delete(idea) },
                            moveToFolder: { moveIdea(idea.id, to: $0) }
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
        let idea = Idea(title: "", content: "", canvasX: nil, canvasY: nil, folderID: selectedFolderID)
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
        .buttonStyle(.plain)
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
    let open: () -> Void
    let delete: () -> Void
    let moveToFolder: (UUID?) -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    if idea.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(OrbitTheme.accent) }
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
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(OrbitTheme.ink3(scheme)).frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                Text(idea.contentExcerpt.isEmpty ? "Nothing written yet." : idea.contentExcerpt)
                    .font(.system(size: 12)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
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
            .padding(16).frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).orbitCard()
    }
}

struct IdeaEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Idea.updatedAt, order: .reverse) private var allIdeas: [Idea]
    @Query private var allLinks: [IdeaLink]
    @Bindable var idea: Idea
    let openIdea: (UUID) -> Void
    let close: () -> Void

    @State private var tagDraft = ""
    @FocusState private var tagFieldFocused: Bool
    @State private var saveState = "Saved"
    @State private var autosaveTask: Task<Void, Never>?

    private var wordCount: Int { idea.content.split(whereSeparator: \.isWhitespace).count }
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

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        pageBreadcrumb

                        TextField("Untitled", text: $idea.title, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 30, weight: .semibold))
                            .onChange(of: idea.title) { scheduleSave() }

                        tags
                        relationships
                        subpages

                        MarkdownWorkspace(text: $idea.content)
                            .frame(minHeight: 560)
                            .onChange(of: idea.content) { scheduleSave() }
                    }
                    .padding(.horizontal, 46).padding(.vertical, 32)
                    .frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                }

                Divider().overlay(OrbitTheme.line(scheme))
                documentSidebar
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .onDisappear { autosaveTask?.cancel(); saveNow() }
    }

    private var editorHeader: some View {
        HStack(spacing: 14) {
            Button(action: close) { Label("Ideas", systemImage: "chevron.left") }.buttonStyle(.plain)
            Spacer()
            Text(saveState).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
            Button { idea.pinned.toggle(); scheduleSave() } label: { Image(systemName: idea.pinned ? "pin.fill" : "pin") }
                .buttonStyle(.plain).foregroundStyle(idea.pinned ? OrbitTheme.accent : OrbitTheme.ink2(scheme)).help(idea.pinned ? "Unpin" : "Pin")
            Button(role: .destructive) { deleteIdea() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).help("Delete idea")
        }
        .padding(.horizontal, 28).frame(height: 54)
    }

    @ViewBuilder private var pageBreadcrumb: some View {
        if let parent {
            HStack(spacing: 7) {
                Button { openIdea(parent.id) } label: {
                    Label(parent.title.isEmpty ? "Untitled" : parent.title, systemImage: "doc.text")
                }
                .buttonStyle(.plain).foregroundStyle(OrbitTheme.ink2(scheme))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(OrbitTheme.ink3(scheme))
                Text(idea.title.isEmpty ? "Untitled page" : idea.title).foregroundStyle(OrbitTheme.ink3(scheme))
            }
            .font(.system(size: 11.5, weight: .medium))
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
                            .buttonStyle(.plain).font(.system(size: 8, weight: .bold))
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var relationships: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Relationships").font(.system(size: 13.5, weight: .semibold))
                    Text("Directed links describe which ideas this page uses.")
                        .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
                }
                Spacer()
                Menu {
                    if availableTargets.isEmpty {
                        Text("No more ideas to connect")
                    } else {
                        ForEach(availableTargets) { target in
                            Button(target.title.isEmpty ? "Untitled" : target.title) { addRelation(to: target) }
                        }
                    }
                } label: {
                    Label("Add relation", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            relationshipRow(title: "Uses", symbol: "arrow.right", links: outgoingLinks, targetKeyPath: \.targetID)
            relationshipRow(title: "Used by", symbol: "arrow.left", links: incomingLinks, targetKeyPath: \.sourceID)
        }
        .padding(15)
        .background(OrbitTheme.sunken(scheme).opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(OrbitTheme.line(scheme)) }
    }

    private func relationshipRow(
        title: String,
        symbol: String,
        links: [IdeaLink],
        targetKeyPath: KeyPath<IdeaLink, UUID>
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(OrbitTheme.ink2(scheme))
                .frame(width: 78, alignment: .leading).padding(.top, 5)
            if links.isEmpty {
                Text("None").font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme)).padding(.top, 5)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(links) { link in
                            if let related = allIdeas.first(where: { $0.id == link[keyPath: targetKeyPath] }) {
                                HStack(spacing: 5) {
                                    Button(related.title.isEmpty ? "Untitled" : related.title) { openIdea(related.id) }
                                        .buttonStyle(.plain).lineLimit(1)
                                    Button { removeRelation(link) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.plain).font(.system(size: 8, weight: .bold))
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

    private var subpages: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Pages inside this idea").font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Button { createSubpage() } label: { Label("New subpage", systemImage: "doc.badge.plus") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if children.isEmpty {
                Text("Break this idea into focused pages. Every subpage also appears as a node on the Canvas.")
                    .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                    ForEach(children) { child in
                        Button { openIdea(child.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "doc.text").foregroundStyle(OrbitTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.title.isEmpty ? "Untitled page" : child.title)
                                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(child.contentExcerpt.isEmpty ? "Empty page" : child.contentExcerpt)
                                        .font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(OrbitTheme.ink3(scheme))
                            }
                            .padding(.horizontal, 11).frame(height: 48)
                            .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 9))
                            .overlay { RoundedRectangle(cornerRadius: 9).stroke(OrbitTheme.line(scheme)) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var documentSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Document").font(.system(size: 13.5, weight: .semibold))
            stat("Words", "\(wordCount)")
            stat("Characters", "\(idea.content.count)")
            stat("Subpages", "\(children.count)")
            stat("Relations", "\(outgoingLinks.count + incomingLinks.count)")
            Divider().overlay(OrbitTheme.line(scheme))
            if let parent {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Parent page").font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    Button(parent.title.isEmpty ? "Untitled" : parent.title) { openIdea(parent.id) }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).lineLimit(2)
                    Button("Move to top level") { idea.parentID = nil; scheduleSave() }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(OrbitTheme.accent)
                }
                Divider().overlay(OrbitTheme.line(scheme))
            }
            stat("Created", idea.createdAt.formatted(date: .abbreviated, time: .omitted))
            stat("Edited", idea.updatedAt.formatted(date: .abbreviated, time: .shortened))
            Spacer()
        }
        .padding(24).frame(width: 250, alignment: .leading).background(OrbitTheme.sunken(scheme).opacity(0.38))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(OrbitTheme.ink2(scheme)); Spacer(); Text(value).monospacedDigit() }
            .font(.system(size: 11.5))
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

    private func createSubpage() {
        let offset = Double(children.count % 4) * 34
        let child = Idea(
            title: "Untitled page",
            canvasX: idea.canvasX.map { $0 + 280 + offset },
            canvasY: idea.canvasY.map { $0 + 150 + offset },
            parentID: idea.id
        )
        modelContext.insert(child)
        modelContext.insert(IdeaLink(ideaAID: idea.id, ideaBID: child.id))
        try? modelContext.save()
        openIdea(child.id)
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
        modelContext.delete(idea); try? modelContext.save(); close()
    }
}
