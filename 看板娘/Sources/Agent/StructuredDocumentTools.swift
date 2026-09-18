//
//  StructuredDocumentTools.swift
//  看板娘
//
//  Lightweight Office Open XML extraction and creation for Agent workflows.
//

import AppKit
import Foundation

enum OfficeDocumentExtractor {
    static func extract(path: String, extension ext: String) -> String? {
        switch ext {
        case "docx":
            return xmlText(entry: "word/document.xml", archive: path)
                .replacingOccurrences(of: "\t", with: "\n")
        case "pptx":
            let entries = archiveEntries(path).filter { $0.range(of: #"^ppt/slides/slide\d+\.xml$"#, options: .regularExpression) != nil }.sorted(by: naturalOrder)
            return entries.enumerated().map { index, entry in
                "## 幻灯片 \(index + 1)\n" + xmlText(entry: entry, archive: path)
            }.joined(separator: "\n\n")
        case "xlsx":
            let shared = sharedStrings(archive: path)
            let sheets = archiveEntries(path).filter { $0.range(of: #"^xl/worksheets/sheet\d+\.xml$"#, options: .regularExpression) != nil }.sorted(by: naturalOrder)
            return sheets.enumerated().map { index, entry in
                let xml = archiveData(entry: entry, archive: path) ?? ""
                return "## 工作表 \(index + 1)\n" + spreadsheetRows(xml: xml, shared: shared)
            }.joined(separator: "\n\n")
        default:
            return nil
        }
    }

    private static func archiveEntries(_ path: String) -> [String] {
        run("/usr/bin/unzip", ["-Z1", path]).output.split(separator: "\n").map(String.init)
    }

    private static func archiveData(entry: String, archive: String) -> String? {
        let result = run("/usr/bin/unzip", ["-p", archive, entry])
        return result.status == 0 ? result.output : nil
    }

    private static func xmlText(entry: String, archive: String) -> String {
        guard let xml = archiveData(entry: entry, archive: archive) else { return "" }
        let paragraphAware = xml
            .replacingOccurrences(of: #"</w:p>|</a:p>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"</w:tc>"#, with: "\t", options: .regularExpression)
        let values = matches(pattern: #"<(?:w:t|a:t)(?:\s[^>]*)?>(.*?)</(?:w:t|a:t)>"#, in: paragraphAware)
        return values.map(decodeXML).joined(separator: " ").replacingOccurrences(of: " \n ", with: "\n")
    }

    private static func sharedStrings(archive: String) -> [String] {
        guard let xml = archiveData(entry: "xl/sharedStrings.xml", archive: archive) else { return [] }
        return matches(pattern: #"<si(?:\s[^>]*)?>(.*?)</si>"#, in: xml).map { item in
            matches(pattern: #"<t(?:\s[^>]*)?>(.*?)</t>"#, in: item).map(decodeXML).joined()
        }
    }

    private static func spreadsheetRows(xml: String, shared: [String]) -> String {
        matches(pattern: #"<row(?:\s[^>]*)?>(.*?)</row>"#, in: xml).map { row in
            matches(pattern: #"<c([^>]*)>(.*?)</c>"#, in: row).map { cell in
                if cell.hasPrefix("@shared:"), let index = Int(cell.dropFirst(8)), shared.indices.contains(index) {
                    return shared[index]
                }
                return cell
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    // Captures cell attribute/body together and resolves shared strings or inline values.
    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            if pattern.hasPrefix("<c") && match.numberOfRanges > 2 {
                let attrs = ns.substring(with: match.range(at: 1))
                let body = ns.substring(with: match.range(at: 2))
                let raw = matches(pattern: #"<(?:v|t)(?:\s[^>]*)?>(.*?)</(?:v|t)>"#, in: body).first ?? ""
                if attrs.contains(#"t="s""#), let index = Int(raw), index >= 0 {
                    // Shared values are replaced by spreadsheetRows after this helper; prefix keeps type.
                    return "@shared:\(index)"
                }
                return decodeXML(raw)
            }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private static func decodeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func naturalOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedAscending
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

@MainActor
final class WriteDocumentTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "write_document",
        description: "创建或覆盖 PDF、DOCX、XLSX 或 PPTX 文档。DOCX/PDF 使用 title 和 content；XLSX 使用 rows 二维字符串数组；PPTX 使用 slides（title/body）。写入前显示计划并需确认，可撤销。",
        parameters: [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "目标绝对路径"],
                "title": ["type": "string"],
                "content": ["type": "string"],
                "rows": ["type": "array", "items": ["type": "array", "items": ["type": "string"]]],
                "slides": ["type": "array", "items": ["type": "object", "properties": ["title": ["type": "string"], "body": ["type": "string"]]]],
                "overwrite": ["type": "boolean"]
            ],
            "required": ["path"], "additionalProperties": false
        ]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String {
        let path = arguments["path"] as? String ?? ""
        let rows = (arguments["rows"] as? [[String]])?.count ?? 0
        let slides = (arguments["slides"] as? [[String: Any]])?.count ?? 0
        return "创建结构化文档 \(path)\n表格行数：\(rows)；幻灯片：\(slides)\n现有文件会先备份，操作后可撤销。"
    }

    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard let rawPath = arguments["path"] as? String, NSString(string: rawPath).expandingTildeInPath.hasPrefix("/") else {
            completion(.failure("缺少有效的绝对路径")); return
        }
        let path = URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath).standardizedFileURL.path
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard ["pdf", "docx", "xlsx", "pptx"].contains(ext) else { completion(.failure("仅支持 PDF、DOCX、XLSX 和 PPTX")); return }
        guard AgentFileAccessStore.shared.canWrite(path) else { completion(.failure(AgentFileAccessStore.denialMessage(path: url.deletingLastPathComponent().path))); return }
        let existed = FileManager.default.fileExists(atPath: path)
        guard !existed || (arguments["overwrite"] as? Bool ?? false) else { completion(.failure("目标已存在，请明确设置 overwrite")); return }
        do {
            let backup = existed ? try AgentFileUndoStore.shared.prepareBackup(for: path) : nil
            switch ext {
            case "pdf": try writePDF(url: url, title: arguments["title"] as? String ?? "", content: arguments["content"] as? String ?? "")
            case "docx": try writeDOCX(url: url, title: arguments["title"] as? String ?? "", content: arguments["content"] as? String ?? "")
            case "xlsx": try writeXLSX(url: url, rows: arguments["rows"] as? [[String]] ?? [])
            case "pptx": try writePPTXWithKeynote(url: url, slides: arguments["slides"] as? [[String: Any]] ?? [])
            default: break
            }
            AgentFileUndoStore.shared.push(kind: existed ? .restoreBackup : .removeCreated, originalPath: path, backupPath: backup, summary: "创建 \(url.lastPathComponent)")
            completion(.success("已创建 \(path)"))
        } catch { completion(.failure("创建文档失败：\(error.localizedDescription)")) }
    }

    private func writePDF(url: URL, title: String, content: String) throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 760))
        let text = ([title, content].filter { !$0.isEmpty }).joined(separator: "\n\n")
        view.string = text
        view.font = NSFont.systemFont(ofSize: 13)
        try view.dataWithPDF(inside: view.bounds).write(to: url, options: .atomic)
    }

    private func writeDOCX(url: URL, title: String, content: String) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".rtf")
        defer { try? FileManager.default.removeItem(at: temp) }
        let text = ([title, content].filter { !$0.isEmpty }).joined(separator: "\n\n")
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        try attributed.rtf(from: NSRange(location: 0, length: attributed.length))?.write(to: temp)
        let result = run("/usr/bin/textutil", ["-convert", "docx", "-output", url.path, temp.path], cwd: nil)
        if result.status != 0 { throw error(result.output) }
    }

    private func writeXLSX(url: URL, rows: [[String]]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("""
        <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
        """, at: root.appendingPathComponent("[Content_Types].xml"))
        try write(#"<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#, at: root.appendingPathComponent("_rels/.rels"))
        try write(#"<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"#, at: root.appendingPathComponent("xl/workbook.xml"))
        try write(#"<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#, at: root.appendingPathComponent("xl/_rels/workbook.xml.rels"))
        let rowXML = rows.enumerated().map { rowIndex, row in
            let cells = row.enumerated().map { col, value in "<c r=\"\(columnName(col))\(rowIndex + 1)\" t=\"inlineStr\"><is><t>\(escape(value))</t></is></c>" }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()
        try write("<?xml version=\"1.0\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\(rowXML)</sheetData></worksheet>", at: root.appendingPathComponent("xl/worksheets/sheet1.xml"))
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let result = run("/usr/bin/zip", ["-qr", url.path, "."], cwd: root)
        if result.status != 0 { throw error(result.output) }
    }

    private func writePPTXWithKeynote(url: URL, slides: [[String: Any]]) throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Keynote") != nil else { throw error("创建 PPTX 需要安装 Keynote") }
        let slideScripts = (slides.isEmpty ? [["title": "", "body": ""]] : slides).map { slide in
            let title = appleEscape(slide["title"] as? String ?? "")
            let body = appleEscape(slide["body"] as? String ?? "")
            return "set s to make new slide at end of slides of d with properties {base slide:master slide \"Title & Bullets\"}\nset object text of default title item of s to \"\(title)\"\nset object text of default body item of s to \"\(body)\""
        }.joined(separator: "\n")
        let script = "tell application \"Keynote\"\nset d to make new document\n\(slideScripts)\ndelete slide 1 of d\nexport d to POSIX file \"\(appleEscape(url.path))\" as Microsoft PowerPoint\nclose d saving no\nend tell"
        let result = run("/usr/bin/osascript", ["-e", script], cwd: nil)
        if result.status != 0 { throw error(result.output) }
    }

    private func write(_ string: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }
    private func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    private func appleEscape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") }
    private func columnName(_ index: Int) -> String { var n = index + 1; var value = ""; while n > 0 { n -= 1; value = String(UnicodeScalar(65 + n % 26)!) + value; n /= 26 }; return value }
    private func error(_ message: String) -> Error { NSError(domain: "StructuredDocument", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func run(_ executable: String, _ arguments: [String], cwd: URL?) -> (status: Int32, output: String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.currentDirectoryURL = cwd
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
