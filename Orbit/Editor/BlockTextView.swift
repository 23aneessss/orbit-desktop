import AppKit
import SwiftUI

// MARK: - Typography

enum BlockTypography {
    static func font(for kind: BlockKind) -> NSFont {
        switch kind {
        case .heading1: .systemFont(ofSize: 29, weight: .bold)
        case .heading2: .systemFont(ofSize: 23, weight: .bold)
        case .heading3: .systemFont(ofSize: 18.5, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: 13, weight: .regular)
        default: .systemFont(ofSize: 15.5, weight: .regular)
        }
    }

    /// Height of a single rendered line. Leading markers (bullet, number,
    /// checkbox) centre themselves inside this so they line up with the first
    /// line of text at any heading size instead of drifting.
    static func firstLineHeight(for kind: BlockKind) -> CGFloat {
        let font = font(for: kind)
        return ceil(font.ascender - font.descender + font.leading)
    }

    static func lineSpacing(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading1, .heading2, .heading3: 2
        case .code: 3
        default: 5
        }
    }

    /// Notion gives headings room above them, but not when they open a document.
    static func spacingAbove(for kind: BlockKind, isFirst: Bool) -> CGFloat {
        guard !isFirst else { return 0 }
        switch kind {
        case .heading1: return 26
        case .heading2: return 20
        case .heading3: return 14
        case .code: return 6
        default: return 1
        }
    }

    static func spacingBelow(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading1, .heading2, .heading3: 3
        case .code: 6
        default: 1
        }
    }
}

// MARK: - Resolving a drag position to a block

/// Weak so a deleted block's text view neither leaks nor answers hit tests.
final class WeakTextView {
    weak var view: BlockNSTextView?
    init(_ view: BlockNSTextView) { self.view = view }
}

enum BlockHitTest {
    /// Which block owns a given window-space `y`.
    ///
    /// Frames are window coordinates, so **up is a larger y**. Rows have padding
    /// between them; a `y` landing in one of those gaps (or past either end of
    /// the document) resolves to the nearest block rather than falling through,
    /// which is what made an upward drag jump to the wrong end.
    static func blockID(atY y: CGFloat, in frames: [(id: UUID, rect: NSRect)]) -> UUID? {
        if let hit = frames.first(where: { y >= $0.rect.minY && y <= $0.rect.maxY }) { return hit.id }
        return frames.min(by: { abs($0.rect.midY - y) < abs($1.rect.midY - y) })?.id
    }
}

// MARK: - Focus coordination

/// Blocks are separate text views, so "where is the caret" has to live above
/// them. A request is consumed by whichever block matches, then cleared.
@MainActor
final class BlockFocus: ObservableObject {
    struct Request: Equatable {
        let id: UUID
        /// Character offset, or `Int.max` for "end of block".
        let offset: Int
        let token: Int
    }

    @Published private(set) var request: Request?
    @Published var activeID: UUID?
    private var token = 0

    /// Live text views, used to resolve a drag to a block. Deliberately not
    /// `@Published`: it is geometry bookkeeping, not state anyone renders from.
    var textViews: [UUID: WeakTextView] = [:]

    /// Frames are read on demand so scrolling mid-drag can't make them stale.
    func blockID(atWindowY y: CGFloat) -> UUID? {
        let frames = textViews.compactMap { id, box -> (id: UUID, rect: NSRect)? in
            guard let view = box.view, view.window != nil else { return nil }
            return (id, view.convert(view.bounds, to: nil))
        }
        return BlockHitTest.blockID(atY: y, in: frames)
    }

    func focus(_ id: UUID, offset: Int = .max) {
        token += 1
        request = Request(id: id, offset: offset, token: token)
    }

    func consume(_ id: UUID) -> Int? {
        guard let pending = request, pending.id == id else { return nil }
        request = nil
        return pending.offset
    }
}

// MARK: - Editing intents raised by a block's text view

struct BlockIntents {
    var textChanged: (String) -> Void = { _ in }
    /// Return pressed — split at the caret offset.
    var split: (Int) -> Void = { _ in }
    /// Backspace at offset 0.
    var mergeBackward: () -> Void = {}
    /// Forward-delete at the very end.
    var mergeForward: () -> Void = {}
    /// Tab / Shift-Tab.
    var indent: (Bool) -> Void = { _ in }
    /// Caret left the top or bottom edge.
    var moveFocus: (_ down: Bool, _ offset: Int) -> Void = { _, _ in }
    var escape: () -> Void = {}
    /// Multi-line paste — the editor turns it into blocks at the given offset.
    var paste: (_ markdown: String, _ caret: Int) -> Void = { _, _ in }
    /// Slash-menu query, or nil when the menu should close.
    var slashQuery: (String?) -> Void = { _ in }
    /// Arrow / Return while the slash menu owns the keyboard.
    var menuMove: (_ down: Bool) -> Void = { _ in }
    var menuCommit: () -> Void = {}

