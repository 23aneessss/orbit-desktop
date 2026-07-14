import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \OrbitTask.createdAt, order: .reverse) private var tasks: [OrbitTask]
    @Query private var allSteps: [OrbitTaskStep]
    @Query private var allLinks: [StepLink]
    @Query private var allStrokes: [BoardStroke]
    @Query private var allNotes: [BoardNote]

    @AppStorage("orbit:tasks-seeded") private var tasksSeeded = false
    @AppStorage("orbit:tasks-mode") private var tasksMode = "list"
    @State private var selectedTaskID: UUID?

    var body: some View {
        if let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) {
            TaskDetailView(
                task: task,
                steps: allSteps.filter { $0.taskID == selectedTaskID },
                links: allLinks.filter { $0.taskID == selectedTaskID },
                strokes: allStrokes.filter { $0.taskID == selectedTaskID },
                notes: allNotes.filter { $0.taskID == selectedTaskID },
                close: { self.selectedTaskID = nil }
            )
        } else if tasksMode == "board" {
            GlobalTaskBoardView(
                tasks: tasks,
                steps: allSteps,
                strokes: allStrokes.filter { $0.taskID == nil },
                notes: allNotes.filter { $0.taskID == nil },
                showList: { tasksMode = "list" },
                create: { createTask(at: $0) },
                open: { selectedTaskID = $0.id },
                delete: deleteTask
            ).task { seedTasksIfNeeded() }
        } else {
            taskList
                .task { seedTasksIfNeeded() }
        }
    }

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Tasks").font(.system(size: 27, weight: .semibold))
                        Text("Simple actions and connected workflows, kept in one place.")
                            .font(.system(size: 13.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    Spacer()
                    Picker("View", selection: $tasksMode) { Text("List").tag("list"); Text("Board").tag("board") }
                        .pickerStyle(.segmented).frame(width: 150)
                    Button { createTask() } label: { Label("New task", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
                }

                taskSection("Open", tasks.filter { !$0.done })
                if tasks.contains(where: \.done) { taskSection("Completed", tasks.filter(\.done)) }
            }
            .padding(32).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(OrbitTheme.canvas(scheme))
    }

    @ViewBuilder private func taskSection(_ title: String, _ items: [OrbitTask]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 14.5, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            steps: allSteps.filter { $0.taskID == task.id },
                            open: { selectedTaskID = task.id },
                            toggle: { toggleTask(task) },
                            delete: { deleteTask(task) }
                        )
                        if index < items.count - 1 { Divider().padding(.leading, 52) }
                    }
                }.orbitCard()
            }
        }
    }

    private func createTask(at point: CGPoint? = nil) {
        let task = OrbitTask(title: "Untitled task", canvasX: point.map { Double($0.x) }, canvasY: point.map { Double($0.y) })
        modelContext.insert(task); try? modelContext.save(); selectedTaskID = task.id
    }

    private func toggleTask(_ task: OrbitTask) {
        guard allSteps.allSatisfy({ $0.taskID != task.id }) else { selectedTaskID = task.id; return }
        task.done.toggle(); task.completedAt = task.done ? .now : nil; try? modelContext.save()
    }

    private func deleteTask(_ task: OrbitTask) {
        let id = task.id
        allLinks.filter { $0.taskID == id }.forEach(modelContext.delete)
        allStrokes.filter { $0.taskID == id }.forEach(modelContext.delete)
        allNotes.filter { $0.taskID == id }.forEach(modelContext.delete)
        allSteps.filter { $0.taskID == id }.forEach(modelContext.delete)
        modelContext.delete(task); try? modelContext.save()
    }


    private func seedTasksIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "orbit:demo-data-enabled") else { return }
        guard !tasksSeeded else { return }
        guard tasks.isEmpty else { tasksSeeded = true; return }
        let launch = OrbitTask(title: "Launch Orbit desktop", note: "Ship the first native, local-first release.")
        let review = OrbitTask(title: "Review weekly priorities", note: "Choose the three outcomes that matter most.")
        modelContext.insert(launch); modelContext.insert(review)

        let research = OrbitTaskStep(taskID: launch.id, title: "Validate native architecture", done: true, orderIndex: 0, canvasX: 190, canvasY: 170)
        let build = OrbitTaskStep(taskID: launch.id, title: "Build product slices", orderIndex: 1, canvasX: 500, canvasY: 170)
        let release = OrbitTaskStep(taskID: launch.id, title: "Prepare release", orderIndex: 2, canvasX: 810, canvasY: 170)
        let ideas = OrbitTaskStep(taskID: launch.id, parentID: build.id, title: "Ideas and canvas", done: true, orderIndex: 0)
        let workflows = OrbitTaskStep(taskID: launch.id, parentID: build.id, title: "Tasks and workflows", orderIndex: 1)
        [research, build, release, ideas, workflows].forEach(modelContext.insert)
        modelContext.insert(StepLink(taskID: launch.id, sourceID: research.id, targetID: build.id))
        modelContext.insert(StepLink(taskID: launch.id, sourceID: build.id, targetID: release.id))
        TaskCompletionService.recompute(task: launch, steps: [research, build, release, ideas, workflows])
        try? modelContext.save()
        tasksSeeded = true
    }
}

