import SwiftData
import SwiftUI

struct IdeasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Idea.updatedAt, order: .reverse) private var ideas: [Idea]
    @Binding var requestedIdeaID: UUID?

    @State private var query = ""
    @State private var selectedTag: String?
    @State private var selectedIdeaID: UUID?

    init(requestedIdeaID: Binding<UUID?> = .constant(nil)) {
        _requestedIdeaID = requestedIdeaID
    }

    private var filteredIdeas: [Idea] {
        ideas.filter { idea in
            let matchesQuery = query.isEmpty
                || idea.title.localizedStandardContains(query)
                || idea.content.localizedStandardContains(query)
                || idea.tags.contains(where: { $0.localizedStandardContains(query) })
            let matchesTag = selectedTag == nil || idea.tags.contains(selectedTag!)
            let matchesHierarchy = !query.isEmpty || selectedTag != nil || idea.parentID == nil
            return matchesQuery && matchesTag && matchesHierarchy
        }
    }

    private var topTags: [String] {
        let counts = ideas.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(10).map(\.key)
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

                    ForEach(topTags.prefix(5), id: \.self) { tag in
                        Button("#\(tag)") { selectedTag = selectedTag == tag ? nil : tag }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(selectedTag == tag ? OrbitTheme.accent : OrbitTheme.ink2(scheme))
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(selectedTag == tag ? OrbitTheme.accentSoft(scheme) : OrbitTheme.sunken(scheme),
                                        in: Capsule())
                    }
                }

                if filteredIdeas.isEmpty {
                    emptyState
                } else {
                    let pinned = filteredIdeas.filter(\.pinned)
                    if !pinned.isEmpty {
                        ideaSection(title: "Pinned", ideas: pinned)
                    }
                    ideaSection(title: pinned.isEmpty ? "All ideas" : "Everything else", ideas: filteredIdeas.filter { !$0.pinned })
                }
            }
            .padding(32)
            .frame(maxWidth: 1220, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(OrbitTheme.canvas(scheme))
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
                            open: { selectedIdeaID = idea.id },
                            delete: { delete(idea) }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty && selectedTag == nil ? "lightbulb" : "magnifyingglass")
                .font(.system(size: 21)).foregroundStyle(OrbitTheme.accent)
                .frame(width: 48, height: 48).background(OrbitTheme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: 13))
            Text(query.isEmpty && selectedTag == nil ? "Capture your first idea" : "No ideas match")
                .font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty && selectedTag == nil
                 ? "A title is enough. You can shape the thought later."
                 : "Try a different phrase or clear the active tag.")
                .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
            if query.isEmpty && selectedTag == nil {
                Button("New idea") { createIdea() }.buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private func createIdea() {
        let idea = Idea(title: "", content: "", canvasX: nil, canvasY: nil)
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

private struct IdeaBrowserCard: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var idea: Idea
    let childCount: Int
    let parentTitle: String?
    let open: () -> Void
    let delete: () -> Void

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
                    Spacer()
                    Text(idea.updatedAt, style: .relative).font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme))
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

    private var tags: some View {
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
                .onSubmit(addTag)
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