    // Block-level selection (Notion "select whole blocks" mode).
    /// Esc from a caret selects the current block.
    var selectThisBlock: () -> Void = {}
    /// Cmd-A once selects the block's text; a second Cmd-A selects every block.
    var selectAllBlocks: () -> Void = {}
    /// Plain arrow moves the single-block selection.
    var moveBlockSelection: (_ down: Bool) -> Void = { _ in }
    /// Shift-arrow grows/shrinks the selected range.
    var extendBlockSelection: (_ down: Bool) -> Void = { _ in }
    var copyBlocks: () -> Void = {}
    var deleteBlocks: () -> Void = {}
    var clearBlockSelection: () -> Void = {}
    /// A mouse drag left this block — start selecting whole blocks from here.
    var dragSelectBegan: () -> Void = {}
    /// The drag is now over this block; select the range from the anchor to it.
    var dragSelectTo: (UUID) -> Void = { _ in }
}

// MARK: - NSTextView subclass

final class BlockNSTextView: NSTextView {
    var intents = BlockIntents()
    var blockKind: BlockKind = .paragraph
    /// Which block this view renders, so a drag can name the block it lands on.
    var blockID = UUID()
    /// Window-space y → block, supplied by the SwiftUI layer.
    var resolveBlock: (CGFloat) -> UUID? = { _ in nil }
    var menuIsOpen = false
    /// True while the editor is in whole-block selection mode; this view then
    /// routes copy / delete / arrows to the document instead of its own text.
    var blockSelecting = false
    var onFocusChange: (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    // Cmd-A: first press selects this block's text; once fully selected (or
    // already in block mode) it escalates to selecting every block.
    override func selectAll(_ sender: Any?) {
        let length = (string as NSString).length
        if blockSelecting || (length > 0 && selectedRange().length == length) {
            intents.selectAllBlocks()
        } else {
            super.selectAll(sender)
        }
    }

    override func copy(_ sender: Any?) {
        if blockSelecting { intents.copyBlocks() } else { super.copy(sender) }
    }

    /// Drag from inside this block out to another one and the whole blocks get
    /// selected, like Notion. AppKit's own `mouseDown` runs a modal tracking
    /// loop, so `mouseDragged` would never reach us — we track the drag here and
    /// do the in-block text selection by hand while it stays within bounds.
    override func mouseDown(with event: NSEvent) {
        if blockSelecting { intents.clearBlockSelection() }

        guard event.clickCount == 1,
              !event.modifierFlags.contains(.shift),
              let window else {
            super.mouseDown(with: event)   // double/triple-click, shift-click
            return
        }

        window.makeFirstResponder(self)
        let start = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        setSelectedRange(NSRange(location: start, length: 0))

        var crossed = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let local = convert(next.locationInWindow, from: nil)

            if !crossed, local.y < -6 || local.y > bounds.height + 6 {
                crossed = true
                intents.dragSelectBegan()
            }

            if crossed {
                if let target = resolveBlock(next.locationInWindow.y) {
                    intents.dragSelectTo(target)
                }
            } else {
                let index = characterIndexForInsertion(at: local)
                setSelectedRange(NSRange(location: min(start, index), length: abs(index - start)))
                autoscroll(with: next)
            }
        }
    }