private struct GlobalTaskBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    let tasks: [OrbitTask]
    let steps: [OrbitTaskStep]
    let strokes: [BoardStroke]
    let notes: [BoardNote]
    let showList: () -> Void
    let create: (CGPoint?) -> Void
    let open: (OrbitTask) -> Void
    let delete: (OrbitTask) -> Void

    @State private var pan = CGSize.zero
    @State private var committedPan = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var tool: WorkflowTool = .hand
    @State private var inkColor = "#8B5CF6"
    @State private var activeStroke: [[Double]] = []
    @State private var selectedNoteID: UUID?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                WorkflowBackground(pan: pan, zoom: zoom).contentShape(Rectangle())
                    .gesture(tool == .hand ? panGesture : nil).simultaneousGesture(magnifyGesture)
                    .onTapGesture(count: 2, coordinateSpace: .local) { location in
                        if tool == .hand { create(worldPoint(location)) }
                    }
                WorkflowInkLayer(strokes: strokes, preview: activeStroke, previewColor: inkColor, pan: pan, zoom: zoom).allowsHitTesting(false)
                ForEach(notes) { note in
                    WorkflowStickyNote(note: note, zoom: zoom, pan: pan, selected: selectedNoteID == note.id) {
                        selectedNoteID = note.id
                    } moved: { save() }
                }
                ForEach(tasks) { task in
                    TaskBoardNode(task: task, childSteps: steps.filter { $0.taskID == task.id }, zoom: zoom, pan: pan, open: { open(task) }, toggle: { toggle(task) }, delete: { delete(task) }, moved: save)
                }
                if tool != .hand {
                    Color.clear.contentShape(Rectangle()).gesture(tool == .pen ? inkGesture : nil)
                        .onTapGesture(coordinateSpace: .local) { location in if tool == .note { addNote(at: location) } }
                }
                boardToolbar
            }
            .clipped()
            .task { tileUnplaced(in: proxy.size) }
            .onDeleteCommand { deleteSelectedNote() }
        }
    }

    private var boardToolbar: some View {
        HStack(spacing: 6) {
            ForEach(WorkflowTool.allCases) { item in
                Button { tool = item } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).background(tool == item ? OrbitTheme.accentSoft(scheme) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .help(item.title).accessibilityLabel(item.title)
            }
            Divider().frame(height: 22).padding(.horizontal, 3)
            ForEach(annotationColors, id: \.self) { color in
                Button { inkColor = color } label: {
                    Circle().fill(Color(hex: color)).frame(width: 15, height: 15)
                        .overlay { Circle().stroke(.primary.opacity(inkColor == color ? 0.65 : 0), lineWidth: 2).padding(-2) }
                }.buttonStyle(.plain).frame(width: 22, height: 28)
            }
            Button { undoAnnotation() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28) }.buttonStyle(.plain).help("Undo annotation")
            Divider().frame(height: 22).padding(.horizontal, 3)
            Picker("View", selection: Binding(get: { "board" }, set: { if $0 == "list" { showList() } })) {
                Text("List").tag("list"); Text("Board").tag("board")
            }.labelsHidden().pickerStyle(.segmented).frame(width: 128)
            Button { create(nil) } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(OrbitTheme.accent).help("New task")
        }
        .padding(7).background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitTheme.line(scheme)) }
        .shadow(color: .black.opacity(0.07), radius: 7, y: 3).fixedSize().padding(18)
    }

    private var annotationColors: [String] { ["#F59E0B", "#3D6DF2", "#10B981", "#F43F5E", "#8B5CF6", "#64748B"] }
    private var panGesture: some Gesture { DragGesture(minimumDistance: 1).onChanged { value in pan = CGSize(width: committedPan.width + value.translation.width, height: committedPan.height + value.translation.height) }.onEnded { _ in committedPan = pan } }
    private var magnifyGesture: some Gesture { MagnifyGesture().onChanged { value in zoom = min(max(committedZoom * value.magnification, 0.25), 1.75) }.onEnded { _ in committedZoom = zoom } }
    private var inkGesture: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            let point = worldPoint(value.location)
            if let last = activeStroke.last, pow(last[0] - point.x, 2) + pow(last[1] - point.y, 2) < 4 { return }
            activeStroke.append([point.x, point.y])
        }.onEnded { _ in
            if activeStroke.count > 1 { modelContext.insert(BoardStroke(points: activeStroke, color: inkColor)) }
            activeStroke = []; save()
        }
    }
    private func worldPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - pan.width) / zoom, y: (point.y - pan.height) / zoom) }
    private func addNote(at point: CGPoint) { let world = worldPoint(point); modelContext.insert(BoardNote(color: annotationPaperColor(inkColor), canvasX: world.x, canvasY: world.y)); save() }
    private func toggle(_ task: OrbitTask) { guard !steps.contains(where: { $0.taskID == task.id }) else { open(task); return }; task.done.toggle(); task.completedAt = task.done ? .now : nil; save() }
    private func tileUnplaced(in size: CGSize) {
        for (index, task) in tasks.filter({ $0.canvasX == nil || $0.canvasY == nil }).enumerated() {
            task.canvasX = 170 + Double(index % 4) * 270; task.canvasY = 170 + Double(index / 4) * 165
        }
        save()
    }
    private func undoAnnotation() {
        let stroke = strokes.max(by: { $0.createdAt < $1.createdAt }); let note = notes.max(by: { $0.createdAt < $1.createdAt })
        if let stroke, note == nil || stroke.createdAt > note!.createdAt { modelContext.delete(stroke) } else if let note { modelContext.delete(note) }; save()
    }
    private func deleteSelectedNote() { guard let id = selectedNoteID, let note = notes.first(where: { $0.id == id }) else { return }; modelContext.delete(note); selectedNoteID = nil; save() }
    private func save() { try? modelContext.save() }
}

