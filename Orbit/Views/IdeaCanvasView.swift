import SwiftData
import SwiftUI

private struct MergeCandidate: Identifiable {
    let draggedID: UUID
    let targetID: UUID
    var id: String { "\(draggedID)-\(targetID)" }
}

struct IdeaCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Idea.createdAt) private var ideas: [Idea]
    @Query private var links: [IdeaLink]

    @State private var pan = CGSize.zero
    @State private var committedPan = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var selectedIdeaID: UUID?
    @State private var openedIdeaID: UUID?
    @State private var selectedLinkID: UUID?
    @State private var connectionSourceID: UUID?
    @State private var connectionStart: CGPoint?
    @State private var connectionEnd: CGPoint?
    @State private var mergeCandidate: MergeCandidate?

    var body: some View {
        Group {
            if let openedIdeaID,
               let idea = ideas.first(where: { $0.id == openedIdeaID }) {
                IdeaEditorView(idea: idea, openIdea: { self.openedIdeaID = $0 }) { self.openedIdeaID = nil }
            } else {
                canvasContent
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .task { tileUnplacedIdeas() }
        .onChange(of: ideas.map(\.id)) { tileUnplacedIdeas() }
        .sheet(item: $mergeCandidate) { candidate in
            if let dragged = ideas.first(where: { $0.id == candidate.draggedID }),
               let target = ideas.first(where: { $0.id == candidate.targetID }) {
                MergeIdeasSheet(dragged: dragged, target: target) {
                    merge(dragged: dragged, into: target)
                }
            }
        }
    }

    private var canvasContent: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OrbitTheme.line(scheme))

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    CanvasBackground(pan: pan, zoom: zoom)
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                        .simultaneousGesture(magnifyGesture)
                        .simultaneousGesture(
                            SpatialTapGesture(count: 2).onEnded { value in
                                addIdea(at: value.location)
                            }
                        )

                    CanvasEdges(ideas: ideas, links: links, pan: pan, zoom: zoom, selectedLinkID: selectedLinkID)
                        .allowsHitTesting(false)
                    CanvasHierarchyEdges(ideas: ideas, links: links, pan: pan, zoom: zoom)
                        .allowsHitTesting(false)
                    CanvasEdgeHitLayer(ideas: ideas, links: links, pan: pan, zoom: zoom) { linkID in
                        selectedLinkID = linkID
                        selectedIdeaID = nil
                    }
                    CanvasConnectionPreview(start: connectionStart, end: connectionEnd)
                        .allowsHitTesting(false)

                    ForEach(ideas) { idea in
                        CanvasIdeaNode(
                            idea: idea,
                            childCount: ideas.count { $0.parentID == idea.id },
                            zoom: zoom,
                            pan: pan,
                            selected: selectedIdeaID == idea.id,
                            connecting: connectionSourceID == idea.id,
                            select: {
                                selectedLinkID = nil
                                openedIdeaID = idea.id
                            },
                            connectionChanged: { start, end in
                                selectedIdeaID = idea.id; connectionSourceID = idea.id; connectionStart = start; connectionEnd = end
                            },
                            connectionEnded: { end in finishConnection(from: idea, at: end) },
                            moved: { nodeMoved(idea) }
                        )
                    }

                    canvasControls
                        .padding(18)

                }
                .clipped()
                .coordinateSpace(name: "ideaCanvas")
                .onDeleteCommand { selectedLinkID == nil ? deleteSelected() : deleteSelectedLink() }
                .onExitCommand { connectionSourceID = nil; selectedIdeaID = nil; selectedLinkID = nil }
                .accessibilityAction(named: "Create idea at viewport center") {
                    addIdea(at: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2))
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Canvas").font(.system(size: 27, weight: .semibold))
                Text("Arrange ideas, link their relationships, or overlap two cards to merge them.")
                    .font(.system(size: 13.5)).foregroundStyle(OrbitTheme.ink2(scheme))
            }
            Spacer()
            if selectedLinkID != nil {
                Button(role: .destructive) { deleteSelectedLink() } label: { Label("Delete link", systemImage: "link.badge.minus") }
                    .buttonStyle(.bordered)
            }
            if selectedIdeaID != nil {
                Button(role: .destructive) { deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.bordered)
            }
            Button { addIdea() } label: { Label("New idea", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
        }
        .padding(.horizontal, 32).frame(height: 96)
    }

    private var canvasControls: some View {
        HStack(spacing: 2) {
            canvasControl("plus", help: "Zoom in") { setZoom(zoom * 1.2) }
            canvasControl("minus", help: "Zoom out") { setZoom(zoom / 1.2) }
            Divider().frame(height: 18).padding(.horizontal, 3)
            canvasControl("arrow.up.left.and.arrow.down.right", help: "Reset viewport") { resetViewport() }
        }
        .padding(5).background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitTheme.line(scheme)) }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3).fixedSize()
    }

    private func canvasControl(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.plain).background(Color.clear, in: RoundedRectangle(cornerRadius: 6)).help(help)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                pan = CGSize(width: committedPan.width + value.translation.width,
                             height: committedPan.height + value.translation.height)
            }
            .onEnded { _ in committedPan = pan }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(committedZoom * value.magnification, 0.2), 1.75) }
            .onEnded { _ in committedZoom = zoom }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.2), 1.75)
        committedZoom = zoom
    }

    private func resetViewport() {
        withAnimation(.easeOut(duration: 0.22)) {
            pan = .zero; committedPan = .zero; zoom = 1; committedZoom = 1
        }
    }

    private func addIdea(at screenPoint: CGPoint? = nil) {
        let screen = screenPoint ?? CGPoint(x: 520, y: 300)
        let world = CGPoint(x: (screen.x - pan.width) / zoom, y: (screen.y - pan.height) / zoom)
        let idea = Idea(title: "Untitled", content: "", canvasX: world.x, canvasY: world.y)
        modelContext.insert(idea); try? modelContext.save(); selectedIdeaID = idea.id
    }

    private func tileUnplacedIdeas() {
        let unplaced = ideas.filter { $0.canvasX == nil || $0.canvasY == nil }
        guard !unplaced.isEmpty else { return }
        let placedBottom = ideas.compactMap { idea -> Double? in
            guard let y = idea.canvasY else { return nil }
            return y + 90
        }.max() ?? 120
        for (index, idea) in unplaced.enumerated() {
            idea.canvasX = 190 + Double(index % 3) * 290
            idea.canvasY = placedBottom + 150 + Double(index / 3) * 170
        }
        try? modelContext.save()
    }

    private func finishConnection(from source: Idea, at screenPoint: CGPoint) {
        let target = ideas.first { idea in
            guard idea.id != source.id, let x = idea.canvasX, let y = idea.canvasY else { return false }
            return CGRect(x: x * zoom + pan.width - 112 * zoom, y: y * zoom + pan.height - 59 * zoom, width: 224 * zoom, height: 118 * zoom).insetBy(dx: -10, dy: -10).contains(screenPoint)
        }
        defer { connectionSourceID = nil; connectionStart = nil; connectionEnd = nil; selectedIdeaID = nil }
        guard let target else { return }
        let duplicate = links.contains { $0.sourceID == source.id && $0.targetID == target.id }
        if !duplicate { modelContext.insert(IdeaLink(ideaAID: source.id, ideaBID: target.id)) }
        try? modelContext.save()
    }

    private func nodeMoved(_ idea: Idea) {
        try? modelContext.save()
        guard let x = idea.canvasX, let y = idea.canvasY else { return }
        let movedRect = CGRect(x: x - 112, y: y - 59, width: 224, height: 118)
        let candidate = ideas.filter { $0.id != idea.id }.compactMap { target -> (Idea, CGFloat)? in
            guard let targetX = target.canvasX, let targetY = target.canvasY else { return nil }
            let targetRect = CGRect(x: targetX - 112, y: targetY - 59, width: 224, height: 118)
            let overlap = movedRect.intersection(targetRect)
            guard !overlap.isNull else { return nil }
            return (target, (overlap.width * overlap.height) / (movedRect.width * movedRect.height))
        }.max { $0.1 < $1.1 }
        if let candidate, candidate.1 > 0.5 {
            mergeCandidate = MergeCandidate(draggedID: idea.id, targetID: candidate.0.id)
        }
    }

    private func deleteSelected() {
        guard let selectedIdeaID, let idea = ideas.first(where: { $0.id == selectedIdeaID }) else { return }
        links.filter { $0.ideaAID == selectedIdeaID || $0.ideaBID == selectedIdeaID }.forEach(modelContext.delete)
        ideas.filter { $0.parentID == selectedIdeaID }.forEach { $0.parentID = nil }
        modelContext.delete(idea); try? modelContext.save()
        self.selectedIdeaID = nil; connectionSourceID = nil
    }

    private func deleteSelectedLink() {
        guard let selectedLinkID, let link = links.first(where: { $0.id == selectedLinkID }) else { return }
        modelContext.delete(link)
        try? modelContext.save()
        self.selectedLinkID = nil
    }

    private func merge(dragged: Idea, into target: Idea) {
        let removedID = dragged.id
        let targetID = target.id
        let outgoingTargets = Set(links.filter { $0.sourceID == removedID }.map(\.targetID)).subtracting([targetID])
        let incomingSources = Set(links.filter { $0.targetID == removedID }.map(\.sourceID)).subtracting([targetID])

        if target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { target.title = dragged.title }
        if !dragged.content.isEmpty {
            target.content = target.content.isEmpty ? dragged.content : "\(target.content)\n\n---\n\n\(dragged.content)"
        }
        target.tags = Array(Set(target.tags + dragged.tags)).sorted()
        target.updatedAt = .now

        if target.parentID == removedID { target.parentID = dragged.parentID }
        ideas.filter { $0.parentID == removedID && $0.id != targetID }.forEach { $0.parentID = targetID }

        links.filter { $0.ideaAID == removedID || $0.ideaBID == removedID }.forEach(modelContext.delete)
        for neighbor in outgoingTargets {
            let exists = links.contains { $0.sourceID == targetID && $0.targetID == neighbor }
            if !exists { modelContext.insert(IdeaLink(ideaAID: targetID, ideaBID: neighbor)) }
        }
        for neighbor in incomingSources {
            let exists = links.contains { $0.sourceID == neighbor && $0.targetID == targetID }
            if !exists { modelContext.insert(IdeaLink(ideaAID: neighbor, ideaBID: targetID)) }
        }
        modelContext.delete(dragged); try? modelContext.save()
        selectedIdeaID = targetID; connectionSourceID = nil; mergeCandidate = nil
    }
}

