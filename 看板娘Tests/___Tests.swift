import Foundation
import AppKit
import SwiftUI
import Testing
@testable import 看板娘

struct PetHorizontalPlacementTests {
    @Test
    func centerIsTheDefaultPlacement() {
        #expect(PetHorizontalPlacement.defaultValue == .center)
        #expect(PetHorizontalPlacement.defaultValue.rawValue == "center")
    }

    @Test
    func allPersistedPlacementValuesRoundTrip() {
        for placement in PetHorizontalPlacement.allCases {
            #expect(PetHorizontalPlacement(rawValue: placement.rawValue) == placement)
        }
    }
}

struct PetStateCoordinatorTests {
    @Test @MainActor
    func conversationLifecycleAndStaleEvents() {
        let now = Date(timeIntervalSince1970: 100)
        let coordinator = PetStateCoordinator(now: now)
        let activeID = UUID()
        let staleID = UUID()

        coordinator.send(.conversationStarted(activeID), at: now)
        #expect(coordinator.snapshot.activityState == .thinking)
        coordinator.send(.conversationStreamStarted(activeID), at: now.addingTimeInterval(1))
        #expect(coordinator.snapshot.activityState == .talking)

        coordinator.send(.conversationCompleted(staleID), at: now.addingTimeInterval(2))
        #expect(coordinator.snapshot.activityState == .talking)
        #expect(coordinator.snapshot.runID == activeID)
    }

    @Test @MainActor
    func confirmationCannotBeOverriddenByBackgroundWork() {
        let coordinator = PetStateCoordinator()
        let commandID = UUID()
        coordinator.send(.conversationStarted(commandID))
        coordinator.send(.commandConfirmationRequested(commandID))

        coordinator.send(.automationStarted(UUID()))
        coordinator.send(.interaction(.clicked, nil))

        #expect(coordinator.snapshot.activityState == .waitingForConfirmation)
        #expect(coordinator.snapshot.renderedState == .waitingForConfirmation)
        #expect(coordinator.snapshot.hasPendingConfirmation)
    }

    @Test @MainActor
    func transientSuccessFallsBackToLatestSnapshot() {
        let now = Date(timeIntervalSince1970: 200)
        let coordinator = PetStateCoordinator(now: now)
        let runID = UUID()

        coordinator.send(.conversationStarted(runID), at: now)
        coordinator.send(.conversationCompleted(runID), at: now.addingTimeInterval(1))
        #expect(coordinator.snapshot.activityState == .idle)
        #expect(coordinator.snapshot.renderedState == .success)

        coordinator.expireTransientEffect(at: now.addingTimeInterval(4))
        #expect(coordinator.snapshot.activityState == .idle)
        #expect(coordinator.snapshot.renderedState == .idle)
        #expect(coordinator.transientEffect == nil)
    }

    @Test @MainActor
    func sleepOnlyStartsFromIdle() {
        let coordinator = PetStateCoordinator()
        let runID = UUID()
        coordinator.send(.conversationStarted(runID))
        coordinator.send(.idleTimeoutReached)
        #expect(coordinator.snapshot.activityState == .thinking)

        coordinator.send(.resetToIdle)
        coordinator.send(.idleTimeoutReached)
        #expect(coordinator.snapshot.activityState == .sleeping)
    }

    @Test @MainActor
    func foregroundWorkInterruptsClickEffect() {
        let coordinator = PetStateCoordinator()
        coordinator.send(.interaction(.clicked, 5))
        #expect(coordinator.transientEffect == .clicked)

        coordinator.send(.conversationStarted(UUID()))
        #expect(coordinator.snapshot.activityState == .thinking)
        #expect(coordinator.transientEffect == nil)
    }
}