private struct TaskBoardNode: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var task: OrbitTask
    let childSteps: [OrbitTaskStep]
    let zoom: CGFloat; let pan: CGSize
    let open: () -> Void; let toggle: () -> Void; let delete: () -> Void; let moved: () -> Void
    @State private var origin: CGPoint?
    private var leaves: [OrbitTaskStep] { childSteps.filter { step in !childSteps.contains(where: { $0.parentID == step.id }) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: toggle) { Image(systemName: task.done ? "checkmark.circle.fill" : childSteps.isEmpty ? "circle" : "circle.dotted") }.buttonStyle(.plain).foregroundStyle(task.done ? OrbitTheme.accent : OrbitTheme.ink3(scheme))
                TextField("Task", text: $task.title).textFieldStyle(.plain).font(.system(size: 13, weight: .semibold)).onSubmit(moved)
                if !childSteps.isEmpty { Button(action: open) { Image(systemName: "arrow.up.right") }.buttonStyle(.plain).foregroundStyle(OrbitTheme.accent).help("Open workflow") }
                Menu { Button("Delete", role: .destructive, action: delete) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }
            if childSteps.isEmpty {
                Text(task.note.isEmpty ? "No note" : task.note).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(2)
            } else {
                ProgressView(value: Double(leaves.filter(\.done).count), total: Double(max(leaves.count, 1))).tint(OrbitTheme.accent)
                Text("\(leaves.filter(\.done).count) of \(leaves.count) steps").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink2(scheme))
            }
        }
        .padding(15).frame(width: 240, height: 125, alignment: .topLeading)
        .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(OrbitTheme.line(scheme)) }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3).scaleEffect(zoom)
        .position(x: (task.canvasX ?? 170) * zoom + pan.width, y: (task.canvasY ?? 170) * zoom + pan.height)
        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
            if origin == nil { origin = CGPoint(x: task.canvasX ?? 0, y: task.canvasY ?? 0) }; guard let origin else { return }
            task.canvasX = origin.x + value.translation.width / zoom; task.canvasY = origin.y + value.translation.height / zoom
        }.onEnded { _ in origin = nil; moved() })
        .simultaneousGesture(TapGesture(count: 2).onEnded(open))
    }
}

private struct TaskRow: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var task: OrbitTask
    let steps: [OrbitTaskStep]
    let open: () -> Void
    let toggle: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button(action: toggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(task.done ? OrbitTheme.accent : OrbitTheme.ink3(scheme))
            }.buttonStyle(.plain)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 13.5, weight: .medium)).strikethrough(task.done)
                    if !task.note.isEmpty { Text(task.note).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme)).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !steps.isEmpty {
                let leafSteps = steps.filter { step in !steps.contains(where: { $0.parentID == step.id }) }
                Text("\(leafSteps.filter(\.done).count)/\(leafSteps.count)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 4).background(OrbitTheme.accentSoft(scheme), in: Capsule())
                Text("workflow").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.accent)
            }
            Menu { Button("Delete", systemImage: "trash", role: .destructive, action: delete) } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 16).frame(minHeight: 62)
    }
}

private struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Bindable var task: OrbitTask
    let steps: [OrbitTaskStep]
    let links: [StepLink]
    let strokes: [BoardStroke]
    let notes: [BoardNote]
    let close: () -> Void

    @AppStorage("orbit:task-detail-mode") private var mode = "steps"
    @State private var newStepTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: close) { Label("Tasks", systemImage: "chevron.left") }.buttonStyle(.plain)
                TextField("Task title", text: $task.title).textFieldStyle(.plain).font(.system(size: 18, weight: .semibold))
                    .onSubmit(save)
                Spacer()
                Picker("View", selection: $mode) { Text("Steps").tag("steps"); Text("Workflow").tag("workflow") }
                    .pickerStyle(.segmented).frame(width: 190)
            }
            .padding(.horizontal, 28).frame(height: 58)
            Divider().overlay(OrbitTheme.line(scheme))

            if mode == "workflow" {
                WorkflowCanvasView(task: task, steps: steps, links: links, strokes: strokes, notes: notes)
            } else {
                stepsView
            }
        }
        .background(OrbitTheme.canvas(scheme))
    }

    private var stepsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Steps").font(.system(size: 22, weight: .semibold))
                    Text("Composite steps complete automatically when every child is done.")
                        .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                }
                VStack(spacing: 0) {
                    ForEach(rootSteps) { step in
                        StepBlock(
                            step: step,
                            allSteps: steps,
                            toggle: { toggle(step) },
                            toggleChild: { toggle($0) },
                            addChild: { addChild(to: step) },
                            delete: { delete(step) }
                        )
                        if step.id != rootSteps.last?.id { Divider().padding(.leading, 48) }
                    }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(OrbitTheme.ink3(scheme)).frame(width: 28)
                        TextField("Add a step", text: $newStepTitle).textFieldStyle(.plain).onSubmit(addRootStep)
                    }.padding(.horizontal, 16).frame(height: 52)
                }.orbitCard()
            }
            .padding(32).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var rootSteps: [OrbitTaskStep] { steps.filter { $0.parentID == nil }.sorted { $0.orderIndex < $1.orderIndex } }

    private func addRootStep() {
        let title = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        modelContext.insert(OrbitTaskStep(taskID: task.id, title: title, orderIndex: rootSteps.count))
        newStepTitle = ""; recompute()
    }

    private func addChild(to step: OrbitTaskStep) {
        let children = steps.filter { $0.parentID == step.id }
        modelContext.insert(OrbitTaskStep(taskID: task.id, parentID: step.id, title: "New sub-step", orderIndex: children.count))
        recompute()
    }

    private func toggle(_ step: OrbitTaskStep) {
        guard !steps.contains(where: { $0.parentID == step.id }) else { return }
        step.done.toggle(); recompute()
    }

    private func delete(_ step: OrbitTaskStep) {
        var ids: Set<UUID> = [step.id]
        var changed = true
        while changed {
            changed = false
            for candidate in steps where candidate.parentID.map(ids.contains) == true && !ids.contains(candidate.id) {
                ids.insert(candidate.id); changed = true
            }
        }
        links.filter { ids.contains($0.sourceID) || ids.contains($0.targetID) }.forEach(modelContext.delete)
        steps.filter { ids.contains($0.id) }.forEach(modelContext.delete)
        recompute(excluding: ids)
    }

    private func recompute(excluding ids: Set<UUID> = []) {
        TaskCompletionService.recompute(task: task, steps: steps.filter { !ids.contains($0.id) }); save()
    }

    private func save() { try? modelContext.save() }
}

private struct StepBlock: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var step: OrbitTaskStep
    let allSteps: [OrbitTaskStep]
    let toggle: () -> Void
    let toggleChild: (OrbitTaskStep) -> Void
    let addChild: () -> Void
    let delete: () -> Void

    private var children: [OrbitTaskStep] { allSteps.filter { $0.parentID == step.id }.sorted { $0.orderIndex < $1.orderIndex } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: toggle) { Image(systemName: step.done ? "checkmark.circle.fill" : children.isEmpty ? "circle" : "circle.dotted") }
                    .buttonStyle(.plain).font(.system(size: 19)).foregroundStyle(step.done ? OrbitTheme.accent : OrbitTheme.ink3(scheme))
                TextField("Step", text: $step.title).textFieldStyle(.plain).font(.system(size: 13.5, weight: .medium))
                if !children.isEmpty {
                    Text("\(children.filter(\.done).count)/\(children.count)").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(OrbitTheme.ink2(scheme))
                }
                Button(action: addChild) { Image(systemName: "plus") }.buttonStyle(.plain).help("Add sub-step")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }.buttonStyle(.plain).help("Delete step")
            }.padding(.horizontal, 16).frame(height: 52)
            ForEach(children) { child in
                HStack(spacing: 10) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(OrbitTheme.ink3(scheme))
                    Button { toggleChild(child) } label: {
                        Image(systemName: child.done ? "checkmark.circle.fill" : "circle").foregroundStyle(child.done ? OrbitTheme.accent : OrbitTheme.ink3(scheme))
                    }.buttonStyle(.plain)
                    TextField("Sub-step", text: Bindable(child).title).textFieldStyle(.plain)
                }.font(.system(size: 12.5)).padding(.leading, 44).padding(.trailing, 16).frame(height: 42)
                    .background(OrbitTheme.sunken(scheme).opacity(0.42))
            }
        }
    }
}

