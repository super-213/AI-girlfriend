//
//  StreamingTextCoalescer.swift
//  看板娘
//
//  合并高频流式文本回调，避免每个 token 都触发一次 SwiftUI 布局。
//

import Foundation

@MainActor
final class StreamingTextCoalescer {
    typealias FlushHandler = @MainActor (String) -> Void

    private let interval: Duration
    private let onFlush: FlushHandler
    private var pendingText = ""
    private var scheduledFlush: Task<Void, Never>?

    init(
        interval: Duration = .milliseconds(40),
        onFlush: @escaping FlushHandler
    ) {
        self.interval = interval
        self.onFlush = onFlush
    }

    func append(_ text: String) {
        guard !text.isEmpty else { return }
        pendingText += text
        guard scheduledFlush == nil else { return }

        scheduledFlush = Task { @MainActor [weak self, interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// 立即发布待处理文本。请求结束或状态切换时调用，保证不丢失尾部内容。
    func flush() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard !pendingText.isEmpty else { return }

        let text = pendingText
        pendingText = ""
        onFlush(text)
    }

    /// 丢弃待处理文本。开始新请求或取消旧请求时调用，避免跨请求串流。
    func reset() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingText = ""
    }
}
