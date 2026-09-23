import AppKit
import SwiftUI
import WebKit

/// Keep ordinary replies lightweight; use the browser renderer for blocks that Text cannot lay out.
struct DialogMarkdownView: View {
    let source: String

    var body: some View {
        if DialogMarkdownNormalizer.needsRichRenderer(source) {
            DialogMarkdownWebView(source: DialogMarkdownNormalizer.normalizeLooseTables(source))
        } else {
            SelectableMarkdownText(source: source)
        }
    }
}

enum DialogMarkdownNormalizer {
    static func needsRichRenderer(_ source: String) -> Bool {
        if source.contains("```") || source.contains("~~~")
            || (source.contains("|") && source.contains("\n"))
            || source.contains("\\(") || source.contains("\\[") { return true }
        guard let firstDollar = source.firstIndex(of: "$") else { return false }
        return source[source.index(after: firstDollar)...].contains("$")
    }

    /// Some model replies omit the separator row of a pipe table. Add it only for consecutive rows.
    static func normalizeLooseTables(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0
        var fence: String?

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let currentFence = fence {
                result.append(line)
                if trimmed.hasPrefix(currentFence) { fence = nil }
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                result.append(line)
                index += 1
                continue
            }

            guard let count = tableColumnCount(line) else {
                result.append(line)
                index += 1
                continue
            }
            var end = index + 1
            while end < lines.count, tableColumnCount(lines[end]) == count { end += 1 }
            let group = Array(lines[index..<end])
            if group.count >= 2 && !isSeparator(group[1]) {
                result.append(group[0])
                result.append("| " + Array(repeating: "---", count: count).joined(separator: " | ") + " |")
                result.append(contentsOf: group.dropFirst())
            } else {
                result.append(contentsOf: group)
            }
            index = end
        }
        return result.joined(separator: "\n")
    }

    private static func tableColumnCount(_ line: String) -> Int? {
        guard !line.hasPrefix("    "), !line.hasPrefix("\t") else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix(">"), trimmed.contains("|") else { return nil }
        let cells = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
        guard cells.count >= 2, cells.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        return cells.count
    }

    private static func isSeparator(_ line: String) -> Bool {
        let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: " |"))
            .split(separator: "|", omittingEmptySubsequences: false)
        return !cells.isEmpty && cells.allSatisfy {
            let cell = $0.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            return cell.count >= 3 && cell.allSatisfy { $0 == "-" }
        }
    }
}

private struct DialogMarkdownWebView: View {
    let source: String
    @State private var contentHeight: CGFloat = 24

    var body: some View {
        MarkdownWebViewRepresentable(source: source, contentHeight: $contentHeight)
            .frame(height: contentHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownWebViewRepresentable: NSViewRepresentable {
    let source: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "markdownHeight")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        context.coordinator.source = source
        context.coordinator.webView = webView
        context.coordinator.installWheelRouter()

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Markdown")
            ?? Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.source = source
        context.coordinator.renderIfReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.removeWheelRouter()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "markdownHeight")
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var contentHeight: Binding<CGFloat>
        var source = ""
        var renderedSource: String?
        var isReady = false
        weak var webView: WKWebView?
        private var wheelMonitor: Any?

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        func installWheelRouter() {
            guard wheelMonitor == nil else { return }
            // WKWebView consumes vertical wheel events even when its document cannot scroll.
            // Route those events to the enclosing conversation scroll view; keep horizontal
            // events inside WebKit for wide tables and code blocks.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let webView = self.webView,
                      let window = webView.window, event.window === window,
                      webView.bounds.contains(webView.convert(event.locationInWindow, from: nil)),
                      !event.modifierFlags.contains(.shift),
                      abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
                      let outerScrollView = webView.enclosingScrollView else { return event }

                outerScrollView.scrollWheel(with: event)
                return nil
            }
        }

        func removeWheelRouter() {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            wheelMonitor = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            renderIfReady()
        }

        func renderIfReady() {
            guard isReady, source != renderedSource, let webView,
                  let data = try? JSONEncoder().encode(source),
                  let argument = String(data: data, encoding: .utf8) else { return }
            renderedSource = source
            webView.evaluateJavaScript("window.renderMarkdown(\(argument));", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let height = max(24, CGFloat(number.doubleValue))
            if contentHeight.wrappedValue != height { contentHeight.wrappedValue = height }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
                return .cancel
            } else {
                return .allow
            }
        }
    }
}