private struct WorkflowCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Bindable var task: OrbitTask
    let steps: [OrbitTaskStep]
    let links: [StepLink]
    let strokes: [BoardStroke]
    let notes: [BoardNote]

    @State private var pan = CGSize.zero
    @State private var committedPan = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var selectedID: UUID?
    @State private var selectedLinkID: UUID?
    @State private var sourceID: UUID?
    @State private var connectionStart: CGPoint?
    @State private var connectionEnd: CGPoint?
    @State private var selectedNoteID: UUID?
    @State private var scopeID: UUID?
    @State private var tool: WorkflowTool = .hand
    @State private var inkColor = "#8B5CF6"
    @State private var activeStroke: [[Double]] = []

    private var visibleSteps: [OrbitTaskStep] { steps.filter { $0.parentID == scopeID } }
    private var visibleStrokes: [BoardStroke] { strokes.filter { $0.scopeID == scopeID } }
    private var visibleNotes: [BoardNote] { notes.filter { $0.scopeID == scopeID } }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                WorkflowBackground(pan: pan, zoom: zoom).contentShape(Rectangle())
                    .gesture(tool == .hand ? panGesture : nil)
                    .simultaneousGesture(magnifyGesture)
                WorkflowInkLayer(strokes: visibleStrokes, preview: activeStroke, previewColor: inkColor, pan: pan, zoom: zoom)
                    .allowsHitTesting(false)
                WorkflowEdges(steps: visibleSteps, links: links, pan: pan, zoom: zoom, selectedLinkID: selectedLinkID).allowsHitTesting(false)
                WorkflowEdgeHitLayer(steps: visibleSteps, links: links, pan: pan, zoom: zoom) { linkID in
                    selectedLinkID = linkID
                    selectedID = nil
                    selectedNoteID = nil
                }
                CanvasConnectionPreview(start: connectionStart, end: connectionEnd).allowsHitTesting(false)
                ForEach(visibleNotes) { note in
                    WorkflowStickyNote(note: note, zoom: zoom, pan: pan, selected: selectedNoteID == note.id) {
                        selectedNoteID = note.id; selectedID = nil
                    } moved: { save() }
                }
                ForEach(visibleSteps) { step in
                    WorkflowNode(
                        step: step,
                        hasChildren: steps.contains { $0.parentID == step.id },
                        zoom: zoom,
                        pan: pan,
                        selected: selectedID == step.id,
                        connecting: sourceID == step.id,
                        select: {
                            selectedLinkID = nil
                            if steps.contains(where: { $0.parentID == step.id }) { enter(step) }
                            else { selectedID = step.id }
                        },
                        connectionChanged: { start, end in selectedLinkID = nil; selectedID = step.id; sourceID = step.id; connectionStart = start; connectionEnd = end },
                        connectionEnded: { end in finishConnection(from: step, at: end) },
                        toggle: { toggle(step) },
                        open: { enter(step) },
                        moved: save
                    )
                }
                if tool != .hand {
                    Color.clear.contentShape(Rectangle())
                        .gesture(tool == .pen ? inkGesture : nil)
                        .onTapGesture(coordinateSpace: .local) { location in
                            if tool == .note { addNote(at: location) }
                        }
                }
                workflowToolbar
            }
            .clipped()
            .coordinateSpace(name: "workflowCanvas")
            .onDeleteCommand { deleteSelected() }
            .onExitCommand { if scopeID != nil { leaveScope() } else { tool = .hand } }
        }
    }

    private var workflowToolbar: some View {
        HStack(spacing: 6) {
            Button { leaveScope() } label: { Image(systemName: "house").frame(width: 28, height: 28) }.buttonStyle(.plain).disabled(scopeID == nil)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(OrbitTheme.ink3(scheme))
            Text(scopeID.flatMap { id in steps.first(where: { $0.id == id })?.title } ?? "Workflow")
                .font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
            Divider().frame(height: 22).padding(.horizontal, 3)
            ForEach(WorkflowTool.allCases) { item in
                Button { tool = item } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).background(tool == item ? OrbitTheme.accentSoft(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .help(item.title).accessibilityLabel(item.title)
            }
            Divider().frame(height: 22).padding(.horizontal, 3)
            ForEach(["#F59E0B", "#3D6DF2", "#10B981", "#F43F5E", "#8B5CF6", "#64748B"], id: \.self) { color in
                Button { inkColor = color } label: {
                    Circle().fill(Color(hex: color)).frame(width: 15, height: 15)
                        .overlay { Circle().stroke(.primary.opacity(inkColor == color ? 0.65 : 0), lineWidth: 2).padding(-2) }
                }.buttonStyle(.plain).frame(width: 22, height: 28).help("Ink color")
            }
            Button { undoAnnotation() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28) }.buttonStyle(.plain).help("Undo last annotation")
            Divider().frame(height: 22).padding(.horizontal, 3)
            if selectedLinkID != nil {
                Button(role: .destructive) { deleteSelectedLink() } label: {
                    Image(systemName: "link.badge.minus").frame(width: 28, height: 28)
                }.buttonStyle(.plain).foregroundStyle(.red).help("Delete selected link")
                Divider().frame(height: 22).padding(.horizontal, 3)
            }
            Button { addStep() } label: { Label("Add step", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.small).tint(OrbitTheme.accent)
        }
        .padding(7).background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(OrbitTheme.line(scheme)) }
        .shadow(color: .black.opacity(0.07), radius: 7, y: 3).fixedSize().padding(18)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1).onChanged { value in pan = CGSize(width: committedPan.width + value.translation.width, height: committedPan.height + value.translation.height) }.onEnded { _ in committedPan = pan }
    }
    private var magnifyGesture: some Gesture {
        MagnifyGesture().onChanged { value in zoom = min(max(committedZoom * value.magnification, 0.25), 1.75) }.onEnded { _ in committedZoom = zoom }
    }
    private var inkGesture: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            let point = worldPoint(value.location)
            activeStroke.append([point.x, point.y])
        }.onEnded { _ in
            guard activeStroke.count > 1 else { activeStroke = []; return }
            modelContext.insert(BoardStroke(taskID: task.id, scopeID: scopeID, points: activeStroke, color: inkColor))
            activeStroke = []; save()
        }
    }
    private func addStep() {
        let index = visibleSteps.count
        modelContext.insert(OrbitTaskStep(taskID: task.id, parentID: scopeID, title: "New step", orderIndex: index, canvasX: 190 + Double(index % 3) * 300, canvasY: 180 + Double(index / 3) * 160)); recompute()
    }
    private func addNote(at location: CGPoint) {
        let point = worldPoint(location)
        modelContext.insert(BoardNote(taskID: task.id, scopeID: scopeID, color: annotationPaperColor(inkColor), canvasX: point.x, canvasY: point.y)); save()
    }
    private func worldPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - pan.width) / zoom, y: (point.y - pan.height) / zoom)
    }
    private func enter(_ step: OrbitTaskStep) {
        let children = steps.filter { $0.parentID == step.id }
        guard !children.isEmpty else { return }
        for (index, child) in children.enumerated() where child.canvasX == nil || child.canvasY == nil {
            child.canvasX = 190 + Double(index % 3) * 300; child.canvasY = 180 + Double(index / 3) * 160
        }
        scopeID = step.id; resetViewport(); save()
    }
    private func leaveScope() { scopeID = nil; resetViewport() }
    private func resetViewport() { pan = .zero; committedPan = .zero; zoom = 1; committedZoom = 1; selectedID = nil; selectedLinkID = nil; selectedNoteID = nil; sourceID = nil; connectionStart = nil; connectionEnd = nil }
    private func finishConnection(from source: OrbitTaskStep, at screenPoint: CGPoint) {
        let target = visibleSteps.first { step in
            guard step.id != source.id, let x = step.canvasX, let y = step.canvasY else { return false }
            return CGRect(x: x * zoom + pan.width - 110 * zoom, y: y * zoom + pan.height - 35 * zoom, width: 220 * zoom, height: 70 * zoom).insetBy(dx: -10, dy: -10).contains(screenPoint)
        }
        defer { sourceID = nil; connectionStart = nil; connectionEnd = nil; selectedID = nil }
        guard let target else { return }
        if !links.contains(where: { $0.sourceID == source.id && $0.targetID == target.id }) {
            modelContext.insert(StepLink(taskID: task.id, sourceID: source.id, targetID: target.id))
        }
        save()
    }
    private func toggle(_ step: OrbitTaskStep) {
        guard !steps.contains(where: { $0.parentID == step.id }) else { return }
        step.done.toggle(); recompute()
    }
    private func deleteSelected() {
        if selectedLinkID != nil { deleteSelectedLink(); return }
        if let selectedNoteID, let note = notes.first(where: { $0.id == selectedNoteID }) {
            modelContext.delete(note); self.selectedNoteID = nil; save(); return
        }
        guard let selectedID, steps.contains(where: { $0.id == selectedID }) else { return }
        var ids: Set<UUID> = [selectedID]
        var changed = true
        while changed {
            changed = false
            for candidate in steps where candidate.parentID.map(ids.contains) == true && !ids.contains(candidate.id) {
                ids.insert(candidate.id); changed = true
            }
        }
        links.filter { ids.contains($0.sourceID) || ids.contains($0.targetID) }.forEach(modelContext.delete)
        steps.filter { ids.contains($0.id) }.forEach(modelContext.delete)
        self.selectedID = nil; recompute(excluding: ids)
    }
    private func deleteSelectedLink() {
        guard let selectedLinkID, let link = links.first(where: { $0.id == selectedLinkID }) else { return }
        modelContext.delete(link)
        self.selectedLinkID = nil
        save()
    }
    private func undoAnnotation() {
        let lastStroke = visibleStrokes.max(by: { $0.createdAt < $1.createdAt })
        let lastNote = visibleNotes.max(by: { $0.createdAt < $1.createdAt })
        if let stroke = lastStroke, lastNote == nil || stroke.createdAt > lastNote!.createdAt { modelContext.delete(stroke) }
        else if let note = lastNote { modelContext.delete(note) }
        save()
    }
    private func recompute(excluding ids: Set<UUID> = []) { TaskCompletionService.recompute(task: task, steps: steps.filter { !ids.contains($0.id) }); save() }
    private func save() { try? modelContext.save() }
}