private struct CanvasBackground: View {
    @Environment(\.colorScheme) private var scheme
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(8, 24 * zoom)
            let startX = pan.width.truncatingRemainder(dividingBy: spacing)
            let startY = pan.height.truncatingRemainder(dividingBy: spacing)
            for x in stride(from: startX, through: size.width, by: spacing) {
                for y in stride(from: startY, through: size.height, by: spacing) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                 with: .color(OrbitTheme.ink3(scheme).opacity(0.28)))
                }
            }
        }
        .background(OrbitTheme.canvas(scheme))
    }
}

private struct CanvasEdges: View {
    let ideas: [Idea]
    let links: [IdeaLink]
    let pan: CGSize
    let zoom: CGFloat
    let selectedLinkID: UUID?

    var body: some View {
        Canvas { context, _ in
            let ideasByID = Dictionary(uniqueKeysWithValues: ideas.map { ($0.id, $0) })
            for link in links {
                guard let a = ideasByID[link.ideaAID], let b = ideasByID[link.ideaBID],
                      let geometry = ideaLinkGeometry(from: a, to: b, pan: pan, zoom: zoom) else { continue }
                let selected = selectedLinkID == link.id
                let color = OrbitTheme.accent.opacity(selected ? 0.9 : 0.42)
                context.stroke(geometry.path, with: .color(color),
                               style: StrokeStyle(lineWidth: max(selected ? 2.8 : 1, (selected ? 2.8 : 1.6) * zoom), lineCap: .round))
                context.fill(geometry.arrow, with: .color(color))
            }
        }
    }
}

