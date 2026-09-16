//
//  NativeAnimatedImage.swift
//  看板娘
//

import AppKit
import ImageIO
import SwiftUI

/// Displays GIF and APNG animations with the system ImageIO decoder.
///
/// The decoder keeps only the displayed frame and one prefetched frame alive.
/// Frames are decoded off the main thread and assigned directly to a backing
/// layer, preserving source pixels, alpha, and per-frame timing without causing
/// a SwiftUI body update for every frame.
struct NativeAnimatedImage: NSViewRepresentable {
    let url: URL
    let loops: Bool

    func makeNSView(context: Context) -> NativeAnimatedImageNSView {
        let imageView = NativeAnimatedImageNSView()
        imageView.configure(url: url, loops: loops)
        return imageView
    }

    func updateNSView(_ imageView: NativeAnimatedImageNSView, context: Context) {
        imageView.configure(url: url, loops: loops)
    }

    static func dismantleNSView(_ imageView: NativeAnimatedImageNSView, coordinator: ()) {
        imageView.stopAnimating()
    }
}

@MainActor
final class NativeAnimatedImageNSView: NSView {
    private struct Configuration: Equatable {
        let url: URL
        let loops: Bool
    }

    private var configuration: Configuration?
    private var animationGeneration: UInt = 0
    private var player: ImageIOAnimationPlayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    func configure(url: URL, loops: Bool) {
        let nextConfiguration = Configuration(url: url, loops: loops)
        guard configuration != nextConfiguration else { return }

        stopAnimating(clearFrame: true)
        configuration = nextConfiguration
        animationGeneration &+= 1
        let generation = animationGeneration

        let player = ImageIOAnimationPlayer(url: url, loops: loops) { [weak self] image in
            guard let self, self.animationGeneration == generation else { return }
            self.display(image)
        }
        self.player = player
        player.start()
    }

    func stopAnimating() {
        stopAnimating(clearFrame: false)
    }

    private func stopAnimating(clearFrame: Bool) {
        animationGeneration &+= 1
        player?.cancel()
        player = nil
        configuration = nil
        if clearFrame {
            layer?.contents = nil
        }
    }

    private func display(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }
}

private final class ImageIOAnimationPlayer: @unchecked Sendable {
    private let url: URL
    private let loops: Bool
    private let frameHandler: FrameHandler
    private let queue = DispatchQueue(
        label: "com.kanban-girl.imageio-animation",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    private let cancellation = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var cancelled = false

    init(url: URL, loops: Bool, onFrame: @escaping @MainActor (CGImage) -> Void) {
        self.url = url
        self.loops = loops
        frameHandler = FrameHandler(onFrame)
    }

    func start() {
        queue.async { [self] in
            play()
        }
    }

    func cancel() {
        stateLock.withLock {
            guard !cancelled else { return }
            cancelled = true
            cancellation.signal()
        }
    }

    private func play() {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0,
              let firstFrame = decodedFrame(from: source, at: 0) else { return }

        var frameIndex = 0
        var displayedAt = DispatchTime.now().uptimeNanoseconds
        frameHandler.deliver(firstFrame)

        while !isCancelled {
            var nextIndex = frameIndex + 1
            if nextIndex == frameCount {
                guard loops else { return }
                nextIndex = 0
            }

            // Decode the next frame while the current one is on screen, then
            // wait only for the remainder of the source frame's duration.
            guard let nextFrame = decodedFrame(from: source, at: nextIndex) else { return }
            let delay = frameDuration(from: source, at: frameIndex)
            let delayNanoseconds = UInt64(max(delay, 0.001) * 1_000_000_000)
            let deadline = displayedAt &+ delayNanoseconds
            let now = DispatchTime.now().uptimeNanoseconds

            if deadline > now,
               cancellation.wait(timeout: .now() + .nanoseconds(Int(deadline - now))) == .success {
                return
            }
            guard !isCancelled else { return }

            displayedAt = max(deadline, DispatchTime.now().uptimeNanoseconds)
            frameHandler.deliver(nextFrame)
            frameIndex = nextIndex
        }
    }

    private var isCancelled: Bool {
        stateLock.withLock { cancelled }
    }

    private func decodedFrame(from source: CGImageSource, at index: Int) -> CGImage? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, index, options)
    }

    private func frameDuration(from source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
            return 0.1
        }

        let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
        let candidates: [Any?] = [
            gif?[kCGImagePropertyGIFUnclampedDelayTime as String],
            gif?[kCGImagePropertyGIFDelayTime as String],
            png?[kCGImagePropertyAPNGUnclampedDelayTime as String],
            png?[kCGImagePropertyAPNGDelayTime as String]
        ]
        return candidates.lazy.compactMap { ($0 as? NSNumber)?.doubleValue }.first(where: { $0 > 0 }) ?? 0.1
    }
}

private final class FrameHandler: @unchecked Sendable {
    private let body: @MainActor (CGImage) -> Void

    init(_ body: @escaping @MainActor (CGImage) -> Void) {
        self.body = body
    }

    func deliver(_ image: CGImage) {
        DispatchQueue.main.async { [body] in
            MainActor.assumeIsolated {
                body(image)
            }
        }
    }
}
