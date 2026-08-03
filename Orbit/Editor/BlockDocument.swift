import Foundation

/// A Notion-style block. Blocks are an in-memory projection of the markdown
/// stored in `Idea.content` — there is no separate persisted block entity, so
/// existing notes open as blocks with no migration.
///
/// `raw` holds the exact source line(s) a block was parsed from and is cleared
/// the moment the block is edited. Serializing an untouched block replays `raw`
/// verbatim, which makes round-tripping an unedited document byte-identical by
/// construction rather than by regex luck.
struct Block: Identifiable, Equatable {
    var id = UUID()
    var kind: BlockKind = .paragraph
    var text: String = ""
    var checked: Bool = false
    var indent: Int = 0
    var language: String = ""
    /// Set only on `.page` blocks — the `Idea` this block links to.
    var pageID: UUID?
    var raw: String?





    init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        checked: Bool = false,
        indent: Int = 0,
        language: String = "",
        pageID: UUID? = nil,
        raw: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.checked = checked
        self.indent = indent
        self.language = language
        self.pageID = pageID
        self.raw = raw
    }

    /// Any mutation made through the editor goes through here so a block can
    /// never keep a stale `raw` that no longer matches its fields.
    mutating func edited() { raw = nil }

    var isEmptyParagraph: Bool { kind == .paragraph && text.isEmpty }
}

enum BlockKind: String, CaseIterable, Equatable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulleted
    case numbered
    case todo
    case quote
    case code
    case divider
    case page

    var isList: Bool { self == .bulleted || self == .numbered || self == .todo }

    /// `.page` is created by the slash menu against a real sub-page record, so
    /// it is not something a plain text block can be converted into.
    static var convertible: [BlockKind] { allCases.filter { $0 != .page } }

    /// Blocks whose kind carries to the next block when you press Return.
    var continuesOnReturn: Bool { isList || self == .quote }

    var title: String {
        switch self {
        case .paragraph: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulleted: "Bulleted list"
        case .numbered: "Numbered list"
        case .todo: "To-do list"
        case .quote: "Quote"
        case .code: "Code"
        case .divider: "Divider"
        case .page: "Page"
        }
    }

    var subtitle: String {
        switch self {
        case .paragraph: "Just start writing with plain text."
        case .heading1: "Big section heading."
        case .heading2: "Medium section heading."
        case .heading3: "Small section heading."
        case .bulleted: "Create a simple bulleted list."
        case .numbered: "Create a list with numbering."
        case .todo: "Track tasks with a checkbox."
        case .quote: "Capture a quote."
        case .code: "Capture a snippet of code."
        case .divider: "Visually divide blocks."
        case .page: "Create a sub-page inside this idea."
        }
    }

    var symbol: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bulleted: "list.bullet"
        case .numbered: "list.number"
        case .todo: "checklist"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        case .page: "doc.text"
        }
    }

    /// Words the slash menu matches against, beyond the title.
    var keywords: [String] {
        switch self {
        case .paragraph: ["text", "paragraph", "plain"]
        case .heading1: ["h1", "heading", "title"]
        case .heading2: ["h2", "heading", "subtitle"]
        case .heading3: ["h3", "heading"]
        case .bulleted: ["bullet", "list", "ul", "unordered"]
        case .numbered: ["number", "list", "ol", "ordered"]
        case .todo: ["todo", "task", "checkbox", "check"]
        case .quote: ["quote", "blockquote", "cite"]
        case .code: ["code", "snippet", "pre"]
        case .divider: ["divider", "separator", "rule", "line", "hr"]
        case .page: ["page", "subpage", "sub-page", "doc", "document", "nested"]
        }
    }
}

// MARK: - Markdown <-> blocks

enum BlockDocument {
    static let maxIndent = 6

    /// One source line becomes one block, which is exactly Notion's model and
    /// keeps the mapping reversible. Fenced code is the sole multi-line block.
    static func parse(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if let fence = openingFence(in: line) {
                var body: [String] = []
                var cursor = index + 1
                var closed = false
                while cursor < lines.count {
                    if isClosingFence(lines[cursor], matching: fence.marker) {
                        closed = true
                        break
                    }
                    body.append(lines[cursor])
                    cursor += 1
                }
                // An unterminated fence is not a code block — fall through and
                // treat the line as ordinary text so nothing is swallowed.
                if closed {
                    let rawLines = Array(lines[index...cursor])
                    blocks.append(
                        Block(
                            kind: .code,
                            text: body.joined(separator: "\n"),
                            language: fence.language,
                            raw: rawLines.joined(separator: "\n")
                        )
                    )
                    index = cursor + 1
                    continue
                }
            }

            blocks.append(parseLine(line))
            index += 1
        }