private enum WorkflowTool: String, CaseIterable, Identifiable {
    case hand, pen, note
    var id: String { rawValue }
    var icon: String { switch self { case .hand: "hand.draw"; case .pen: "pencil.tip"; case .note: "note.text.badge.plus" } }
    var title: String { switch self { case .hand: "Move canvas"; case .pen: "Draw"; case .note: "Add sticky note" } }
}

private func annotationPaperColor(_ ink: String) -> String {
    switch ink.uppercased() {
    case "#3D6DF2": "#DBEAFE"
    case "#10B981": "#D1FAE5"
    case "#F43F5E": "#FFE4E6"
    case "#8B5CF6": "#EDE9FE"
    case "#64748B": "#E2E8F0"
    default: "#FEF3C7"
    }
}

private struct WorkflowInkLayer: View {
    let strokes: [BoardStroke]; let preview: [[Double]]; let previewColor: String; let pan: CGSize; let zoom: CGFloat
    var body: some View {
        Canvas { context, _ in
            for stroke in strokes { draw(stroke.points, color: stroke.color, width: stroke.lineWidth, context: &context) }
            draw(preview, color: previewColor, width: 3, context: &context)
        }
    }
    private func draw(_ points: [[Double]], color: String, width: Double, context: inout GraphicsContext) {
        guard let first = points.first, first.count > 1 else { return }
        var path = Path(); path.move(to: CGPoint(x: first[0] * zoom + pan.width, y: first[1] * zoom + pan.height))
        for point in points.dropFirst() where point.count > 1 { path.addLine(to: CGPoint(x: point[0] * zoom + pan.width, y: point[1] * zoom + pan.height)) }
        context.stroke(path, with: .color(Color(hex: color)), style: StrokeStyle(lineWidth: max(1, width * zoom), lineCap: .round, lineJoin: .round))
    }
}

