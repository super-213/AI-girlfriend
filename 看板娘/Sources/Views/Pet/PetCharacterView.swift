//
//  PetCharacterView.swift
//  看板娘
//

import AppKit
import SDWebImage
import SDWebImageSwiftUI
import SwiftUI

struct PetCharacterView: View {
    @ObservedObject var backend: PetViewBackend
    @ObservedObject var coordinator: PetStateCoordinator
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