        return blocks
    }

    static func serialize(_ blocks: [Block]) -> String {
        var lines: [String] = []
        var counters: [Int: Int] = [:]

        for block in blocks {
            // Numbering restarts whenever a non-numbered block interrupts the
            // run, and each indent level counts independently.
            if block.kind == .numbered {
                counters = counters.filter { $0.key <= block.indent }
                counters[block.indent, default: 0] += 1
            } else {
                counters.removeAll()
            }

            if let raw = block.raw {
                lines.append(raw)
            } else {
                lines.append(render(block, number: counters[block.indent] ?? 1))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: line parsing

    private static func parseLine(_ line: String) -> Block {
        let lead = line.prefix { $0 == " " || $0 == "\t" }
        let indent = indentLevel(for: String(lead))
        let body = String(line.dropFirst(lead.count))

        if isDivider(body) {
            return Block(kind: .divider, text: "", indent: 0, raw: line)
        }

        if let (level, rest) = headingPrefix(body) {
            let kind: BlockKind = level == 1 ? .heading1 : (level == 2 ? .heading2 : .heading3)
            return Block(kind: kind, text: rest, indent: 0, raw: line)
        }

        if let (checked, rest) = todoPrefix(body) {
            return Block(kind: .todo, text: rest, checked: checked, indent: indent, raw: line)
        }

        if let rest = bulletPrefix(body) {
            return Block(kind: .bulleted, text: rest, indent: indent, raw: line)
        }

        if let rest = numberPrefix(body) {
            return Block(kind: .numbered, text: rest, indent: indent, raw: line)
        }

        if let rest = quotePrefix(body) {
            return Block(kind: .quote, text: rest, indent: 0, raw: line)
        }

        if let page = pageReference(body) {
            return Block(kind: .page, text: page.title, indent: indent, pageID: page.id, raw: line)
        }

        // Anything unrecognised — including `#### deep headings`, tables and
        // indented code — stays a paragraph holding the untouched source, so it
        // survives a round trip instead of being silently rewritten.
        return Block(kind: .paragraph, text: line, indent: 0, raw: line)
    }

    private static func render(_ block: Block, number: Int) -> String {
        let pad = String(repeating: "  ", count: max(0, block.indent))
        switch block.kind {
        case .paragraph: return block.text
        case .heading1: return "# " + block.text
        case .heading2: return "## " + block.text
        case .heading3: return "### " + block.text
        case .bulleted: return pad + "- " + block.text
        case .numbered: return pad + "\(number). " + block.text
        case .todo: return pad + (block.checked ? "- [x] " : "- [ ] ") + block.text
        case .quote: return "> " + block.text
        case .divider: return "---"
        case .page:
            guard let pageID = block.pageID else { return block.text }
            return pad + "[\(block.text)](\(BlockDocument.pageScheme)\(pageID.uuidString))"
        case .code:
            let head = block.language.isEmpty ? "```" : "```" + block.language
            return ([head] + block.text.components(separatedBy: "\n") + ["```"]).joined(separator: "\n")
        }
    }

    // MARK: prefix matchers

    static func indentLevel(for lead: String) -> Int {
        // Tabs count as one level, spaces as one level per two columns, which
        // maps both `  - ` and `   - ` in existing notes onto level 1.
        var columns = 0
        for character in lead {
            if character == "\t" { columns += 2 } else { columns += 1 }
        }
        return min(columns / 2, maxIndent)
    }

    private static func isDivider(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        for marker in ["-", "*", "_"] where trimmed.allSatisfy({ String($0) == marker }) {
            return true
        }
        return false
    }

    private static func headingPrefix(_ body: String) -> (Int, String)? {
        let hashes = body.prefix { $0 == "#" }
        guard (1...3).contains(hashes.count) else { return nil }
        let rest = body.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return (hashes.count, String(rest.dropFirst()))
    }

    private static func todoPrefix(_ body: String) -> (Bool, String)? {
        for marker in ["- ", "* ", "+ "] where body.hasPrefix(marker) {
            let rest = body.dropFirst(marker.count)
            for (token, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where rest.hasPrefix(token) {
                return (checked, String(rest.dropFirst(token.count)))
            }
            // `- [x]` with nothing after it is still a checkbox.
            for (token, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where rest == token {
                return (checked, "")
            }
        }
        return nil
    }

    private static func bulletPrefix(_ body: String) -> String? {
        for marker in ["- ", "* ", "+ "] where body.hasPrefix(marker) {
            return String(body.dropFirst(marker.count))
        }
        // A lone `-` on its own line is an empty bullet, not a paragraph.
        if body == "-" || body == "*" || body == "+" { return "" }
        return nil
    }

    private static func numberPrefix(_ body: String) -> String? {
        let digits = body.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = body.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        let after = rest.dropFirst()
        if after.isEmpty { return "" }
        guard after.first == " " else { return nil }
        return String(after.dropFirst())
    }

    /// Sub-pages are stored as an ordinary markdown link, so a note stays
    /// readable (and portable) outside Orbit.
    static let pageScheme = "orbit://idea/"

    private static let pagePattern = try! NSRegularExpression(
        pattern: #"^\[([^\]]*)\]\(orbit://idea/([0-9A-Fa-f-]{36})\)$"#
    )

    private static func pageReference(_ body: String) -> (title: String, id: UUID)? {
        let range = NSRange(body.startIndex..., in: body)
        guard let match = pagePattern.firstMatch(in: body, range: range),
              match.numberOfRanges >= 3,
              let titleRange = Range(match.range(at: 1), in: body),
              let idRange = Range(match.range(at: 2), in: body),
              let id = UUID(uuidString: String(body[idRange])) else { return nil }
        return (String(body[titleRange]), id)
    }

    private static func quotePrefix(_ body: String) -> String? {
        if body.hasPrefix("> ") { return String(body.dropFirst(2)) }
        if body == ">" { return "" }
        return nil
    }

    private static func openingFence(in line: String) -> (marker: String, language: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let language = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            guard !language.contains(marker) else { return nil }
            return (marker, language)
        }
        return nil
    }

    private static func isClosingFence(_ line: String, matching marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = marker.first else { return false }
        return trimmed.hasPrefix(marker) && trimmed.allSatisfy { $0 == first }
    }

    // MARK: - Paste

    /// Splices pasted markdown into a document as real blocks.
    ///
    /// A block lays out exactly one logical line, so letting a multi-line paste
    /// land in a single block renders clipped and re-serializes as a heading
    /// that swallowed a list. Pasting has to be a structural edit.
    ///
    /// Returns the rewritten document and where the caret should land, or nil
    /// if there was nothing to paste.
    static func paste(
        _ markdown: String,
        into blocks: [Block],
        at index: Int,
        caret: Int
    ) -> (blocks: [Block], caretID: UUID, caretOffset: Int)? {
        guard blocks.indices.contains(index) else { return nil }

        // Pasting out of a browser or Windows brings CRLF along with it.
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var incoming = parse(normalized)
        guard !incoming.isEmpty else { return nil }

        let target = blocks[index]
        let characters = Array(target.text)
        let cut = min(max(caret, 0), characters.count)
        let head = String(characters[..<cut])
        let tail = String(characters[cut...])

        if !head.isEmpty {
            if incoming[0].kind == .paragraph {
                // Plain prose flows into the text already left of the caret and
                // keeps that block's own kind, so pasting a sentence at the end
                // of a bullet extends the bullet.
                incoming[0].kind = target.kind
                incoming[0].checked = target.checked
                incoming[0].indent = target.indent
                incoming[0].text = head + incoming[0].text
                incoming[0].edited()
            } else {
                // A pasted heading or list item keeps its own kind instead of
                // being flattened into the paragraph it landed in.
                var lead = target
                lead.text = head
                lead.edited()
                incoming.insert(lead, at: 0)
            }
        }

        if !tail.isEmpty {
            var trail = target
            trail.id = UUID()
            trail.text = tail
            trail.edited()
            incoming.append(trail)
        }

        // Reusing the focused block's id keeps its text view alive across the
        // splice instead of tearing it down mid-paste.
        incoming[0].id = target.id

        let caretIndex = max(0, tail.isEmpty ? incoming.count - 1 : incoming.count - 2)
        let landing = incoming[caretIndex]

        var result = blocks
        result.replaceSubrange(index...index, with: incoming)
        return (result, landing.id, landing.text.count)
    }
}

// MARK: - Markdown shortcuts typed inside a block

enum BlockShortcut {
    /// Notion converts a block the instant you type `# `, `- `, `1. ` and the
    /// like. Returns the new kind plus the text with the trigger stripped.
    static func match(_ text: String, in kind: BlockKind) -> (kind: BlockKind, text: String, checked: Bool)? {
        guard kind != .code else { return nil }

        for (trigger, checked) in [("[] ", false), ("[ ] ", false), ("[x] ", true), ("[X] ", true)]
        where text.hasPrefix(trigger) {
            return (.todo, String(text.dropFirst(trigger.count)), checked)
        }

        let table: [(String, BlockKind)] = [
            ("### ", .heading3),
            ("## ", .heading2),
            ("# ", .heading1),
            ("- ", .bulleted),
            ("* ", .bulleted),
            ("+ ", .bulleted),
            ("> ", .quote)
        ]

        for (trigger, target) in table where text.hasPrefix(trigger) {
            guard target != kind else { return nil }
            return (target, String(text.dropFirst(trigger.count)), false)
        }

        if text.hasPrefix("```") {
            return (.code, String(text.dropFirst(3)), false)
        }

        if text == "---" || text == "***" {
            return (.divider, "", false)
        }

        // `1. `, `2) ` and friends open a numbered list.
        let digits = text.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = text.dropFirst(digits.count)
            if let separator = rest.first, separator == "." || separator == ")", rest.dropFirst().first == " " {
                guard kind != .numbered else { return nil }
                return (.numbered, String(rest.dropFirst(2)), false)
            }
        }

        return nil
    }
}