private struct WorkflowStickyNote: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var note: BoardNote
    let zoom: CGFloat; let pan: CGSize; let selected: Bool; let select: () -> Void; let moved: () -> Void
    @State private var origin: CGPoint?
    var body: some View {
        TextField("Note", text: $note.text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12.5, weight: .medium))
            .padding(14).frame(width: 170, height: 112, alignment: .topLeading)
            .background(Color(hex: note.color), in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(selected ? OrbitTheme.accent : Color.black.opacity(0.08), lineWidth: selected ? 2 : 1) }
            .shadow(color: .black.opacity(0.08), radius: 5, y: 3).scaleEffect(zoom)
            .position(x: note.canvasX * zoom + pan.width, y: note.canvasY * zoom + pan.height)
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                if origin == nil { origin = CGPoint(x: note.canvasX, y: note.canvasY) }
                guard let origin else { return }
                note.canvasX = origin.x + value.translation.width / zoom; note.canvasY = origin.y + value.translation.height / zoom
            }.onEnded { _ in origin = nil; moved() })
            .simultaneousGesture(TapGesture().onEnded(select))
    }
}

private struct WorkflowBackground: View {
    @Environment(\.colorScheme) private var scheme
    let pan: CGSize; let zoom: CGFloat
    var body: some View {
        Canvas { context, size in
            let spacing = max(8, 24 * zoom), startX = pan.width.truncatingRemainder(dividingBy: spacing), startY = pan.height.truncatingRemainder(dividingBy: spacing)
            for x in stride(from: startX, through: size.width, by: spacing) { for y in stride(from: startY, through: size.height, by: spacing) { context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(OrbitTheme.ink3(scheme).opacity(0.25))) } }
        }.background(OrbitTheme.canvas(scheme))
    }
}

private struct WorkflowEdges: View {
    let steps: [OrbitTaskStep]; let links: [StepLink]; let pan: CGSize; let zoom: CGFloat; let selectedLinkID: UUID?
    var body: some View {
        Canvas { context, _ in
            let map = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
            for link in links {
                guard let source = map[link.sourceID], let target = map[link.targetID],
                      let path = workflowLinkPath(from: source, to: target, pan: pan, zoom: zoom) else { continue }
                let selected = selectedLinkID == link.id
                context.stroke(path, with: .color(OrbitTheme.accent.opacity(selected ? 0.95 : 0.48)),
                               style: StrokeStyle(lineWidth: max(selected ? 2.8 : 1.2, (selected ? 2.8 : 1.8) * zoom), lineCap: .round))
            }
        }
    }
}

