import AppKit
import SwiftUI

/// A Notion-style block editor over a plain markdown string.
///
/// The document is parsed into blocks on load and serialized back on every
/// edit, so `Idea.content` stays ordinary markdown and nothing about the stored
/// schema changes.
struct BlockEditorView: View {
    @Binding var text: String
    var placeholder: String = "Start writing, or press / for commands"
    /// Creates a real sub-page record and returns its id, so `/page` can link
    /// to something that exists in the Ideas tree rather than a dangling id.
    var createPage: (() -> UUID?)?
    var pageTitle: ((UUID) -> String?)?
    var pageIcon: ((UUID) -> String?)?
    var openPage: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.orbitWidth) private var orbitWidth
    @StateObject private var focus = BlockFocus()

    @State private var blocks: [Block] = []
    @State private var heights: [UUID: CGFloat] = [:]
    @State private var hoveredID: UUID?
    @State private var selectedDividerID: UUID?

    /// Row geometry, used to turn a drag position into an insertion index.
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var drag: DragState?
    @State private var menuBlockID: UUID?

    private struct DragState {
        let id: UUID
        /// Where the dragged block would land, as an index into `blocks`.
        var target: Int
    }

    private static let space = "orbit.blocks"

    @State private var slashTarget: UUID?
    @State private var slashQuery: String = ""
    @State private var slashIndex: Int = 0

    /// Last string this view wrote out, so an echo of our own edit coming back
    /// through the binding does not reparse and stomp the caret.
    @State private var lastEmitted: String?

    /// Notion-style whole-block selection. `anchor`/`cursor` are the ends of a
    /// keyboard range; `selected` is the set that renders highlighted.
    @State private var selected: Set<UUID> = []
    @State private var selAnchor: UUID?
    @State private var selCursor: UUID?
    private var blockSelecting: Bool { !selected.isEmpty }

    private var numbering: [UUID: Int] { BlockEditorView.displayNumbers(blocks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ponytail: plain VStack, not Lazy — every block needs a live text
            // view for focus routing and height measurement. Fine to ~300
            // blocks; switch to a windowed list if documents get book-sized.
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                row(for: block, at: index)
            }

            trailingClickCatcher
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(RowFramePreference.self) { rowFrames = $0 }
        .overlay(alignment: .topLeading) { insertionLine }
        .overlay(alignment: .topLeading) { slashMenuOverlay }
        .environmentObject(focus)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: text) { _, newValue in
            // Only reparse when the change came from outside this editor.
            guard newValue != lastEmitted else { return }
            load(newValue)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for block: Block, at index: Int) -> some View {
        let isActive = focus.activeID == block.id
        let showsGutter = hoveredID == block.id || drag?.id == block.id || menuBlockID == block.id

        HStack(alignment: .top, spacing: 0) {
            gutter(for: block, at: index, visible: showsGutter)

            HStack(alignment: .top, spacing: 8) {
                marker(for: block)
                content(for: block, isActive: isActive)
            }
            .padding(.leading, CGFloat(block.indent) * (orbitWidth.isCompact ? 16 : 26))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, BlockTypography.spacingAbove(for: block.kind, isFirst: index == 0))
        .padding(.bottom, BlockTypography.spacingBelow(for: block.kind))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramePreference.self,
                    value: [block.id: proxy.frame(in: .named(Self.space))]
                )
            }
        }
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(OrbitTheme.accent.opacity(scheme == .dark ? 0.20 : 0.13))
                .opacity(selected.contains(block.id) ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredID = block.id } else if hoveredID == block.id { hoveredID = nil }
        }
        .opacity(drag?.id == block.id ? 0.4 : 1)
    }

    /// The blue rule showing where a dragged block will land.
    @ViewBuilder
    private var insertionLine: some View {
        if let drag, let y = insertionY(for: drag.target) {
            Rectangle()
                .fill(OrbitTheme.accent)
                .frame(height: 2)
                .padding(.leading, orbitWidth.gutterWidth)
                .offset(y: y - 1)
                .allowsHitTesting(false)
        }
    }

    private func insertionY(for index: Int) -> CGFloat? {
        if blocks.indices.contains(index) { return rowFrames[blocks[index].id]?.minY }
        return blocks.last.flatMap { rowFrames[$0.id]?.maxY }
    }

    /// Which slot a drag sitting at `y` would drop into. Comparing against each
    /// row's midpoint is what makes the target flip as the cursor crosses the
    /// middle of a row rather than its edge.
    private func insertionIndex(for y: CGFloat) -> Int {
        for (index, block) in blocks.enumerated() {
            guard let frame = rowFrames[block.id] else { continue }
            if y < frame.midY { return index }
        }
        return blocks.count
    }

    // MARK: gutter (plus and drag handle)

    @ViewBuilder
    private func gutter(for block: Block, at index: Int, visible: Bool) -> some View {
        HStack(spacing: 1) {
            Button { insertBlock(below: block.id) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(OrbitTheme.ink3(scheme))
            .help("Click to add a block below")

            handle(for: block, at: index)
        }
        .opacity(visible ? 1 : 0)
        // An opacity-0 view still hit-tests in SwiftUI, so without this the
        // invisible handle swallows clicks in the margin of every row.
        .allowsHitTesting(visible)
        .animation(.easeOut(duration: 0.1), value: visible)
        .frame(width: orbitWidth.gutterWidth, alignment: .trailing)
        .padding(.trailing, orbitWidth.isCompact ? 2 : 6)
        .padding(.top, gutterTopInset(for: block.kind))
    }

    /// Drag to reorder, click for the block menu.
    ///
    /// This used to be a `Menu` with `.onDrag` attached to its label, which
    /// never worked: `Menu` consumes the mouse-down to open itself, so the drag
    /// could not start. Owning both gestures directly is what makes the handle
    /// behave like Notion's.
    @ViewBuilder
    private func handle(for block: Block, at index: Int) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .foregroundStyle(OrbitTheme.ink3(scheme))
            .help("Drag to move, or click for actions")
            .onTapGesture { menuBlockID = block.id }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if drag?.id != block.id { drag = DragState(id: block.id, target: index) }
                        drag?.target = insertionIndex(for: value.location.y)
                    }
                    .onEnded { _ in
                        if let state = drag { moveBlock(state.id, to: state.target) }
                        drag = nil
                    }
            )
            .popover(
                isPresented: Binding(
                    get: { menuBlockID == block.id },
                    set: { if !$0, menuBlockID == block.id { menuBlockID = nil } }
                ),
                arrowEdge: .leading
            ) {
                blockMenu(for: block)
            }
    }

    private func gutterTopInset(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading1: 8
        case .heading2: 5
        case .heading3: 3
        case .divider: 0
        default: 1
        }
    }

    /// The handle's click menu. A panel rather than a native `Menu`, because the
    /// handle needs to own its own gestures in order to drag.
    @ViewBuilder
    private func blockMenu(for block: Block) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            menuRow("Delete", "trash", tint: OrbitTheme.rose) { delete(block.id) }
            menuRow("Duplicate", "plus.square.on.square") { duplicate(block.id) }

            if block.kind.isList || block.kind == .paragraph || block.kind == .quote {
                menuRow("Indent", "increase.indent") { indent(block.id, deeper: true) }
                    .disabled(block.indent >= BlockDocument.maxIndent)
                menuRow("Outdent", "decrease.indent") { indent(block.id, deeper: false) }
                    .disabled(block.indent == 0)
            }

            Text("TURN INTO")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(OrbitTheme.ink3(scheme))
                .padding(.horizontal, 8)
                .padding(.top, 9)
                .padding(.bottom, 3)

            ForEach(BlockKind.convertible, id: \.self) { kind in
                menuRow(kind.title, kind.symbol) { setKind(kind, for: block.id) }
                    .disabled(kind == block.kind)
            }
        }
        .padding(6)
        .frame(width: 208)
    }

    @ViewBuilder
    private func menuRow(
        _ title: String,
        _ symbol: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            menuBlockID = nil
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title).font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint ?? OrbitTheme.ink(scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: block leading markers

    @ViewBuilder
    private func marker(for block: Block) -> some View {
        switch block.kind {
        case .bulleted:
            Text(bulletGlyph(for: block.indent))
                .font(.system(size: 16))
                .foregroundStyle(OrbitTheme.ink(scheme))
                .frame(width: 24, height: BlockTypography.firstLineHeight(for: block.kind), alignment: .center)

        case .numbered:
            Text("\(numbering[block.id] ?? 1).")
                .font(.system(size: 15))
                .monospacedDigit()
                .foregroundStyle(OrbitTheme.ink(scheme))
                .frame(width: 24, height: BlockTypography.firstLineHeight(for: block.kind), alignment: .trailing)

        case .todo:
            // The tap target must be a filled shape. A `Shape.stroke()` only
            // hit-tests along the 1.4pt outline, which made the checkbox look
            // clickable while swallowing every click that landed inside it.
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(block.checked ? OrbitTheme.accent : Color.clear)
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(block.checked ? OrbitTheme.accent : OrbitTheme.ink3(scheme), lineWidth: 1.4)
                if block.checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onTapGesture { toggleCheck(block.id) }
            .frame(width: 24, height: BlockTypography.firstLineHeight(for: block.kind), alignment: .center)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(block.checked ? "Mark as not done" : "Mark as done")
            .help(block.checked ? "Mark as not done" : "Mark as done")

        default:
            EmptyView()
        }
    }

    private func bulletGlyph(for indent: Int) -> String {
        switch indent % 3 {
        case 1: "◦"
        case 2: "▪"
        default: "•"
        }
    }

    // MARK: block content

    @ViewBuilder
    private func content(for block: Block, isActive: Bool) -> some View {
        switch block.kind {
        case .divider:
            dividerRow(block)

        case .page:
            pageRow(block)

        case .code:
            editor(for: block, isActive: isActive)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(OrbitTheme.line(scheme))
                }

        case .quote:
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(OrbitTheme.ink(scheme).opacity(0.5))
                    .frame(width: 3)
                    .frame(minHeight: heights[block.id] ?? 24)
                editor(for: block, isActive: isActive)
            }

        default:
            editor(for: block, isActive: isActive)
        }
    }

    @ViewBuilder
    private func pageRow(_ block: Block) -> some View {
        let title = block.pageID.flatMap { pageTitle?($0) } ?? block.text
        Button {
            if let pageID = block.pageID { openPage?(pageID) }
        } label: {
            HStack(spacing: 9) {
                if let icon = block.pageID.flatMap({ pageIcon?($0) }) {
                    Text(icon).font(.system(size: 15))
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(OrbitTheme.ink2(scheme))
                }
                Text(title.isEmpty ? "Untitled page" : title)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.ink(scheme))
                    .underline()
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open this sub-page")
    }

    @ViewBuilder
    private func dividerRow(_ block: Block) -> some View {
        Rectangle()
            .fill(selectedDividerID == block.id ? OrbitTheme.accent : OrbitTheme.line(scheme))
            .frame(height: selectedDividerID == block.id ? 2 : 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture { selectedDividerID = block.id }
            .focusable()
            .onKeyPress(.delete) { delete(block.id); return .handled }
            .onKeyPress(.deleteForward) { delete(block.id); return .handled }
            .accessibilityLabel("Divider")
    }

    @ViewBuilder
    private func editor(for block: Block, isActive: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if block.text.isEmpty, block.kind != .code {
                Text(placeholderText(for: block, isActive: isActive))
                    .font(Font(BlockTypography.font(for: block.kind)))
                    .foregroundStyle(OrbitTheme.ink3(scheme))
                    .allowsHitTesting(false)
            }

            BlockTextEditor(
                blockID: block.id,
                kind: block.kind,
                text: block.text,
                checked: block.checked,
                isMenuOpen: slashTarget == block.id,
                blockSelecting: blockSelecting,
                accent: OrbitTheme.accent,
                scheme: scheme,
                height: heightBinding(for: block.id),
                intents: intents(for: block.id)
            )
            .frame(height: max(heights[block.id] ?? 24, 20))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholderText(for block: Block, isActive: Bool) -> String {
        guard isActive else {
            switch block.kind {
            case .heading1, .heading2, .heading3: return block.kind.title
            case .todo: return "To-do"
            case .quote: return "Quote"
            default: return ""
            }
        }
        switch block.kind {
        case .heading1, .heading2, .heading3: return block.kind.title
        case .bulleted, .numbered, .todo: return "List"
        case .quote: return "Quote"
        default: return blocks.count == 1 ? placeholder : "Type / for commands"
        }
    }

    private func heightBinding(for id: UUID) -> Binding<CGFloat> {
        Binding(
            get: { heights[id] ?? 24 },
            set: { heights[id] = $0 }
        )
    }

    /// Clicking the empty space under the document continues writing, the way
    /// clicking below a Notion page does.
    private var trailingClickCatcher: some View {
        Color.clear
            .frame(height: 140)
            .contentShape(Rectangle())
            .onTapGesture {
                if let last = blocks.last, last.isEmptyParagraph {
                    focus.focus(last.id)
                } else {
                    let fresh = Block()
                    blocks.append(fresh)
                    commit()
                    focus.focus(fresh.id)
                }
            }
    }

    // MARK: - Slash menu

    private var slashMatches: [BlockKind] {
        let query = slashQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return BlockKind.allCases }
        return BlockKind.allCases.filter { kind in
            kind.title.lowercased().contains(query) || kind.keywords.contains { $0.hasPrefix(query) }
        }
    }

    @ViewBuilder
    private var slashMenuOverlay: some View {
        if slashTarget != nil, !slashMatches.isEmpty {
            SlashMenu(
                matches: slashMatches,
                selection: slashIndex,
                scheme: scheme,
                pick: { commitSlash($0) }
            )
            .offset(x: 52, y: slashMenuOffset)
            .transition(.opacity)
            .zIndex(10)
        }
    }

    /// Sits just under the block that opened it.
    private var slashMenuOffset: CGFloat {
        guard let target = slashTarget,
              let index = blocks.firstIndex(where: { $0.id == target }) else { return 0 }
        var y: CGFloat = 0
        for (position, block) in blocks.enumerated() where position <= index {
            y += BlockTypography.spacingAbove(for: block.kind, isFirst: position == 0)
            if position < index {
                y += (heights[block.id] ?? 24) + BlockTypography.spacingBelow(for: block.kind)
            }
        }
        return y + (heights[blocks[index].id] ?? 24) + 6
    }

    private func commitSlash(_ kind: BlockKind) {
        guard let target = slashTarget,
              let index = blocks.firstIndex(where: { $0.id == target }) else { return }

        // Strip the "/query" that opened the menu.
        let token = "/" + slashQuery
        var text = blocks[index].text
        if let range = text.range(of: token, options: .backwards) {
            text.removeSubrange(range)
        }

        blocks[index].text = text
        blocks[index].kind = kind
        blocks[index].edited()

        if kind == .page {
            guard let newPageID = createPage?() else {
                // No sub-page could be created — leave the block as plain text
                // rather than writing a link that points at nothing.
                blocks[index].kind = .paragraph
                closeSlash()
                commit()
                focus.focus(blocks[index].id)
                return
            }
            blocks[index].pageID = newPageID
            blocks[index].text = ""
            let follow = Block()
            blocks.insert(follow, at: index + 1)
            closeSlash()
            commit()
            focus.focus(follow.id, offset: 0)
            return
        }

        if kind == .divider {
            // A divider holds no text, so push any remainder into a new block.
            blocks[index].text = ""
            let follow = Block(text: text)
            blocks.insert(follow, at: index + 1)
            closeSlash()
            commit()
            focus.focus(follow.id, offset: 0)
            return
        }

        let id = blocks[index].id
        closeSlash()
        commit()
        focus.focus(id)
    }

    private func closeSlash() {
        slashTarget = nil
        slashQuery = ""
        slashIndex = 0
    }

    // MARK: - Intents

    private func intents(for id: UUID) -> BlockIntents {
        var intents = BlockIntents()

        intents.selectThisBlock = { if selected.isEmpty { selectBlocks([id], anchor: id, cursor: id) } }
        intents.selectAllBlocks = {
            guard !blocks.isEmpty else { return }
            selectBlocks(Set(blocks.map(\.id)), anchor: blocks.first?.id, cursor: blocks.last?.id)
        }
        intents.moveBlockSelection = { down in moveSelection(down: down) }
        intents.extendBlockSelection = { down in extendSelection(down: down) }
        intents.copyBlocks = { copySelected() }
        intents.deleteBlocks = { deleteSelected() }
        intents.clearBlockSelection = { clearSelection() }

        intents.textChanged = { newText in
            if !selected.isEmpty { clearSelection() }
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }

            // Markdown shortcut: "# " and friends transform the block in place.
            if let shortcut = BlockShortcut.match(newText, in: blocks[index].kind) {
                blocks[index].kind = shortcut.kind
                blocks[index].text = shortcut.text
                blocks[index].checked = shortcut.checked
                blocks[index].edited()

                if shortcut.kind == .divider {
                    let follow = Block()
                    blocks.insert(follow, at: index + 1)
                    commit()
                    focus.focus(follow.id, offset: 0)
                    return
                }

                commit()
                focus.focus(id, offset: 0)
                return
            }

            guard blocks[index].text != newText else { return }
            blocks[index].text = newText
            blocks[index].edited()
            commit()
        }

        intents.split = { offset in
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
            let block = blocks[index]

            // Return on an empty list item leaves the list, like Notion.
            if block.text.isEmpty, block.kind.continuesOnReturn {
                if block.indent > 0 {
                    blocks[index].indent -= 1
                } else {
                    blocks[index].kind = .paragraph
                    blocks[index].checked = false
                }
                blocks[index].edited()
                commit()
                focus.focus(block.id, offset: 0)
                return
            }

            let characters = Array(block.text)
            let cut = min(max(offset, 0), characters.count)
            let head = String(characters[..<cut])
            let tail = String(characters[cut...])

            blocks[index].text = head
            blocks[index].edited()

            let inherits = block.kind.continuesOnReturn
            let fresh = Block(
                kind: inherits ? block.kind : .paragraph,
                text: tail,
                checked: false,
                indent: inherits ? block.indent : 0
            )
            blocks.insert(fresh, at: index + 1)
            commit()
            focus.focus(fresh.id, offset: 0)
        }

        intents.mergeBackward = {
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
            let block = blocks[index]

            // Backspace first strips the block's own formatting, exactly like
            // Notion: bullet -> text, indented -> outdented, only then merge.
            if block.indent > 0 {
                blocks[index].indent -= 1
                blocks[index].edited()
                commit()
                focus.focus(block.id, offset: 0)
                return
            }
            if block.kind != .paragraph {
                blocks[index].kind = .paragraph
                blocks[index].checked = false
                blocks[index].edited()
                commit()
                focus.focus(block.id, offset: 0)
                return
            }
            guard index > 0 else { return }

            let previous = blocks[index - 1]
            if previous.kind == .divider {
                blocks.remove(at: index - 1)
                commit()
                focus.focus(block.id, offset: 0)
                return
            }

            let junction = previous.text.count
            blocks[index - 1].text = previous.text + block.text
            blocks[index - 1].edited()
            blocks.remove(at: index)
            commit()
            focus.focus(blocks[index - 1].id, offset: junction)
        }

        intents.mergeForward = {
            guard let index = blocks.firstIndex(where: { $0.id == id }), index + 1 < blocks.count else { return }
            let next = blocks[index + 1]
            if next.kind == .divider {
                blocks.remove(at: index + 1)
                commit()
                return
            }
            let junction = blocks[index].text.count
            blocks[index].text += next.text
            blocks[index].edited()
            blocks.remove(at: index + 1)
            commit()
            focus.focus(blocks[index].id, offset: junction)
        }

        intents.paste = { markdown, caret in
            guard let index = blocks.firstIndex(where: { $0.id == id }),
                  let spliced = BlockDocument.paste(markdown, into: blocks, at: index, caret: caret)
            else { return }
            blocks = spliced.blocks
            closeSlash()
            commit()
            focus.focus(spliced.caretID, offset: spliced.caretOffset)
        }

        intents.indent = { deeper in indent(id, deeper: deeper) }

        intents.moveFocus = { down, _ in
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
            let neighbour = down ? index + 1 : index - 1
            guard blocks.indices.contains(neighbour) else { return }
            focus.focus(blocks[neighbour].id, offset: down ? 0 : .max)
        }

        intents.escape = { closeSlash() }

        intents.slashQuery = { query in
            guard let query else {
                if slashTarget == id { closeSlash() }
                return
            }
            slashTarget = id
            if slashQuery != query { slashIndex = 0 }
            slashQuery = query
        }

        intents.menuMove = { down in
            let count = slashMatches.count
            guard count > 0 else { return }
            slashIndex = (slashIndex + (down ? 1 : -1) + count) % count
        }

        intents.menuCommit = {
            guard slashMatches.indices.contains(slashIndex) else { return }
            commitSlash(slashMatches[slashIndex])
        }

        return intents
    }

    // MARK: - Structural edits

    private func indent(_ id: UUID, deeper: Bool) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let kind = blocks[index].kind
        guard kind.isList || kind == .paragraph || kind == .quote else { return }

        let current = blocks[index].indent
        let next = deeper ? min(current + 1, BlockDocument.maxIndent) : max(current - 1, 0)
        guard next != current else { return }

        blocks[index].indent = next
        blocks[index].edited()
        commit()
    }

    private func setKind(_ kind: BlockKind, for id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].kind = kind
        if kind != .todo { blocks[index].checked = false }
        if kind == .heading1 || kind == .heading2 || kind == .heading3 || kind == .divider {
            blocks[index].indent = 0
        }
        blocks[index].edited()
        commit()
        focus.focus(id)
    }

    private func toggleCheck(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].checked.toggle()
        blocks[index].edited()
        commit()
    }

    private func insertBlock(below id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let fresh = Block(indent: blocks[index].indent)
        blocks.insert(fresh, at: index + 1)
        commit()
        focus.focus(fresh.id, offset: 0)
    }

    private func duplicate(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        var copy = blocks[index]
        copy.id = UUID()
        blocks.insert(copy, at: index + 1)
        commit()
    }

    private func delete(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        if selectedDividerID == id { selectedDividerID = nil }
        blocks.remove(at: index)
        // A document always keeps one block to type into.
        if blocks.isEmpty { blocks = [Block()] }
        commit()
        let neighbour = max(0, index - 1)
        if blocks.indices.contains(neighbour) { focus.focus(blocks[neighbour].id) }
    }

    /// `destination` is a slot between rows, not a row index — dropping just
    /// below where the block already sits is a no-op. `move(fromOffsets:)`
    /// handles the shift that made the old remove-then-insert land one row
    /// short whenever a block moved downward.
    private func moveBlock(_ id: UUID, to destination: Int) {
        guard let from = blocks.firstIndex(where: { $0.id == id }),
              destination != from, destination != from + 1,
              (0...blocks.count).contains(destination) else { return }
        blocks.move(fromOffsets: IndexSet(integer: from), toOffset: destination)
        commit()
    }

    // MARK: - Load / commit

    // MARK: - Block selection

    private func selectBlocks(_ set: Set<UUID>, anchor: UUID?, cursor: UUID?) {
        selected = set; selAnchor = anchor; selCursor = cursor
    }

    private func clearSelection() {
        guard !selected.isEmpty else { return }
        selected = []; selAnchor = nil; selCursor = nil
    }

    private func moveSelection(down: Bool) {
        guard let cursor = selCursor, let i = blocks.firstIndex(where: { $0.id == cursor }) else { return }
        let j = down ? min(i + 1, blocks.count - 1) : max(i - 1, 0)
        let id = blocks[j].id
        selectBlocks([id], anchor: id, cursor: id)
    }

    private func extendSelection(down: Bool) {
        guard let anchor = selAnchor, let ai = blocks.firstIndex(where: { $0.id == anchor }),
              let cursor = selCursor, let ci = blocks.firstIndex(where: { $0.id == cursor }) else { return }
        let nj = down ? min(ci + 1, blocks.count - 1) : max(ci - 1, 0)
        selCursor = blocks[nj].id
        let lo = min(ai, nj), hi = max(ai, nj)
        selected = Set(blocks[lo...hi].map(\.id))
    }

    private func copySelected() {
        let chosen = blocks.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BlockDocument.serialize(chosen), forType: .string)
    }

    private func deleteSelected() {
        guard !selected.isEmpty else { return }
        let firstIdx = blocks.firstIndex { selected.contains($0.id) } ?? 0
        let survivors = blocks.filter { !selected.contains($0.id) }
        blocks = survivors.isEmpty ? [Block()] : survivors
        clearSelection()
        commit()
        focus.focus(blocks[min(firstIdx, blocks.count - 1)].id, offset: 0)
    }

    private func loadIfNeeded() {
        guard blocks.isEmpty else { return }
        load(text)
    }

    private func load(_ markdown: String) {
        var parsed = BlockDocument.parse(markdown)
        if parsed.isEmpty { parsed = [Block()] }
        blocks = parsed
        heights = [:]
        closeSlash()
    }

    private func commit() {
        let markdown = BlockDocument.serialize(blocks)
        lastEmitted = markdown
        text = markdown
    }

    // MARK: - Numbering

    static func displayNumbers(_ blocks: [Block]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var counters: [Int: Int] = [:]
        for block in blocks {
            guard block.kind == .numbered else {
                counters.removeAll()
                continue
            }
            counters = counters.filter { $0.key <= block.indent }
            counters[block.indent, default: 0] += 1
            result[block.id] = counters[block.indent]
        }
        return result
    }
}

// MARK: - Row geometry

/// Every row reports its frame so a drag can be resolved to an insertion slot
/// without guessing from accumulated heights.
private struct RowFramePreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Slash menu

private struct SlashMenu: View {
    let matches: [BlockKind]
    let selection: Int
    let scheme: ColorScheme
    let pick: (BlockKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("BASIC BLOCKS")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(OrbitTheme.ink3(scheme))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 5)

            ForEach(Array(matches.enumerated()), id: \.element) { index, kind in
                Button { pick(kind) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 14))
                            .frame(width: 34, height: 34)
                            .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(OrbitTheme.ink(scheme))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(OrbitTheme.ink(scheme))
                            Text(kind.subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(OrbitTheme.ink3(scheme))
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        index == selection ? OrbitTheme.accentSoft(scheme) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 5)
            }
        }
        .padding(.bottom, 7)
        .frame(width: 312)
        .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(OrbitTheme.line(scheme))
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 18, y: 8)
    }
}