private struct CanvasEdgeHitLayer: View {
    let ideas: [Idea]
    let links: [IdeaLink]
    let pan: CGSize
    let zoom: CGFloat
    let select: (UUID) -> Void

    var body: some View {
        let ideasByID = Dictionary(uniqueKeysWithValues: ideas.map { ($0.id, $0) })
        ZStack {
            ForEach(links) { link in
                if let a = ideasByID[link.ideaAID], let b = ideasByID[link.ideaBID],
                   let geometry = ideaLinkGeometry(from: a, to: b, pan: pan, zoom: zoom) {
                    geometry.path.stroke(Color.black.opacity(0.001), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .contentShape(geometry.path.strokedPath(StrokeStyle(lineWidth: 14, lineCap: .round)))
                        .onTapGesture { select(link.id) }
                        .help("Select link")
                }
            }
        }
    }
}

private struct CanvasHierarchyEdges: View {
    let ideas: [Idea]
    let links: [IdeaLink]
    let pan: CGSize
    let zoom: CGFloat

    var body: some View {
        Canvas { context, _ in
            let ideasByID = Dictionary(uniqueKeysWithValues: ideas.map { ($0.id, $0) })
            for child in ideas {
                guard let parentID = child.parentID,
                      let parent = ideasByID[parentID],
                      !links.contains(where: { $0.sourceID == parentID && $0.targetID == child.id }),
                      let geometry = ideaLinkGeometry(from: parent, to: child, pan: pan, zoom: zoom) else { continue }
                let color = OrbitTheme.accent.opacity(0.25)
                context.stroke(
                    geometry.path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: max(1, 1.4 * zoom), lineCap: .round, dash: [5, 5])
                )
                context.fill(geometry.arrow, with: .color(color))
            }
        }
    }
}