struct PetAssetResolverTests {
    @Test
    func missingWorkingAssetFallsBackToIdle() {
        let idle = PetAnimationAsset(id: "idle", location: "idle.png", type: .png)
        let character = PetCharacter(
            id: "test",
            name: "Test",
            assetsByState: [.idle: [idle]],
            autoMessages: []
        )

        let resolved = PetAssetResolver().resolve(
            character: character,
            state: .working,
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(resolved?.asset.id == "idle")
        #expect(resolved?.resolvedState == .idle)
    }

    @Test
    func interactionAssetWinsForClickEffect() {
        let idle = PetAnimationAsset(id: "idle", location: "idle.gif")
        let click = PetAnimationAsset(id: "click", location: "click.gif", loop: false)
        let character = PetCharacter(
            id: "test",
            name: "Test",
            assetsByState: [.idle: [idle]],
            interactionAssets: [click],
            autoMessages: []
        )

        let resolved = PetAssetResolver().resolve(
            character: character,
            state: .idle,
            transientEffect: .clicked,
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(resolved?.asset.id == "click")
        #expect(resolved?.isInteractionAsset == true)
    }

    @Test
    func oldTwoGifCharacterIsRejectedByConfirmedMigrationPolicy() {
        let legacyJSON = #"{"name":"旧角色","normalGif":"idle.gif","clickGif":"tap.gif","autoMessages":[]}"#
        let decoded = try? JSONDecoder().decode(PetCharacter.self, from: Data(legacyJSON.utf8))
        #expect(decoded == nil)
    }

    @Test
    func newCharacterRoundTrips() throws {
        let character = PetCharacter(
            id: "stable-id",
            name: "新角色",
            assetsByState: [
                .idle: [PetAnimationAsset(id: "idle", location: "idle.png", type: .png)],
                .thinking: [PetAnimationAsset(id: "thinking", location: "thinking.gif")]
            ],
            autoMessages: ["你好"]
        )
        let data = try JSONEncoder().encode(character)
        let decoded = try JSONDecoder().decode(PetCharacter.self, from: data)
        #expect(decoded == character)
        #expect(decoded.id == "stable-id")
    }
}

struct PetWindowGeometryTests {
    @Test
    func growingContentPreservesPetAnchor() {
        let current = NSRect(x: 500, y: 160, width: 280, height: 280)
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

        let expanded = PetWindowGeometry.anchoredFrame(
            currentFrame: current,
            proposedContentSize: CGSize(width: 340, height: 390),
            visibleFrame: visible
        )

        #expect(expanded.midX == current.midX)
        #expect(expanded.minY == current.minY)
        #expect(expanded.width == 340)
        #expect(expanded.height == 390)
    }

    @Test
    func expansionAtScreenEdgeNeverMovesPetAnchor() {
        let current = NSRect(x: 1_250, y: 720, width: 280, height: 280)
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

        let expanded = PetWindowGeometry.anchoredFrame(
            currentFrame: current,
            proposedContentSize: CGSize(width: 360, height: 520),
            visibleFrame: visible
        )

        #expect(expanded.midX == current.midX)
        #expect(expanded.minY == current.minY)
        #expect(expanded.maxX > visible.maxX)
        #expect(expanded.maxY > visible.maxY)
    }

    @Test
    func contentCanShrinkWindowToOneHundredEightyPoints() {
        let current = NSRect(x: 500, y: 160, width: 336, height: 346)
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

        let shrunk = PetWindowGeometry.anchoredFrame(
            currentFrame: current,
            proposedContentSize: CGSize(width: 120, height: 140),
            visibleFrame: visible
        )

        #expect(shrunk.size == PetWindowSizing.minimumSize)
        #expect(shrunk.midX == current.midX)
        #expect(shrunk.minY == current.minY)
    }
}

struct WindowResizeGeometryTests {
    private let initial = NSRect(x: 100, y: 100, width: 560, height: 440)
    private let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)
    private let minimum = NSSize(width: 420, height: 320)

    @Test
    func draggingTopRightCornerExpandsBothDimensions() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: 80, y: 60),
            edges: [.right, .top],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.minX == initial.minX)
        #expect(resized.minY == initial.minY)
        #expect(resized.width == 640)
        #expect(resized.height == 500)
    }

    @Test
    func draggingLeftAndBottomPreservesOppositeCorner() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: -50, y: -25),
            edges: [.left, .bottom],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.maxX == initial.maxX)
        #expect(resized.maxY == initial.maxY)
        #expect(resized.width == 610)
        #expect(resized.height == 465)
    }

    @Test
    func shrinkingStopsAtMinimumSize() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: -500, y: -500),
            edges: [.right, .top],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.size == minimum)
        #expect(resized.origin == initial.origin)
    }

    @Test
    func expansionStopsAtVisibleScreenEdges() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: -500, y: 800),
            edges: [.left, .top],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.minX == visible.minX)
        #expect(resized.maxY == visible.maxY)
    }
}

struct PetWindowScaleGeometryTests {
    private let initial = NSRect(x: 500, y: 120, width: 336, height: 346)
    private let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

