import XCTest
@testable import Orbit

/// The block editor is a projection over the markdown already stored in
/// `Idea.content`. These tests exist to guarantee that opening a note in the
/// editor can never rewrite it, which is the one failure mode that would cost
/// real data.
final class BlockDocumentRoundTripTests: XCTestCase {
    /// Shaped after the constructs that actually appear in existing notes:
    /// `##`/`###` headings, `-` bullets with odd indentation, `---` dividers,
    /// `>` quotes, numbered runs, blank separator lines and inline `**bold**`.
    private let realWorldSample = """
    faut clarifier tous les points maintenant :
    - finaliser les projets dev en local
    - preparer le dossier presidentiel

    ## wsh dar raouf
    - la nouvelle structure tea el khedma ( les taches ytlonsaw )
       - le recrutement li ndar au debut de l'annee

    ### aspect rh
     - malgre y'avais pas des evenement interne
    - **local active** durant toutes l'annee

    ---

    > une citation
    1. premier
    2. deuxieme
    3. troisieme

    #### un titre trop profond
    | col | col |
    """

    func testUntouchedDocumentRoundTripsByteForByte() {
        let blocks = BlockDocument.parse(realWorldSample)
        XCTAssertEqual(BlockDocument.serialize(blocks), realWorldSample)
    }

    func testBlankLinesSurviveAsEmptyParagraphs() {
        let source = "one\n\n\ntwo"
        let blocks = BlockDocument.parse(source)

        XCTAssertEqual(blocks.count, 4)
        XCTAssertTrue(blocks[1].isEmptyParagraph)
        XCTAssertTrue(blocks[2].isEmptyParagraph)
        XCTAssertEqual(BlockDocument.serialize(blocks), source)
    }

    func testUnsupportedMarkdownIsPreservedVerbatimAsParagraphs() {
        // `####` and tables have no block kind, so they must survive untouched
        // rather than being normalised into something else.
        let source = "#### deep heading\n| a | b |\n|---|---|"
        let blocks = BlockDocument.parse(source)

        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .paragraph, .paragraph])
        XCTAssertEqual(BlockDocument.serialize(blocks), source)
    }

    func testEditingEveryBlockStillReparsesToTheSameStructure() {
        // Clearing `raw` forces the canonical renderer. The structure it emits
        // has to parse back into the identical set of blocks, or an edit
        // anywhere would silently reshape the rest of the document.
        var blocks = BlockDocument.parse(realWorldSample)
        for index in blocks.indices { blocks[index].edited() }

        let canonical = BlockDocument.serialize(blocks)
        let reparsed = BlockDocument.parse(canonical)

        XCTAssertEqual(reparsed.map(\.kind), blocks.map(\.kind))
        XCTAssertEqual(reparsed.map(\.text), blocks.map(\.text))
        XCTAssertEqual(reparsed.map(\.indent), blocks.map(\.indent))
        XCTAssertEqual(reparsed.map(\.checked), blocks.map(\.checked))
    }

    func testTrailingNewlineIsNotSwallowed() {
        XCTAssertEqual(BlockDocument.serialize(BlockDocument.parse("a\n")), "a\n")
        XCTAssertEqual(BlockDocument.serialize(BlockDocument.parse("")), "")
    }
}

final class BlockDocumentParsingTests: XCTestCase {
    func testRecognisesEveryBlockKind() {
        let blocks = BlockDocument.parse(
            """
            # h1
            ## h2
            ### h3
            - bullet
            1. numbered
            - [ ] open task
            - [x] done task
            > quote
            ---
            plain
            """
        )

        XCTAssertEqual(
            blocks.map(\.kind),
            [.heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .todo, .quote, .divider, .paragraph]
        )
        XCTAssertEqual(blocks[5].checked, false)
        XCTAssertEqual(blocks[6].checked, true)
        XCTAssertEqual(blocks[6].text, "done task")
    }

    func testTodoIsMatchedBeforeBulletSoCheckboxesAreNotEatenAsBullets() {
        let blocks = BlockDocument.parse("- [x] shipped")
        XCTAssertEqual(blocks.first?.kind, .todo)
        XCTAssertEqual(blocks.first?.text, "shipped")
    }

    func testIndentationMapsBothTwoAndThreeSpaceNesting() {
        let blocks = BlockDocument.parse("- a\n  - b\n   - c\n\t- d")
        XCTAssertEqual(blocks.map(\.indent), [0, 1, 1, 1])
    }

