//
//  PetCharacterView.swift
//  看板娘
//

import AppKit
import ImageIO
import SwiftUI

struct PetArtworkBounds: Equatable, @unchecked Sendable {
    let sourceSize: CGSize
    let visibleMinX: CGFloat
    let visibleMaxX: CGFloat
}

enum PetArtworkAlignmentGeometry {
    static let containerSize: CGFloat = 280

    static func horizontalOffset(
        bounds: PetArtworkBounds,
        displayScale: CGFloat,
        position: Double,
        containerSize: CGFloat = containerSize
    ) -> CGFloat {
        guard bounds.sourceSize.width > 0,
              bounds.sourceSize.height > 0,
              containerSize > 0 else { return 0 }

        let fitScale = min(
            containerSize / bounds.sourceSize.width,
            containerSize / bounds.sourceSize.height
        )
        let fittedWidth = bounds.sourceSize.width * fitScale
        let fittedMinX = (containerSize - fittedWidth) / 2
        let visibleMinX = fittedMinX + bounds.visibleMinX * fitScale
        let visibleMaxX = fittedMinX + bounds.visibleMaxX * fitScale
        let centerX = containerSize / 2
        let resolvedDisplayScale = max(displayScale, 0)
        let scaledVisibleMinX = centerX + (visibleMinX - centerX) * resolvedDisplayScale
        let scaledVisibleMaxX = centerX + (visibleMaxX - centerX) * resolvedDisplayScale

        let progress = CGFloat(PetHorizontalPosition.clamped(position))
        let visibleWidth = scaledVisibleMaxX - scaledVisibleMinX
        let targetMinX = (containerSize - visibleWidth) * progress
        return targetMinX - scaledVisibleMinX
    }
}

final class PetImageAlphaMask: @unchecked Sendable {
    let sourceSize: CGSize
    private let pixelWidth: Int
    private let pixelHeight: Int
    private let bytesPerRow: Int
    private let pixels: [UInt8]

    init(
        sourceSize: CGSize,
        pixelWidth: Int,
        pixelHeight: Int,
        bytesPerRow: Int,
        pixels: [UInt8]
    ) {
        self.sourceSize = sourceSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    /// Samples the poster frame using the same aspect-fit, scale and offset
    /// geometry as `PetCharacterView`. This preserves transparent click-through
    /// without synchronously snapshotting the complete SwiftUI layer tree.
    func isOpaque(
        at point: CGPoint,
        in containerBounds: CGRect,
        displayScale: CGFloat,
        displayOffset: CGSize,
        artworkAlignmentOffset: CGFloat,
        alphaThreshold: UInt8 = 30
    ) -> Bool {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              containerBounds.width > 0,
              containerBounds.height > 0,
              displayScale > 0 else { return false }

        let fitScale = min(
            containerBounds.width / sourceSize.width,
            containerBounds.height / sourceSize.height
        )
        let fittedSize = CGSize(
            width: sourceSize.width * fitScale,
            height: sourceSize.height * fitScale
        )
        let visualCenter = CGPoint(
            x: containerBounds.midX + displayOffset.width + artworkAlignmentOffset,
            y: containerBounds.midY + displayOffset.height
        )
        let unscaledPoint = CGPoint(
            x: containerBounds.midX + (point.x - visualCenter.x) / displayScale,
            y: containerBounds.midY + (point.y - visualCenter.y) / displayScale
        )
        let fittedOrigin = CGPoint(
            x: containerBounds.midX - fittedSize.width / 2,
            y: containerBounds.midY - fittedSize.height / 2
        )
        let sourceX = (unscaledPoint.x - fittedOrigin.x) / fitScale
        let sourceYFromTop = (unscaledPoint.y - fittedOrigin.y) / fitScale
        guard sourceX >= 0, sourceX < sourceSize.width,
              sourceYFromTop >= 0, sourceYFromTop < sourceSize.height else {
            return false
        }

        let pixelX = min(max(Int(sourceX), 0), pixelWidth - 1)
        // Bitmap contexts store the first row at the lower edge, while the
        // flipped AppKit hit-test view reports points from the upper edge.
        let pixelY = min(max(pixelHeight - 1 - Int(sourceYFromTop), 0), pixelHeight - 1)
        return pixels[pixelY * bytesPerRow + pixelX * 4 + 3] > alphaThreshold
    }
}

private struct PetArtworkMetadata: @unchecked Sendable {
    let bounds: PetArtworkBounds
    let alphaMask: PetImageAlphaMask
}

private enum PetArtworkMetadataLoader {
    static func load(location: String) -> PetArtworkMetadata? {
        guard let url = assetURL(for: location),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }

        var minX = width
        var maxX = -1
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width where pixels[rowStart + x * bytesPerPixel + 3] > 30 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard maxX >= minX else { return nil }

        let sourceSize = CGSize(width: width, height: height)
        return PetArtworkMetadata(
            bounds: PetArtworkBounds(
                sourceSize: sourceSize,
                visibleMinX: CGFloat(minX),
                visibleMaxX: CGFloat(maxX + 1)
            ),
            alphaMask: PetImageAlphaMask(
                sourceSize: sourceSize,
                pixelWidth: width,
                pixelHeight: height,
                bytesPerRow: bytesPerRow,
                pixels: pixels
            )
        )
    }

    private static func assetURL(for location: String) -> URL? {
        if location.hasPrefix("/") {
            return URL(fileURLWithPath: location)
        }
        return Bundle.main.url(forResource: location, withExtension: nil)
    }
}