    @Test
    func horizontalDragScalesPetUniformlyFromBottomEdge() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 420, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible
        )

        #expect(resized.minX == initial.minX)
        #expect(resized.minY == initial.minY)
        #expect(resized.width == 420)
        #expect(resized.height == 432.5)
    }

    @Test
    func leftBottomCornerPreservesOppositeCorner() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 416, y: 40, width: 420, height: 426),
            edges: [.left, .bottom],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible
        )

        #expect(resized.maxX == initial.maxX)
        #expect(resized.maxY == initial.maxY)
        #expect(resized.width / initial.width == resized.height / initial.height)
    }

    @Test
    func shrinkingStopsBeforeEitherDimensionDropsBelowMinimum() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 100, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible
        )

        #expect(resized.width == 180)
        #expect(resized.height >= 180)
    }

    @Test
    func resizingHonorsConfiguredScaleLimit() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 1_000, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible,
            maximumScaleFactor: 1.5
        )

        #expect(resized.width == initial.width * 1.5)
        #expect(resized.height == initial.height * 1.5)
    }

    @Test
    func fixedPanelHeightDoesNotScaleWithCharacter() {
        let initial = NSRect(x: 500, y: 120, width: 356, height: 346)
        let fixedPanelHeight: CGFloat = 66
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 267, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible,
            fixedContentHeight: fixedPanelHeight
        )

        #expect(resized.width == 267)
        #expect(resized.height == 276)
        #expect(resized.height - PetWindowSizing.characterBaseHeight * 0.75 == fixedPanelHeight)
    }

    @Test
    func verticalDragDerivesScaleAfterSubtractingFixedPanelHeight() {
        let initial = NSRect(x: 500, y: 120, width: 356, height: 346)
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 356, height: 276),
            edges: [.top],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible,
            fixedContentHeight: 66
        )

        #expect(resized.width == 267)
        #expect(resized.height == 276)
        #expect(resized.minY == initial.minY)
    }
}

struct PetWindowRuntimeSizingTests {
    @Test
    func panelWidthTracksWindowScaleWithoutScalingPanelContent() {
        #expect(PetWindowSizing.panelWidth(for: 0.5) == 164)
        #expect(PetWindowSizing.panelWidth(for: 1) == 340)
        #expect(PetWindowSizing.panelWidth(for: 2) == 696)
    }

    @Test @MainActor
    func scaledContentReportsItsVisualSizeInsteadOfUnscaledLayoutSize() {
        let rootView = PetWindowScaledContent(scale: 0.5) {
            Color.red
                .frame(width: 336, height: 346)
                .fixedSize()
        }
        let hostingView = NSHostingView(rootView: rootView)

        #expect(hostingView.fittingSize.width == 168)
        #expect(hostingView.fittingSize.height == 173)
    }

    @Test @MainActor
    func hostingFixedPetContentStillAcceptsOneHundredEightyPointWindow() {
        let rootView = Color.clear
            .frame(width: 336, height: 346)
            .fixedSize()
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 346),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentMinSize = PetWindowSizing.minimumSize

        window.setFrame(
            NSRect(x: 0, y: 0, width: 180, height: 186),
            display: false,
            animate: false
        )
        hostingView.layoutSubtreeIfNeeded()

        #expect(window.contentMinSize == PetWindowSizing.minimumSize)
        #expect(window.frame.width == 180)
    }
}

struct OptionWindowResizeModeTests {
    @Test @MainActor
    func dialogWindowForwardsOptionModifierToNativeOverlay() {
        let window = DialogWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        let overlay = OptionWindowResizeNSView(frame: window.contentView?.bounds ?? .zero)
        window.resizeOverlay = overlay

        window.updateResizeMode(for: [.option])
        #expect(overlay.isResizeModeActive)

        window.updateResizeMode(for: [])
        #expect(!overlay.isResizeModeActive)
    }

    @Test @MainActor
    func nativeOverlayTracksContainerSize() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 440))
        let overlay = OptionWindowResizeNSView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)

        container.setFrameSize(NSSize(width: 720, height: 520))
        container.layoutSubtreeIfNeeded()

        #expect(overlay.frame.size == container.bounds.size)
    }

    @Test @MainActor
    func resizeContainerOverlayWinsHitTestingAboveHostingView() {
        let hostingView = NSHostingView(
            rootView: Color.clear.frame(width: 336, height: 346).fixedSize()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 346),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = WindowResizeContainerNSView(
            frame: NSRect(x: 0, y: 0, width: 336, height: 346)
        )
        window.contentView = container
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        let overlay = OptionWindowResizeNSView(frame: container.bounds)
        overlay.setResizeModeActive(true)
        container.addSubview(overlay, positioned: .above, relativeTo: hostingView)

        let rightEdgePoint = NSPoint(
            x: container.bounds.maxX - 4,
            y: container.bounds.midY
        )
        #expect(container.hitTest(rightEdgePoint) === overlay)
    }

    @Test @MainActor
    func activeOverlayRendersOrangeBorder() throws {
        let overlay = OptionWindowResizeNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        overlay.cornerRadius = 24
        overlay.setResizeModeActive(true)

        let bitmap = try #require(overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds))
        overlay.cacheDisplay(in: overlay.bounds, to: bitmap)

        var foundAccentPixel = false
        for x in 0..<bitmap.pixelsWide where !foundAccentPixel {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.45,
                   color.redComponent > 0.7,
                   color.greenComponent > 0.3,
                   color.redComponent > color.greenComponent,
                   color.greenComponent > color.blueComponent {
                    foundAccentPixel = true
                    break
                }
            }
        }

        #expect(foundAccentPixel)
    }
}