    func testFencedCodeBecomesOneBlock() {
        let blocks = BlockDocument.parse("intro\n```swift\nlet x = 1\nlet y = 2\n```\nafter")

        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .code, .paragraph])
        XCTAssertEqual(blocks[1].language, "swift")
        XCTAssertEqual(blocks[1].text, "let x = 1\nlet y = 2")
    }

    func testUnterminatedFenceStaysTextInsteadOfSwallowingTheRestOfTheNote() {
        let source = "```\nstill writing"
        let blocks = BlockDocument.parse(source)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(BlockDocument.serialize(blocks), source)
    }

    func testNumberedListsRenumberSequentiallyAndRestartAfterAnInterruption() {
        var blocks = [
            Block(kind: .numbered, text: "one"),
            Block(kind: .numbered, text: "two"),
            Block(kind: .paragraph, text: ""),
            Block(kind: .numbered, text: "fresh")
        ]
        for index in blocks.indices { blocks[index].edited() }

        XCTAssertEqual(BlockDocument.serialize(blocks), "1. one\n2. two\n\n1. fresh")
    }

    func testDisplayNumbersTrackNestingIndependently() {
        let blocks = [
            Block(kind: .numbered, text: "a"),
            Block(kind: .numbered, text: "a.1", indent: 1),
            Block(kind: .numbered, text: "a.2", indent: 1),
            Block(kind: .numbered, text: "b")
        ]

        let numbers = BlockEditorView.displayNumbers(blocks)
        XCTAssertEqual(blocks.map { numbers[$0.id] }, [1, 1, 2, 2])
    }
}

final class BlockShortcutTests: XCTestCase {
    func testTypingAHashSpaceTurnsTheBlockIntoAHeading() {
        let match = BlockShortcut.match("# ", in: .paragraph)
        XCTAssertEqual(match?.kind, .heading1)
        XCTAssertEqual(match?.text, "")
    }

    func testLongerHeadingTriggersWinOverShorterOnes() {
        XCTAssertEqual(BlockShortcut.match("### ", in: .paragraph)?.kind, .heading3)
        XCTAssertEqual(BlockShortcut.match("## ", in: .paragraph)?.kind, .heading2)
    }

    func testCheckboxAndListTriggers() {
        XCTAssertEqual(BlockShortcut.match("- ", in: .paragraph)?.kind, .bulleted)
        XCTAssertEqual(BlockShortcut.match("1. ", in: .paragraph)?.kind, .numbered)
        XCTAssertEqual(BlockShortcut.match("> ", in: .paragraph)?.kind, .quote)
        XCTAssertEqual(BlockShortcut.match("---", in: .paragraph)?.kind, .divider)

        let todo = BlockShortcut.match("[x] ", in: .paragraph)
        XCTAssertEqual(todo?.kind, .todo)
        XCTAssertEqual(todo?.checked, true)
    }

    func testTriggerKeepsTheTextTypedAfterIt() {
        let match = BlockShortcut.match("## aspect rh", in: .paragraph)
        XCTAssertEqual(match?.kind, .heading2)
        XCTAssertEqual(match?.text, "aspect rh")
    }

    func testATriggerDoesNotRefireOnABlockThatIsAlreadyThatKind() {
        XCTAssertNil(BlockShortcut.match("- already a bullet", in: .bulleted))
        XCTAssertNil(BlockShortcut.match("## already a heading", in: .heading2))
    }

    func testCodeBlocksNeverAutoFormat() {
        XCTAssertNil(BlockShortcut.match("# not a heading in code", in: .code))
        XCTAssertNil(BlockShortcut.match("- not a bullet in code", in: .code))
    }
}

// MARK: - Nested page path

@MainActor
final class IdeaHierarchyTests: XCTestCase {
    func testAncestorsReturnTheFullPathRootFirst() {
        let root = Idea(title: "ETIC")
        let middle = Idea(title: "President du club", parentID: root.id)
        let leaf = Idea(title: "points positive", parentID: middle.id)
        let all = [leaf, middle, root]

        XCTAssertEqual(IdeaHierarchy.ancestors(of: leaf, in: all).map(\.title), ["ETIC", "President du club"])
        XCTAssertEqual(IdeaHierarchy.depth(of: leaf, in: all), 2)
    }

    func testATopLevelPageHasNoAncestors() {
        let root = Idea(title: "ETIC")
        XCTAssertTrue(IdeaHierarchy.ancestors(of: root, in: [root]).isEmpty)
    }