    // Typing exits block mode (and swallows that one keystroke, like clearing a
    // selection). Real replace-on-type isn't worth the complexity here.
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if blockSelecting { intents.clearBlockSelection(); return }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange(false) }
        return ok
    }

    /// Cmd-B / Cmd-I / Cmd-E wrap the selection in markdown, since the document
    /// is plain text and AppKit's rich-text bold has nothing to act on.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              blockKind != .code,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "b": wrapSelection(with: "**"); return true
        case "i": wrapSelection(with: "*"); return true
        case "e": wrapSelection(with: "`"); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func wrapSelection(with marker: String) {
        let range = selectedRange()
        let text = string as NSString
        let selected = range.length > 0 ? text.substring(with: range) : ""

        // Toggle off when the selection is already wrapped.
        let outer = NSRange(
            location: max(0, range.location - marker.count),
            length: min(range.length + marker.count * 2, text.length - max(0, range.location - marker.count))
        )
        if range.location >= marker.count,
           outer.length == range.length + marker.count * 2,
           text.substring(with: outer).hasPrefix(marker),
           text.substring(with: outer).hasSuffix(marker) {
            guard shouldChangeText(in: outer, replacementString: selected) else { return }
            replaceCharacters(in: outer, with: selected)
            didChangeText()
            setSelectedRange(NSRange(location: outer.location, length: (selected as NSString).length))
            return
        }

        let replacement = marker + selected + marker
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(
            location: range.location + marker.count,
            length: (selected as NSString).length
        ))
    }

    /// A block renders one logical line, so a multi-line paste has to become
    /// several blocks. Left to AppKit it lands as one block full of newlines,
    /// which draws clipped over the row below and serializes back out as a
    /// heading that swallowed the list underneath it.
    override func paste(_ sender: Any?) {
        guard let raw = NSPasteboard.general.string(forType: .string),
              raw.contains("\n") else {
            super.paste(sender)
            return
        }

        // Replacing the selection first keeps the caret offset we hand over
        // meaningful, and lets the normal undo grouping record the deletion.
        let selection = selectedRange()
        if selection.length > 0, shouldChangeText(in: selection, replacementString: "") {
            replaceCharacters(in: selection, with: "")
            didChangeText()
        }

        intents.paste(raw, selectedRange().location)
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }

    override func doCommand(by selector: Selector) {
        // In block-selection mode this view drives the whole document.
        if blockSelecting {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): intents.moveBlockSelection(false)
            case #selector(NSResponder.moveDown(_:)): intents.moveBlockSelection(true)
            case #selector(NSStandardKeyBindingResponding.moveUpAndModifySelection(_:)): intents.extendBlockSelection(false)
            case #selector(NSStandardKeyBindingResponding.moveDownAndModifySelection(_:)): intents.extendBlockSelection(true)
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)): intents.deleteBlocks()
            default: intents.clearBlockSelection()   // Esc, Return, Tab, anything → exit
            }
            return
        }

        // While the slash menu is up it owns the arrows and Return.
        if menuIsOpen {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                intents.menuMove(false); return
            case #selector(NSResponder.moveDown(_:)):
                intents.menuMove(true); return
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                intents.menuCommit(); return
            case #selector(NSResponder.cancelOperation(_:)):
                intents.slashQuery(nil); return
            default:
                break
            }
        }

        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Code blocks keep Return for what it normally does.
            if blockKind == .code { super.doCommand(by: selector); return }
            intents.split(selectedRange().location)
            return

        case #selector(NSResponder.insertLineBreak(_:)):
            // Shift-Return inside code adds a line; elsewhere it starts a block.
            if blockKind == .code { super.doCommand(by: #selector(NSResponder.insertNewline(_:))); return }
            intents.split(selectedRange().location)
            return

        case #selector(NSResponder.deleteBackward(_:)):
            let range = selectedRange()
            if range.length == 0 && range.location == 0 {
                intents.mergeBackward()
                return
            }

        case #selector(NSResponder.deleteForward(_:)):
            let range = selectedRange()
            if range.length == 0 && range.location == (string as NSString).length {
                intents.mergeForward()
                return
            }

        case #selector(NSResponder.insertTab(_:)):
            if blockKind == .code { super.doCommand(by: selector); return }
            intents.indent(true)
            return

        case #selector(NSResponder.insertBacktab(_:)):
            if blockKind == .code { super.doCommand(by: selector); return }
            intents.indent(false)
            return

        case #selector(NSResponder.moveUp(_:)):
            if caretIsOnFirstLine() {
                intents.moveFocus(false, selectedRange().location)
                return
            }

        case #selector(NSResponder.moveDown(_:)):
            if caretIsOnLastLine() {
                intents.moveFocus(true, selectedRange().location)
                return
            }

        case #selector(NSResponder.cancelOperation(_:)):
            // Esc closes the slash menu if open, otherwise selects this block.
            intents.escape()
            intents.selectThisBlock()
            return

        default:
            break
        }

        super.doCommand(by: selector)
    }

    // MARK: caret line probing

    private func lineFragment(at location: Int) -> NSRect? {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return nil }
        let length = (string as NSString).length
        let safe = min(max(location, 0), length)
        let glyph = min(layoutManager.glyphIndexForCharacter(at: safe), layoutManager.numberOfGlyphs - 1)
        _ = textContainer
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    private func caretIsOnFirstLine() -> Bool {
        guard let current = lineFragment(at: selectedRange().location),
              let first = lineFragment(at: 0) else { return true }
        return abs(current.minY - first.minY) < 0.5
    }

    private func caretIsOnLastLine() -> Bool {
        let length = (string as NSString).length
        guard let current = lineFragment(at: selectedRange().location),
              let last = lineFragment(at: length) else { return true }
        return abs(current.minY - last.minY) < 0.5
    }
}

