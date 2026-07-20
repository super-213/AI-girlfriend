import Foundation
import AppKit
import Testing
@testable import 看板娘

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
}