    func testACorruptParentCycleTerminatesInsteadOfHanging() {
        // parentID is a bare UUID with no storage-level cycle check, so a
        // restored backup could produce this. It must not spin forever.
        let first = Idea(title: "A")
        let second = Idea(title: "B", parentID: first.id)
        first.parentID = second.id

        let chain = IdeaHierarchy.ancestors(of: first, in: [first, second])
        XCTAssertEqual(chain.map(\.title), ["B"])
    }

    func testAMissingParentStopsTheChainWithoutCrashing() {
        let orphan = Idea(title: "Orphan", parentID: UUID())
        XCTAssertTrue(IdeaHierarchy.ancestors(of: orphan, in: [orphan]).isEmpty)
    }
}

@MainActor
final class PageIconTests: XCTestCase {
    func testIconKeysAreNamespacedPerIdea() {
        let first = UUID(), second = UUID()
        XCTAssertNotEqual(PageIcon.key(for: first), PageIcon.key(for: second))
        XCTAssertTrue(PageIcon.key(for: first).hasPrefix(PageIcon.keyPrefix))
    }

    func testReadingFindsOnlyTheMatchingIdeaAndIgnoresAppSettings() {
        let target = UUID(), other = UUID()
        let settings = [
            AppSetting(key: "theme", value: "dark"),
            AppSetting(key: "accent", value: "#F43F5E"),
            AppSetting(key: PageIcon.key(for: target), value: "🚀"),
            AppSetting(key: PageIcon.key(for: other), value: "📄")
        ]

        XCTAssertEqual(PageIcon.read(target, from: settings), "🚀")
        XCTAssertEqual(PageIcon.read(other, from: settings), "📄")
        XCTAssertNil(PageIcon.read(UUID(), from: settings))
    }

    func testAnEmptyStoredValueReadsAsNoIcon() {
        let id = UUID()
        XCTAssertNil(PageIcon.read(id, from: [AppSetting(key: PageIcon.key(for: id), value: "")]))
    }

    func testCatalogCoversTheWholeUnicodeEmojiSet() {
        // Generated from Unicode.Scalar.Properties, so this is a floor rather
        // than an exact figure — it rises as Apple ships new Unicode revisions.
        XCTAssertGreaterThan(EmojiCatalog.all.count, 1_400)

        let names = Set(EmojiCatalog.groups.map(\.category))
        XCTAssertTrue(names.contains(.smileys))
        XCTAssertTrue(names.contains(.nature))
        XCTAssertTrue(names.contains(.flags))
        XCTAssertGreaterThan(EmojiCatalog.groups.first { $0.category == .flags }?.entries.count ?? 0, 200)
    }

    func testEveryEntryIsASingleRenderableGrapheme() {
        for entry in EmojiCatalog.all {
            XCTAssertEqual(entry.emoji.count, 1, "\(entry.emoji) is not one grapheme cluster")
            XCTAssertFalse(entry.keywords.isEmpty, "\(entry.emoji) has no search keywords")
        }
    }

    func testSearchFindsByUnicodeNameAndByAlias() {
        // Unicode name.
        XCTAssertTrue(EmojiCatalog.search("rocket").contains { $0.emoji == "🚀" })
        XCTAssertTrue(EmojiCatalog.search("octopus").contains { $0.emoji == "🐙" })
        // Alias — "smile" is nowhere in GRINNING FACE.
        XCTAssertTrue(EmojiCatalog.search("smile").contains { $0.emoji == "😀" })
        XCTAssertTrue(EmojiCatalog.search("done").contains { $0.emoji == "✅" })
        // Country name, not the ISO code.
        XCTAssertTrue(EmojiCatalog.search("france").contains { $0.emoji == "🇫🇷" })
        XCTAssertTrue(EmojiCatalog.search("zzzznope").isEmpty)
    }

    func testSearchDeduplicatesAndRanksWholeWordsFirst() {
        let matches = EmojiCatalog.search("cat")
        XCTAssertEqual(matches.count, Set(matches.map(\.emoji)).count)
        // "cat" as a whole word must outrank "caterpillar"/"delicatessen".
        let firstWholeWord = matches.firstIndex { $0.keywords.split(separator: " ").contains("cat") }
        let firstPartial = matches.firstIndex { !$0.keywords.split(separator: " ").contains("cat") }
        if let firstWholeWord, let firstPartial { XCTAssertLessThan(firstWholeWord, firstPartial) }
    }
}