// MARK: - SwiftUI bridge

struct BlockTextEditor: NSViewRepresentable {
    let blockID: UUID
    let kind: BlockKind
    let text: String
    let checked: Bool
    let isMenuOpen: Bool
    let blockSelecting: Bool
    let accent: Color
    let scheme: ColorScheme
    @Binding var height: CGFloat
    let intents: BlockIntents

    @EnvironmentObject private var focus: BlockFocus

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> BlockNSTextView {
        let view = BlockNSTextView(frame: .zero)
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.string = text
        context.coordinator.applyStyle(to: view, kind: kind, checked: checked)
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        view.intents = intents
        view.blockKind = kind
        view.blockID = blockID
        view.menuIsOpen = isMenuOpen
        focus.textViews[blockID] = WeakTextView(view)
        view.resolveBlock = { [weak focus] y in
            MainActor.assumeIsolated { focus?.blockID(atWindowY: y) }
        }
        view.blockSelecting = blockSelecting
        // Collapse this view's own text highlight so only the block highlight shows.
        if blockSelecting, view.selectedRange().length > 0 {
            view.setSelectedRange(NSRange(location: view.selectedRange().location, length: 0))
        }

        let id = blockID
        view.onFocusChange = { [weak focus] active in
            Task { @MainActor in
                guard let focus else { return }
                if active { focus.activeID = id }
                else if focus.activeID == id { focus.activeID = nil }
            }
        }

        if view.string != text {
            let selected = view.selectedRange()
            view.string = text
            let length = (text as NSString).length
            view.setSelectedRange(NSRange(location: min(selected.location, length), length: 0))
        }

        context.coordinator.applyStyle(to: view, kind: kind, checked: checked)
        context.coordinator.syncHeight(view)

        if let offset = focus.consume(blockID) {
            DispatchQueue.main.async {
                let length = (view.string as NSString).length
                let target = offset == .max ? length : min(max(offset, 0), length)
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: target, length: 0))
                view.scrollRangeToVisible(NSRange(location: target, length: 0))
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextEditor

        init(_ parent: BlockTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? BlockNSTextView else { return }
            applyStyle(to: view, kind: parent.kind, checked: parent.checked)
            syncHeight(view)
            parent.intents.textChanged(view.string)
            emitSlashQuery(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? BlockNSTextView else { return }
            emitSlashQuery(view)
        }

        /// Notion opens the menu on a `/` that starts a word and closes it as
        /// soon as the caret leaves that run or a space is typed.
        private func emitSlashQuery(_ view: BlockNSTextView) {
            let text = view.string as NSString
            let caret = view.selectedRange()
            guard caret.length == 0, parent.kind != .code else {
                parent.intents.slashQuery(nil)
                return
            }

            var index = caret.location - 1
            while index >= 0 {
                let character = text.character(at: index)
                if character == 0x2F { break }                       // "/"
                if character == 0x20 || character == 0x0A {
                    parent.intents.slashQuery(nil)
                    return
                }
                index -= 1
            }
            guard index >= 0 else {
                parent.intents.slashQuery(nil)
                return
            }

            // The slash must open a word, not sit inside one like "and/or".
            if index > 0 {
                let previous = text.character(at: index - 1)
                guard previous == 0x20 || previous == 0x0A else {
                    parent.intents.slashQuery(nil)
                    return
                }
            }

            let queryRange = NSRange(location: index + 1, length: caret.location - index - 1)
            parent.intents.slashQuery(text.substring(with: queryRange))
        }

        // MARK: styling

        func applyStyle(to view: BlockNSTextView, kind: BlockKind, checked: Bool) {
            guard let storage = view.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let base = BlockTypography.font(for: kind)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = BlockTypography.lineSpacing(for: kind)

            let ink = NSColor(OrbitTheme.ink(parent.scheme))
            let muted = NSColor(OrbitTheme.ink2(parent.scheme))
            let faint = NSColor(OrbitTheme.ink3(parent.scheme))

            storage.beginEditing()
            storage.setAttributes(
                [
                    .font: base,
                    .foregroundColor: kind == .quote ? muted : ink,
                    .paragraphStyle: paragraph
                ],
                range: full
            )

            if checked, full.length > 0 {
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: faint],
                    range: full
                )
            }

            if kind != .code {
                MarkdownInline.apply(
                    to: storage,
                    base: base,
                    accent: NSColor(parent.accent),
                    marker: faint,
                    scheme: parent.scheme
                )
            }

            storage.endEditing()
            view.insertionPointColor = parent.blockSelecting ? .clear : NSColor(parent.accent)
        }