@MainActor
private final class PetArtworkMetadataCache: ObservableObject {
    static let shared = PetArtworkMetadataCache()

    @Published private(set) var revision = 0
    private var cachedMetadata: [String: PetArtworkMetadata] = [:]
    private var loadingKeys = Set<String>()
    private var unresolvedKeys = Set<String>()

    func metadata(for asset: PetAnimationAsset) -> PetArtworkMetadata? {
        let key = cacheKey(for: asset)
        if let cached = cachedMetadata[key] { return cached }
        prefetch(asset)
        return nil
    }

    func prefetch(_ asset: PetAnimationAsset) {
        let key = cacheKey(for: asset)
        guard cachedMetadata[key] == nil,
              !loadingKeys.contains(key),
              !unresolvedKeys.contains(key) else { return }
        loadingKeys.insert(key)

        let location = asset.location
        Task.detached(priority: .utility) {
            let metadata = PetArtworkMetadataLoader.load(location: location)
            await MainActor.run {
                let cache = PetArtworkMetadataCache.shared
                cache.loadingKeys.remove(key)
                if let metadata {
                    cache.cachedMetadata[key] = metadata
                    cache.revision &+= 1
                } else {
                    cache.unresolvedKeys.insert(key)
                }
            }
        }
    }

    private func cacheKey(for asset: PetAnimationAsset) -> String {
        "\(asset.id)|\(asset.location)"
    }
}

struct PetCharacterView: View, @MainActor Equatable {
    let character: PetCharacter
    let resolvedAsset: PetResolvedAsset?
    @ObservedObject var coordinator: PetStateCoordinator
    let horizontalPosition: Double
    let isFileDropTargeted: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onRightClick: () -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (NSPoint, NSPoint) -> Void
    let onDragEnded: () -> Void
    let onFileDrop: ([URL]) -> Void
    let onFileDropTargetChanged: (Bool) -> Void
    @ObservedObject private var artworkMetadataCache = PetArtworkMetadataCache.shared

    static func == (lhs: PetCharacterView, rhs: PetCharacterView) -> Bool {
        lhs.character == rhs.character
            && lhs.resolvedAsset == rhs.resolvedAsset
            && lhs.coordinator === rhs.coordinator
            && lhs.horizontalPosition == rhs.horizontalPosition
            && lhs.isFileDropTargeted == rhs.isFileDropTargeted
    }

    var body: some View {
        ZStack {
            media
                .scaleEffect(character.displayOptions.scale)
                .offset(
                    x: character.displayOptions.horizontalOffset,
                    y: character.displayOptions.verticalOffset
                )
            PetTransientEffectView(
                state: coordinator.snapshot.renderedState,
                effect: coordinator.transientEffect
            )
            if isFileDropTargeted {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    )
                    .padding(10)

                Label("松开交给我", systemImage: "tray.and.arrow.down.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            }
        }
        .offset(x: artworkAlignmentOffset)
        .frame(width: 280, height: 280)
        .overlay(
            AlphaHitTestOverlay(
                alphaMask: artworkMetadata?.alphaMask,
                displayScale: CGFloat(character.displayOptions.scale),
                displayOffset: CGSize(
                    width: character.displayOptions.horizontalOffset,
                    height: character.displayOptions.verticalOffset
                ),
                artworkAlignmentOffset: artworkAlignmentOffset,
                onTap: onTap,
                onHover: onHover,
                onDoubleTap: onDoubleTap,
                onRightClick: onRightClick,
                onDragBegan: onDragBegan,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                onFileDrop: onFileDrop,
                onFileDropTargetChanged: onFileDropTargetChanged
            )
        )
        .accessibilityLabel("\(character.name)，\(coordinator.snapshot.renderedState.displayName)")
        .onAppear(perform: prefetchInteractionMetadata)
        .onChange(of: character.id) { _, _ in prefetchInteractionMetadata() }
    }

    private var artworkMetadata: PetArtworkMetadata? {
        guard let asset = resolvedAsset?.asset else { return nil }
        return artworkMetadataCache.metadata(for: asset)
    }

    private var artworkAlignmentOffset: CGFloat {
        guard let bounds = artworkMetadata?.bounds else { return 0 }
        return PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: CGFloat(character.displayOptions.scale),
            position: horizontalPosition
        )
    }

    private func prefetchInteractionMetadata() {
        for asset in character.interactionAssets {
            artworkMetadataCache.prefetch(asset)
        }
    }

    @ViewBuilder
    private var media: some View {
        if let asset = resolvedAsset?.asset {
            if asset.type.isAnimated {
                animatedImage(asset: asset)
            } else if let image = staticImage(location: asset.location) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .id(asset.id)
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func animatedImage(asset: PetAnimationAsset) -> some View {
        if let url = assetURL(location: asset.location) {
            NativeAnimatedImage(url: url, loops: asset.loop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(asset.id)
        } else {
            placeholder
        }
    }

    private func assetURL(location: String) -> URL? {
        if location.hasPrefix("/") {
            return URL(fileURLWithPath: location)
        }
        return Bundle.main.url(forResource: location, withExtension: nil)
    }

    private func staticImage(location: String) -> NSImage? {
        if location.hasPrefix("/") {
            return NSImage(contentsOfFile: location)
        }
        if let url = Bundle.main.url(forResource: location, withExtension: nil) {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: location)
    }

    private var placeholder: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 88, weight: .light))
            .foregroundStyle(.secondary.opacity(0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
