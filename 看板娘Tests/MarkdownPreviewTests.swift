import Testing
@testable import 看板娘

struct MarkdownPreviewTests {
    @Test
    func parserPreservesCommonBlockSyntax() {
        let markdown = """
        # Title

        A **formatted** paragraph.

        1. First
        2. Second

        - [x] Done
        - [ ] Pending

        > A quote

        ```swift
        let answer = 42
        ```
        """

        let blocks = MarkdownDocumentParser.parse(markdown)

        #expect(blocks.contains(.heading(level: 1, text: "Title")))
        #expect(blocks.contains(.paragraph("A **formatted** paragraph.")))
        #expect(blocks.contains(.list(ordered: true, items: [
            MarkdownListItem(depth: 0, text: "First", checked: nil),
            MarkdownListItem(depth: 0, text: "Second", checked: nil)
        ])))
        #expect(blocks.contains(.list(ordered: false, items: [
            MarkdownListItem(depth: 0, text: "Done", checked: true),
            MarkdownListItem(depth: 0, text: "Pending", checked: false)
        ])))
        #expect(blocks.contains(.quote("A quote")))
        #expect(blocks.contains(.code(language: "swift", content: "let answer = 42")))
    }

    @Test
    func parserTreatsSkillFrontMatterAndTablesAsBlocks() {
        let markdown = """
        ---
        name: weather
        description: Weather lookup
        ---

        | Field | Meaning |
        | --- | --- |
        | city | Target city |
        """

        let blocks = MarkdownDocumentParser.parse(markdown)

        #expect(blocks.first == .code(
            language: "YAML",
            content: "name: weather\ndescription: Weather lookup"
        ))
        #expect(blocks.contains(.table(
            headers: ["Field", "Meaning"],
            rows: [["city", "Target city"]]
        )))
    }

    @Test
    func selectableRendererProducesOneContinuousPlainTextSequence() {
        let markdown = """
        # Title

        A **formatted** paragraph.

        - First
        - Second

        ```swift
        let answer = 42
        ```
        """

        let rendered = DialogMarkdownAttributedString.make(from: markdown)

        #expect(String(rendered.characters) == """
        Title

        A formatted paragraph.

        • First
        • Second

        SWIFT
        let answer = 42
        """)
    }

    @Test
    func dialogRendererRecognizesRichBlocksAndMath() {
        #expect(DialogMarkdownNormalizer.needsRichRenderer("```bash\necho hello\n```"))
        #expect(DialogMarkdownNormalizer.needsRichRenderer("| Name | Size |\n| cache | 10 GB |"))
        #expect(DialogMarkdownNormalizer.needsRichRenderer("The area is $\\pi r^2$."))
        #expect(DialogMarkdownNormalizer.needsRichRenderer("\\[x^2 + y^2\\]"))
        #expect(!DialogMarkdownNormalizer.needsRichRenderer("A **formatted** paragraph."))
    }

    @Test
    func dialogRendererRepairsSeparatorlessTablesWithoutChangingCode() {
        let markdown = """
        | 文件夹 | 大小 | 说明 |
        | `.cache` | **10 GB** | 模型缓存 |

        ```bash
        echo 'a | b'
        echo 'c | d'
        ```
        """
        let normalized = DialogMarkdownNormalizer.normalizeLooseTables(markdown)

        #expect(normalized.contains("| 文件夹 | 大小 | 说明 |\n| --- | --- | --- |\n| `.cache`"))
        #expect(normalized.contains("echo 'a | b'\necho 'c | d'"))

        let standard = "| A | B |\n| --- | --- |\n| x | y |"
        #expect(DialogMarkdownNormalizer.normalizeLooseTables(standard) == standard)
    }
}
