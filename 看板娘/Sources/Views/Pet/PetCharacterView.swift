//
//  PetCharacterView.swift
//  看板娘
//

import AppKit
import ImageIO
import SDWebImage
import SDWebImageSwiftUI
import SwiftUI

struct PetArtworkBounds: Equatable {
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

@MainActor
private final class PetArtworkBoundsCache {
    static let shared = PetArtworkBoundsCache()

    private var cachedBounds: [String: PetArtworkBounds] = [:]
    private var unresolvedKeys = Set<String>()

    func bounds(for asset: PetAnimationAsset) -> PetArtworkBounds? {
        let key = "\(asset.id)|\(asset.location)"
        if let cached = cachedBounds[key] { return cached }
        guard !unresolvedKeys.contains(key),
              let url = assetURL(for: asset.location),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bounds = opaqueHorizontalBounds(in: image) else {
            unresolvedKeys.insert(key)
            return nil
        }

        cachedBounds[key] = bounds
        return bounds
    }

    private func assetURL(for location: String) -> URL? {
        if location.hasPrefix("/") {
            return URL(fileURLWithPath: location)
        }
        return Bundle.main.url(forResource: location, withExtension: nil)
    }

    private func opaqueHorizontalBounds(in image: CGImage) -> PetArtworkBounds? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

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
        return PetArtworkBounds(
            sourceSize: CGSize(width: width, height: height),
            visibleMinX: CGFloat(minX),
            visibleMaxX: CGFloat(maxX + 1)
        )
    }
}

struct PetCharacterView: View {
    @ObservedObject var backend: PetViewBackend
    @ObservedObject var coordinator: PetStateCoordinator
    let horizontalPosition: Double
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onRightClick: () -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (NSPoint, NSPoint) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ZStack {
            media
                .scaleEffect(backend.currentCharacter.displayOptions.scale)
                .offset(
                    x: backend.currentCharacter.displayOptions.horizontalOffset,
                    y: backend.currentCharacter.displayOptions.verticalOffset
                )
            PetTransientEffectView(
                state: coordinator.snapshot.renderedState,
                effect: coordinator.transientEffect
            )
        }
        .offset(x: artworkAlignmentOffset)
        .frame(width: 280, height: 280)
        .overlay(
            AlphaHitTestOverlay(
                onTap: onTap,
                onHover: onHover,
                onDoubleTap: onDoubleTap,
                onRightClick: onRightClick,
                onDragBegan: onDragBegan,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded
            )
        )
        .accessibilityLabel("\(backend.currentCharacter.name)，\(coordinator.snapshot.renderedState.displayName)")
        .onDisappear { SDImageCache.shared.clearMemory() }
    }

    private var artworkAlignmentOffset: CGFloat {
        guard let asset = backend.currentResolvedAsset?.asset,
              let bounds = PetArtworkBoundsCache.shared.bounds(for: asset) else { return 0 }
        return PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: CGFloat(backend.currentCharacter.displayOptions.scale),
            position: horizontalPosition
        )
    }

    @ViewBuilder
    private var media: some View {
        if let asset = backend.currentResolvedAsset?.asset {
            if asset.type == .gif {
                gifView(asset: asset)
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
    private func gifView(asset: PetAnimationAsset) -> some View {
        if asset.location.hasPrefix("/") {
            AnimatedImage(url: URL(fileURLWithPath: asset.location))
                .resizable()
                .customLoopCount(asset.loop ? nil : 1)
                .scaledToFit()
                .id(backend.currentResolvedAsset?.asset.id)
        } else {
            AnimatedImage(name: asset.location)
                .resizable()
                .customLoopCount(asset.loop ? nil : 1)
                .scaledToFit()
                .id(backend.currentResolvedAsset?.asset.id)
        }
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
