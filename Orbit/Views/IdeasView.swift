import SwiftData
import SwiftUI

struct IdeasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Idea.updatedAt, order: .reverse) private var ideas: [Idea]

    @State private var query = ""
    @State private var selectedTag: String?
    @State private var selectedIdeaID: UUID?

    private var filteredIdeas: [Idea] {
        ideas.filter { idea in
            let matchesQuery = query.isEmpty
                || idea.title.localizedStandardContains(query)
                || idea.content.localizedStandardContains(query)
                || idea.tags.contains(where: { $0.localizedStandardContains(query) })
            let matchesTag = selectedTag == nil || idea.tags.contains(selectedTag!)
            return matchesQuery && matchesTag
        }
    }

    private var topTags: [String] {
        let counts = ideas.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(10).map(\.key)
    }

    var body: some View {
        if let selectedIdeaID, let idea = ideas.first(where: { $0.id == selectedIdeaID }) {
            IdeaEditorView(idea: idea) { self.selectedIdeaID = nil }
        } else {
            browser
        }
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
                        IdeaBrowserCard(idea: idea, open: { selectedIdeaID = idea.id }, delete: { delete(idea) })
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
        modelContext.delete(idea)
        try? modelContext.save()
    }
}

private struct IdeaBrowserCard: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var idea: Idea
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
                Text(idea.content.isEmpty ? "Nothing written yet." : idea.content)
                    .font(.system(size: 12)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                HStack(spacing: 5) {
                    ForEach(idea.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 5))
                    }
                    if idea.tags.count > 2 { Text("+\(idea.tags.count - 2)").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)) }
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
    @Bindable var idea: Idea
    let close: () -> Void

    @State private var tagDraft = ""
    @State private var saveState = "Saved"
    @State private var autosaveTask: Task<Void, Never>?

    private var wordCount: Int { idea.content.split(whereSeparator: \.isWhitespace).count }
    private var readSeconds: Int { max(1, Int((Double(wordCount) / 200) * 60)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) { Label("Ideas", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text(saveState).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
                Button { idea.pinned.toggle(); scheduleSave() } label: { Image(systemName: idea.pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).foregroundStyle(idea.pinned ? OrbitTheme.accent : OrbitTheme.ink2(scheme)).help(idea.pinned ? "Unpin" : "Pin")
                Button(role: .destructive) { deleteIdea() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Delete idea")
            }
            .padding(.horizontal, 28).frame(height: 54)
            Divider().overlay(OrbitTheme.line(scheme))

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("Untitled", text: $idea.title, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 30, weight: .semibold))
                            .onChange(of: idea.title) { scheduleSave() }

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

                        TextEditor(text: $idea.content)
                            .font(.system(size: 15)).lineSpacing(7)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 480)
                            .onChange(of: idea.content) { scheduleSave() }
                    }
                    .padding(.horizontal, 52).padding(.vertical, 38)
                    .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }

                Divider().overlay(OrbitTheme.line(scheme))
                VStack(alignment: .leading, spacing: 18) {
                    Text("Document").font(.system(size: 13.5, weight: .semibold))
                    stat("Words", "\(wordCount)")
                    stat("Characters", "\(idea.content.count)")
                    stat("Read time", String(format: "%d:%02d", readSeconds / 60, readSeconds % 60))
                    Divider().overlay(OrbitTheme.line(scheme))
                    stat("Created", idea.createdAt.formatted(date: .abbreviated, time: .omitted))
                    stat("Edited", idea.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                }
                .padding(24).frame(width: 250, alignment: .leading).background(OrbitTheme.sunken(scheme).opacity(0.38))
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .onDisappear { autosaveTask?.cancel(); saveNow() }
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
        let descriptor = FetchDescriptor<IdeaLink>()
        if let links = try? modelContext.fetch(descriptor) {
            links.filter { $0.ideaAID == ideaID || $0.ideaBID == ideaID }.forEach(modelContext.delete)
        }
        modelContext.delete(idea); try? modelContext.save(); close()
    }
}
