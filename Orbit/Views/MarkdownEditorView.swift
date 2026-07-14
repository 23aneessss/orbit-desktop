import AppKit
import MarkdownUI
import SwiftUI

enum MarkdownFormatCommand {
    case heading(Int)
    case bold
    case italic
    case quote
    case bulletList
    case numberedList
    case taskList
    case inlineCode
    case codeBlock
    case link
    case horizontalRule
}

@MainActor
final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?

    func apply(_ command: MarkdownFormatCommand) {
        guard let textView else { return }
        let selection = textView.selectedRange()
        let source = textView.string as NSString

        switch command {
        case .heading(let level):
            prefixSelectedLines(String(repeating: "#", count: level) + " ", replacingHeading: true)
        case .quote:
            prefixSelectedLines("> ")
        case .bulletList:
            prefixSelectedLines("- ")
        case .numberedList:
            prefixSelectedLines("1. ")
        case .taskList:
            prefixSelectedLines("- [ ] ")
        case .bold:
            wrap(selection, prefix: "**", suffix: "**", placeholder: "bold text")
        case .italic:
            wrap(selection, prefix: "*", suffix: "*", placeholder: "italic text")
        case .inlineCode:
            wrap(selection, prefix: "`", suffix: "`", placeholder: "code")
        case .codeBlock:
            wrap(selection, prefix: "```\n", suffix: "\n```", placeholder: "code")
        case .link:
            let selected = selection.length > 0 ? source.substring(with: selection) : "link text"
            replace(selection, with: "[\(selected)](https://)", selectedText: selected)
        case .horizontalRule:
            replace(selection, with: "\n\n---\n\n", selectedText: nil)
        }

        textView.window?.makeFirstResponder(textView)
    }

    private func wrap(_ range: NSRange, prefix: String, suffix: String, placeholder: String) {
        guard let textView else { return }
        let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : placeholder
        replace(range, with: prefix + selected + suffix, selectedText: selected, selectionOffset: prefix.utf16.count)
    }

    private func replace(_ range: NSRange, with replacement: String, selectedText: String?, selectionOffset: Int = 1) {
        guard let textView, textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        if let selectedText {
            textView.setSelectedRange(NSRange(location: range.location + selectionOffset, length: selectedText.utf16.count))
        } else {
            textView.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
        }
    }

    private func prefixSelectedLines(_ prefix: String, replacingHeading: Bool = false) {
        guard let textView else { return }
        let source = textView.string as NSString
        let lineRange = source.lineRange(for: textView.selectedRange())
        let selectedLines = source.substring(with: lineRange)
        let trailingNewline = selectedLines.hasSuffix("\n")
        var lines = selectedLines.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if trailingNewline, lines.last == "" { lines.removeLast() }
        lines = lines.map { line in
            guard !line.isEmpty else { return line }
            if replacingHeading {
                return prefix + line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            }
            return prefix + line
        }
        let replacement = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        replace(lineRange, with: replacement, selectedText: nil)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
    }
}

struct MarkdownWorkspace: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    @StateObject private var controller = MarkdownEditorController()
    @State private var mode: Mode = .write

    private enum Mode: String, CaseIterable, Identifiable {
        case write = "Write"
        case preview = "Preview"
        case split = "Split"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(OrbitTheme.line(scheme))

            switch mode {
            case .write:
                MarkdownSourceEditor(text: $text, controller: controller)
            case .preview:
                preview
            case .split:
                HSplitView {
                    MarkdownSourceEditor(text: $text, controller: controller)
                    preview.frame(minWidth: 280)
                }
            }
        }
        .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(OrbitTheme.line(scheme)) }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            formatButton("H1", help: "Heading 1") { controller.apply(.heading(1)) }
            formatButton("H2", help: "Heading 2") { controller.apply(.heading(2)) }
            Divider().frame(height: 17).padding(.horizontal, 4)
            symbolButton("bold", help: "Bold") { controller.apply(.bold) }
            symbolButton("italic", help: "Italic") { controller.apply(.italic) }
            symbolButton("text.quote", help: "Quote") { controller.apply(.quote) }
            symbolButton("list.bullet", help: "Bulleted list") { controller.apply(.bulletList) }
            symbolButton("list.number", help: "Numbered list") { controller.apply(.numberedList) }
            symbolButton("checklist", help: "Task list") { controller.apply(.taskList) }
            symbolButton("chevron.left.forwardslash.chevron.right", help: "Inline code") { controller.apply(.inlineCode) }
            symbolButton("curlybraces.square", help: "Code block") { controller.apply(.codeBlock) }
            symbolButton("link", help: "Link") { controller.apply(.link) }
            symbolButton("minus", help: "Divider") { controller.apply(.horizontalRule) }
            Spacer(minLength: 12)
            Picker("Editor mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 218)
        }
        .padding(.horizontal, 10).frame(height: 43)
    }

    private func formatButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 27) }
            .buttonStyle(.plain).contentShape(RoundedRectangle(cornerRadius: 6)).help(help)
    }

    private func symbolButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11.5, weight: .medium)).frame(width: 27, height: 27) }
            .buttonStyle(.plain).contentShape(RoundedRectangle(cornerRadius: 6)).help(help)
    }

    private var preview: some View {
        ScrollView {
            Group {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Nothing to preview", systemImage: "doc.richtext", description: Text("Write Markdown to see the rendered page."))
                        .frame(minHeight: 390)
                } else {
                    Markdown(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
        .background(OrbitTheme.canvas(scheme).opacity(0.48))
    }
}

private struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 24, height: 22)
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