private struct WorkflowEdgeHitLayer: View {
    let steps: [OrbitTaskStep]; let links: [StepLink]; let pan: CGSize; let zoom: CGFloat; let select: (UUID) -> Void
    var body: some View {
        let map = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        ZStack {
            ForEach(links) { link in
                if let source = map[link.sourceID], let target = map[link.targetID],
                   let path = workflowLinkPath(from: source, to: target, pan: pan, zoom: zoom) {
                    path.stroke(Color.black.opacity(0.001), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .contentShape(path.strokedPath(StrokeStyle(lineWidth: 14, lineCap: .round)))
                        .onTapGesture { select(link.id) }
                        .help("Select link")
                }
            }
        }
    }
}

private func workflowLinkPath(from source: OrbitTaskStep, to target: OrbitTaskStep, pan: CGSize, zoom: CGFloat) -> Path? {
    guard let sx = source.canvasX, let sy = source.canvasY, let tx = target.canvasX, let ty = target.canvasY else { return nil }
    let start = CGPoint(x: (sx + 110) * zoom + pan.width, y: sy * zoom + pan.height)
    let end = CGPoint(x: (tx - 110) * zoom + pan.width, y: ty * zoom + pan.height)
    let bend = max(42 * zoom, abs(end.x - start.x) * 0.4)
    var path = Path()
    path.move(to: start)
    path.addCurve(to: end, control1: CGPoint(x: start.x + bend, y: start.y), control2: CGPoint(x: end.x - bend, y: end.y))
    return path
}

private struct WorkflowNode: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var step: OrbitTaskStep
    let hasChildren: Bool; let zoom: CGFloat; let pan: CGSize; let selected: Bool; let connecting: Bool
    let select: () -> Void; let connectionChanged: (CGPoint, CGPoint) -> Void; let connectionEnded: (CGPoint) -> Void; let toggle: () -> Void; let open: () -> Void; let moved: () -> Void
    @State private var origin: CGPoint?
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 11) {
            Button(action: toggle) { Image(systemName: step.done ? "checkmark.circle.fill" : hasChildren ? "circle.dotted" : "circle") }
                .buttonStyle(.plain).font(.system(size: 18)).foregroundStyle(step.done ? OrbitTheme.accent : OrbitTheme.ink3(scheme))
                .accessibilityLabel(step.done ? "Mark incomplete" : "Mark complete")
            TextField("Step", text: $step.title).textFieldStyle(.plain).font(.system(size: 12.5, weight: .medium)).onSubmit(moved)
            if hasChildren {
                Button(action: open) { Image(systemName: "rectangle.stack") }
                    .buttonStyle(.plain).foregroundStyle(OrbitTheme.accent).help("Open sub-workflow").accessibilityLabel("Open sub-workflow")
            }
        }
        .padding(13).frame(width: 220, height: 70)
        .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(selected ? OrbitTheme.accent : OrbitTheme.line(scheme), lineWidth: selected ? 1.7 : 1) }
        .overlay { connectionPorts }
        .shadow(color: .black.opacity(0.055), radius: 5, y: 2)
        .onHover { hovering = $0 }
        .scaleEffect(zoom)
        .position(x: (step.canvasX ?? 190) * zoom + pan.width, y: (step.canvasY ?? 170) * zoom + pan.height)
        .gesture(DragGesture(minimumDistance: 2).onChanged { value in if origin == nil { origin = CGPoint(x: step.canvasX ?? 0, y: step.canvasY ?? 0) }; guard let origin else { return }; step.canvasX = origin.x + value.translation.width / zoom; step.canvasY = origin.y + value.translation.height / zoom }.onEnded { _ in origin = nil; moved() })
        .simultaneousGesture(TapGesture().onEnded(select))
    }

    @ViewBuilder private var connectionPorts: some View {
        if hovering || connecting {
            ZStack {
                port(offsetX: -110).offset(x: -110)
                port(offsetX: 110).offset(x: 110)
            }
        }
    }

    private func port(offsetX: CGFloat) -> some View {
        let center = CGPoint(x: (step.canvasX ?? 190) * zoom + pan.width + offsetX * zoom, y: (step.canvasY ?? 170) * zoom + pan.height)
        return Circle().fill(OrbitTheme.surface(scheme))
            .overlay { Circle().stroke(OrbitTheme.accent, lineWidth: 2) }
            .frame(width: 13, height: 13).contentShape(Circle().inset(by: -6))
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("workflowCanvas")).onChanged { value in
                connectionChanged(center, value.location)
            }.onEnded { value in connectionEnded(value.location) })
            .accessibilityLabel("Drag to connect step")
    }
}