        func syncHeight(_ view: BlockNSTextView) {
            guard let layoutManager = view.layoutManager, let container = view.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let minimum = ceil(BlockTypography.font(for: parent.kind).boundingRectForFont.height)
            let measured = max(ceil(used), minimum)
            guard abs(measured - parent.height) > 0.5 else { return }
            let binding = parent.$height
            DispatchQueue.main.async { binding.wrappedValue = measured }
        }
    }
}

// MARK: - Live inline markdown

/// Renders `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`, `==mark==` and
/// links as you type. Markers stay in the text — they are the source of truth —
/// but are dimmed almost to nothing so the line reads like rendered prose.
enum MarkdownInline {
    private static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![\*_\w])(\*|_)(?=[^\*_\s])([^\*_]+?)(?<=\S)\1(?![\*_\w])"#)
    private static let code = try! NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let strike = try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let highlight = try! NSRegularExpression(pattern: #"==(?=\S)(.+?)(?<=\S)=="#)
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]\n]*)\]\(([^)\s]*)\)"#)

    static func apply(
        to storage: NSTextStorage,
        base: NSFont,
        accent: NSColor,
        marker: NSColor,
        scheme: ColorScheme
    ) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        guard full.length > 0 else { return }

        let dim = marker.withAlphaComponent(0.35)
        let manager = NSFontManager.shared

        func dimMarkers(_ ranges: [NSRange]) {
            for range in ranges where range.length > 0 && NSMaxRange(range) <= full.length {
                storage.addAttribute(.foregroundColor, value: dim, range: range)
            }
        }

        // Order matters: bold before italic so `**x**` is not read as two italics.
        bold.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let outer = match.range, inner = match.range(at: 2)
            storage.addAttribute(.font, value: manager.convert(base, toHaveTrait: .boldFontMask), range: inner)
            dimMarkers([
                NSRange(location: outer.location, length: inner.location - outer.location),
                NSRange(location: inner.upperBound, length: outer.upperBound - inner.upperBound)
            ])
        }

        italic.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let outer = match.range, inner = match.range(at: 2)
            let current = storage.attribute(.font, at: inner.location, effectiveRange: nil) as? NSFont ?? base
            storage.addAttribute(.font, value: manager.convert(current, toHaveTrait: .italicFontMask), range: inner)
            dimMarkers([
                NSRange(location: outer.location, length: 1),
                NSRange(location: outer.upperBound - 1, length: 1)
            ])
        }

        strike.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let outer = match.range, inner = match.range(at: 1)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
            dimMarkers([
                NSRange(location: outer.location, length: 2),
                NSRange(location: outer.upperBound - 2, length: 2)
            ])
        }

        highlight.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let outer = match.range, inner = match.range(at: 1)
            storage.addAttribute(.backgroundColor, value: accent.withAlphaComponent(0.22), range: inner)
            dimMarkers([
                NSRange(location: outer.location, length: 2),
                NSRange(location: outer.upperBound - 2, length: 2)
            ])
        }

        code.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let outer = match.range, inner = match.range(at: 1)
            let mono = NSFont.monospacedSystemFont(ofSize: max(base.pointSize - 1.5, 10), weight: .regular)
            storage.addAttributes(
                [
                    .font: mono,
                    .foregroundColor: NSColor(OrbitTheme.rose),
                    .backgroundColor: NSColor(OrbitTheme.sunken(scheme))
                ],
                range: inner
            )
            dimMarkers([
                NSRange(location: outer.location, length: 1),
                NSRange(location: outer.upperBound - 1, length: 1)
            ])
        }

        link.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let outer = match.range, label = match.range(at: 1), url = match.range(at: 2)
            storage.addAttributes(
                [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: label
            )
            dimMarkers([
                NSRange(location: outer.location, length: 1),
                NSRange(location: label.upperBound, length: url.location - label.upperBound),
                url,
                NSRange(location: outer.upperBound - 1, length: 1)
            ])
        }
    }
}