private struct IdeaLinkGeometry {
    let path: Path
    let arrow: Path
}

private func ideaLinkGeometry(from a: Idea, to b: Idea, pan: CGSize, zoom: CGFloat) -> IdeaLinkGeometry? {
    guard let ax = a.canvasX, let ay = a.canvasY, let bx = b.canvasX, let by = b.canvasY else { return nil }
    let aCenter = CGPoint(x: ax * zoom + pan.width, y: ay * zoom + pan.height)
    let bCenter = CGPoint(x: bx * zoom + pan.width, y: by * zoom + pan.height)
    let nodeSize = CGSize(width: 224 * zoom, height: 118 * zoom)
    func borderPoint(from center: CGPoint, toward target: CGPoint) -> CGPoint {
        let dx = target.x - center.x, dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let scale = min((nodeSize.width / 2) / max(abs(dx), 0.001), (nodeSize.height / 2) / max(abs(dy), 0.001))
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }
    let start = borderPoint(from: aCenter, toward: bCenter)
    let end = borderPoint(from: bCenter, toward: aCenter)
    let bend = max(38 * zoom, abs(end.x - start.x) * 0.42)
    let control2 = CGPoint(x: end.x - (end.x >= start.x ? bend : -bend), y: end.y)
    var path = Path()
    path.move(to: start)
    path.addCurve(to: end,
                  control1: CGPoint(x: start.x + (end.x >= start.x ? bend : -bend), y: start.y),
                  control2: control2)

    let angle = atan2(end.y - control2.y, end.x - control2.x)
    let arrowLength = max(7, 9 * zoom)
    let arrowWidth = max(4, 5 * zoom)
    let base = CGPoint(x: end.x - cos(angle) * arrowLength, y: end.y - sin(angle) * arrowLength)
    let normal = CGPoint(x: -sin(angle) * arrowWidth, y: cos(angle) * arrowWidth)
    var arrow = Path()
    arrow.move(to: end)
    arrow.addLine(to: CGPoint(x: base.x + normal.x, y: base.y + normal.y))
    arrow.addLine(to: CGPoint(x: base.x - normal.x, y: base.y - normal.y))
    arrow.closeSubpath()
    return IdeaLinkGeometry(path: path, arrow: arrow)
}

struct CanvasConnectionPreview: View {
    let start: CGPoint?; let end: CGPoint?
    var body: some View {
        Canvas { context, _ in
            guard let start, let end else { return }
            let bend = max(34, abs(end.x - start.x) * 0.4)
            var path = Path(); path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: start.x + (end.x >= start.x ? bend : -bend), y: start.y), control2: CGPoint(x: end.x - (end.x >= start.x ? bend : -bend), y: end.y))
            context.stroke(path, with: .color(OrbitTheme.accent.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
        }
    }
}

