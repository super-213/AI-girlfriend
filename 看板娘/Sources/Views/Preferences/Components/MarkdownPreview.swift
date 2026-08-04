//
//  MarkdownPreview.swift
//  看板娘
//
//  轻量、原生的块级 Markdown 预览器。
//

import SwiftUI

struct MarkdownPreview: View {
    let source: String

    private var blocks: [MarkdownBlock] {
        MarkdownDocumentParser.parse(source)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown 预览")
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [MarkdownListItem])
    case quote(String)
    case code(language: String?, content: String)
    case divider
    case table(headers: [String], rows: [[String]])
}

struct MarkdownListItem: Equatable {
    let depth: Int
    let text: String
    let checked: Bool?
}

enum MarkdownDocumentParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        // YAML front matter is not standard Markdown, but skill files commonly use it.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closingIndex = lines.dropFirst().firstIndex(where: {
               $0.trimmingCharacters(in: .whitespaces) == "---"
           }) {
            let metadata = lines[1..<closingIndex].joined(separator: "\n")
            blocks.append(.code(language: "YAML", content: metadata))
            index = closingIndex + 1
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = fenceOpening(in: trimmed) {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count))
                    .trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(
                    language: language.isEmpty ? nil : language,
                    content: codeLines.joined(separator: "\n")
                ))
                continue
            }

            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                flushParagraph()
                var codeLines: [String] = []
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.hasPrefix("    ") {
                        codeLines.append(String(codeLine.dropFirst(4)))
                    } else if codeLine.hasPrefix("\t") {
                        codeLines.append(String(codeLine.dropFirst()))
                    } else if codeLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        codeLines.append("")
                    } else {
                        break
                    }
                    index += 1
                }
                blocks.append(.code(language: nil, content: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isTableHeader(at: index, lines: lines) {
                flushParagraph()
                let headers = tableCells(in: lines[index])
                index += 2
                var rows: [[String]] = []
                while index < lines.count,
                      lines[index].contains("|"),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(in: lines[index]))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(
                        String(quoteLine.dropFirst())
                            .trimmingCharacters(in: .whitespaces)
                    )
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if unorderedItem(in: line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while index < lines.count, let item = unorderedItem(in: lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.list(ordered: false, items: items))
                continue
            }

            if orderedItem(in: line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while index < lines.count, let item = orderedItem(in: lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.list(ordered: true, items: items))
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func fenceOpening(in line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " " else { return nil }
        return (
            hashes.count,
            String(line.dropFirst(hashes.count + 1)).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func unorderedItem(in line: String) -> MarkdownListItem? {
        let leadingCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let trimmed = line.dropFirst(leadingCount)
        guard trimmed.count >= 2,
              ["-", "*", "+"].contains(String(trimmed.prefix(1))),
              trimmed.dropFirst().first == " " else { return nil }

        var text = String(trimmed.dropFirst(2))
        var checked: Bool?
        if text.hasPrefix("[ ] ") {
            checked = false
            text = String(text.dropFirst(4))
        } else if text.lowercased().hasPrefix("[x] ") {
            checked = true
            text = String(text.dropFirst(4))
        }
        return MarkdownListItem(depth: leadingCount / 2, text: text, checked: checked)
    }

    private static func orderedItem(in line: String) -> MarkdownListItem? {
        let leadingCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let trimmed = line.dropFirst(leadingCount)
        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let remainder = trimmed.dropFirst(digits.count)
        guard let punctuation = remainder.first,
              punctuation == "." || punctuation == ")",
              remainder.dropFirst().first == " " else { return nil }
        return MarkdownListItem(
            depth: leadingCount / 2,
            text: String(remainder.dropFirst(2)),
            checked: nil
        )
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableHeader(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let separators = tableCells(in: lines[index + 1])
        guard !separators.isEmpty else { return false }
        return separators.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    @ViewBuilder
    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .tracking(level == 1 ? -0.35 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 8 : 3)

        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .list(ordered, items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MarkdownListRow(item: item, index: index, ordered: ordered)
                }
            }

        case let .quote(text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: 3)

                Text(inlineMarkdown(text))
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)

        case let .code(language, content):
            MarkdownCodeBlock(language: language, content: content)

        case .divider:
            Divider()
                .padding(.vertical, 4)

        case let .table(headers, rows):
            MarkdownTable(headers: headers, rows: rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.weight(.bold)
        case 2: .title2.weight(.bold)
        case 3: .title3.weight(.semibold)
        case 4: .headline
        case 5: .subheadline.weight(.semibold)
        default: .caption.weight(.semibold)
        }
    }
}

private struct MarkdownListRow: View {
    let item: MarkdownListItem
    let index: Int
    let ordered: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
                .frame(width: 20, alignment: .trailing)

            Text(inlineMarkdown(item.text))
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.depth) * 18)
    }

    @ViewBuilder
    private var marker: some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color.accentColor : .secondary)
                .accessibilityLabel(checked ? "已完成" : "未完成")
        } else if ordered {
            Text("\(index + 1).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Circle()
                .fill(Color.secondary)
                .frame(width: item.depth == 0 ? 6 : 5, height: item.depth == 0 ? 6 : 5)
                .accessibilityHidden(true)
        }
    }
}

private struct MarkdownCodeBlock: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))

                Divider()
            }

            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                tableRow(headers, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    tableRow(row, isHeader: false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        GridRow {
            ForEach(0..<columnCount, id: \.self) { index in
                Text(inlineMarkdown(index < cells.count ? cells[index] : ""))
                    .font(isHeader ? .body.weight(.semibold) : .body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minWidth: 100, maxWidth: 240, alignment: .leading)
                    .background(isHeader ? Color.secondary.opacity(0.1) : Color.clear)
            }
        }
    }
}

private func inlineMarkdown(_ source: String) -> AttributedString {
    (try? AttributedString(
        markdown: source,
        options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
    )) ?? AttributedString(source)
}
