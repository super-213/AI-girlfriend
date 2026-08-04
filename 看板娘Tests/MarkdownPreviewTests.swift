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
}