private struct CanvasIdeaNode: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var idea: Idea
    let childCount: Int
    let zoom: CGFloat
    let pan: CGSize
    let selected: Bool
    let connecting: Bool
    let select: () -> Void
    let connectionChanged: (CGPoint, CGPoint) -> Void
    let connectionEnded: (CGPoint) -> Void
    let moved: () -> Void
    @State private var dragOrigin: CGPoint?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if idea.pinned { Image(systemName: "pin.fill").foregroundStyle(OrbitTheme.accent) }
                Text(idea.title.isEmpty ? "Untitled" : idea.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if childCount > 0 {
                    Label("\(childCount)", systemImage: "doc.on.doc")
                        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(OrbitTheme.ink3(scheme))
                }
            }
            Text(idea.contentExcerpt.isEmpty ? "Nothing written yet." : idea.contentExcerpt)
                .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(3)
            HStack(spacing: 5) {
                ForEach(idea.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .padding(13).frame(width: 224, height: 118, alignment: .topLeading)
        .background(OrbitTheme.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? OrbitTheme.accent : OrbitTheme.line(scheme), lineWidth: selected ? 1.7 : 1) }
        .overlay { connectionPorts }
        .shadow(color: .black.opacity(selected ? 0.09 : 0.055), radius: selected ? 8 : 5, y: 2)
        .onHover { hovering = $0 }
        .scaleEffect(zoom)
        .position(x: (idea.canvasX ?? 200) * zoom + pan.width, y: (idea.canvasY ?? 200) * zoom + pan.height)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = CGPoint(x: idea.canvasX ?? 0, y: idea.canvasY ?? 0) }
                    guard let origin = dragOrigin else { return }
                    idea.canvasX = origin.x + value.translation.width / zoom
                    idea.canvasY = origin.y + value.translation.height / zoom
                }
                .onEnded { _ in dragOrigin = nil; moved() }
        )
        .simultaneousGesture(TapGesture().onEnded(select))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Idea: \(idea.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("Drag a side port onto another idea to link")
    }

    @ViewBuilder private var connectionPorts: some View {
        if hovering || connecting {
            ZStack {
                port(offset: CGPoint(x: 0, y: -59)).offset(y: -59)
                port(offset: CGPoint(x: 112, y: 0)).offset(x: 112)
                port(offset: CGPoint(x: 0, y: 59)).offset(y: 59)
                port(offset: CGPoint(x: -112, y: 0)).offset(x: -112)
            }
        }
    }

    private func port(offset: CGPoint) -> some View {
        let center = CGPoint(x: (idea.canvasX ?? 200) * zoom + pan.width + offset.x * zoom, y: (idea.canvasY ?? 200) * zoom + pan.height + offset.y * zoom)
        return Circle().fill(OrbitTheme.surface(scheme))
            .overlay { Circle().stroke(OrbitTheme.accent, lineWidth: 2) }
            .frame(width: 13, height: 13).contentShape(Circle().inset(by: -6))
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("ideaCanvas")).onChanged { value in
                connectionChanged(center, value.location)
            }.onEnded { value in connectionEnded(value.location) })
            .accessibilityLabel("Drag to connect idea")
    }
}

private struct MergeIdeasSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let dragged: Idea
    let target: Idea
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Merge ideas?").font(.system(size: 21, weight: .semibold))
                Text("The dropped idea will be folded into the target. Tags and connections are preserved.")
                    .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
            }
            HStack(spacing: 12) {
                preview(dragged, label: "MERGE")
                Image(systemName: "arrow.right").foregroundStyle(OrbitTheme.ink3(scheme))
                preview(target, label: "KEEP")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Merge") { confirm(); dismiss() }.buttonStyle(.borderedProminent).tint(OrbitTheme.accent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 560)
    }

    private func preview(_ idea: Idea, label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(OrbitTheme.ink3(scheme))
            Text(idea.title.isEmpty ? "Untitled" : idea.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Text(idea.content.isEmpty ? "Nothing written yet." : idea.content).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(3)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading).orbitCard()
    }
}
