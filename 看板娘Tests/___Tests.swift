import Foundation
import AppKit
import SwiftUI
import Testing
@testable import 看板娘

struct AgentFoundationTests {
    @MainActor
    private final class FakeModelClient: AgentModelClient {
        var responses: [AgentModelResponse] = []
        private(set) var requests: [[AgentMessage]] = []

        func sendAgentStreamRequest(
            messages: [AgentMessage],
            tools: [AgentToolDefinition],
            onReceive: @escaping @MainActor @Sendable (String) -> Void,
            onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
            onError: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            requests.append(messages)
            let response = responses.removeFirst()
            if !response.content.isEmpty { onReceive(response.content) }
            onComplete(response)
        }

        func cancelStreamRequest() {}
    }

    @MainActor
    private final class EchoTool: AgentTool {
        let definition = AgentToolDefinition(
            name: "echo",
            description: "echo test",
            parameters: ["type": "object", "properties": [:]]
        )
        let requiresConfirmation = false
        func approvalSummary(arguments: [String: Any]) -> String { "echo" }
        func execute(
            arguments: [String: Any],
            completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
        ) {
            completion(.success(arguments["value"] as? String ?? ""))
        }
    }

    @Test
    func toolCallArgumentsAndOpenAIMessageEncodingRoundTrip() throws {
        let call = AgentToolCall(
            id: "call-1",
            name: "read_file",
            arguments: #"{"path":"/tmp/example.txt"}"#
        )
        let arguments = try call.decodedArguments()
        #expect(arguments["path"] as? String == "/tmp/example.txt")

        let message = AgentMessage.assistant(content: nil, toolCalls: [call]).jsonObject()
        let encodedCalls = message["tool_calls"] as? [[String: Any]]
        let function = encodedCalls?.first?["function"] as? [String: Any]
        #expect(message["role"] as? String == "assistant")
        #expect(function?["name"] as? String == "read_file")
        #expect(function?["arguments"] as? String == call.arguments)
    }

    @Test
    func toolResultUsesStructuredSuccessEnvelope() throws {
        let success = AgentToolExecutionResult.success("星期一")
        let data = try #require(success.modelContent.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["ok"] as? Bool == true)
        #expect(object["result"] as? String == "星期一")
    }

    @Test @MainActor
    func standardRegistryExposesCoreAndAppTools() {
        let names = Set(AgentToolRegistry.standard().definitions.map(\.name))
        #expect(names.contains("get_current_datetime"))
        #expect(names.contains("read_file"))
        #expect(names.contains("run_command"))
        #expect(names.contains("switch_pet_character"))
        #expect(names.contains("run_automation"))
    }

    @Test @MainActor
    func runtimeFeedsToolObservationBackAndContinuesUntilFinalAnswer() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(
                content: "",
                toolCalls: [
                    AgentToolCall(id: "call-echo", name: "echo", arguments: #"{"value":"ok"}"#)
                ]
            ),
            AgentModelResponse(content: "完成", toolCalls: [])
        ]
        let registry = AgentToolRegistry()
        registry.register(EchoTool())
        let runtime = AgentRuntime(
            apiManager: client,
            registry: registry,
            systemPromptProvider: { "system" }
        )
        var completed = false
        runtime.onCompleted = { completed = true }

        runtime.send("test")

        #expect(completed)
        #expect(client.requests.count == 2)
        #expect(client.requests[1].last?.role == .tool)
        #expect(client.requests[1].last?.content?.contains("ok") == true)
        #expect(runtime.messages.last?.content == "完成")
    }

    @Test @MainActor
    func startingNewConversationDropsPreviousTurnContext() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(content: "first", toolCalls: []),
            AgentModelResponse(content: "second", toolCalls: [])
        ]
        let runtime = AgentRuntime(
            apiManager: client,
            registry: AgentToolRegistry(),
            systemPromptProvider: { "system" }
        )

        runtime.send("one")
        runtime.startNewConversation()
        runtime.send("two")

        #expect(client.requests.count == 2)
        #expect(client.requests[1].count == 2)
        #expect(client.requests[1][0].role == .system)
        #expect(client.requests[1][1] == .user("two"))
    }
}

struct ModelConfigurationLibraryTests {
    @Test
    func configurationRequiresAnHTTPServiceURL() {
        var configuration = ModelConfiguration.preset(for: .openAICompatible)
        #expect(configuration.isValid)

        configuration.apiUrl = "localhost:1234/v1/chat/completions"
        #expect(!configuration.isValid)

        configuration.apiUrl = "http://localhost:1234/v1/chat/completions"
        #expect(configuration.isValid)
    }

    @Test
    func legacyLMStudioConfigurationMigratesIntoNamedLibrary() {
        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = ModelConfiguration.migratedLegacy(
            provider: "qwen",
            aiModel: "local/qwen3",
            apiUrl: "http://localhost:1234/v1/chat/completions",
            apiKey: "lm-studio"
        )
        let library = ModelConfigurationLibrary.load(from: defaults, legacyConfiguration: legacy)

        #expect(library.configurations.count == 1)
        #expect(library.configurations[0].name == "LM Studio 本地")
        #expect(library.activeConfigurationID == library.configurations[0].id)
        #expect(defaults.data(forKey: ModelConfigurationLibrary.configurationsKey) != nil)
    }

    @Test
    func multipleCompatibleServicesRoundTripWithoutOverwritingEachOther() {
        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cloud = ModelConfiguration(
            name: "通义千问云端",
            provider: "qwen",
            aiModel: "qwen-plus",
            apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            apiKey: "cloud-key"
        )
        let local = ModelConfiguration(
            name: "LM Studio 本地",
            provider: "qwen",
            aiModel: "local/qwen3",
            apiUrl: "http://localhost:1234/v1/chat/completions",
            apiKey: "lm-studio"
        )
        let saved = ModelConfigurationLibrary(
            configurations: [cloud, local],
            activeConfigurationID: local.id
        )
        saved.save(to: defaults)

        let loaded = ModelConfigurationLibrary.load(from: defaults, legacyConfiguration: cloud)
        #expect(loaded == saved)
        #expect(loaded.configurations[0].apiKey == "cloud-key")
        #expect(loaded.configurations[1].apiKey == "lm-studio")
    }

    @Test
    func externalSettingsPatchUpdatesOnlyTheActiveProfileDetails() {
        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cloud = ModelConfiguration.preset(for: .openAICompatible)
        var local = ModelConfiguration.preset(for: .openAICompatible)
        local.name = "LM Studio 本地"
        local.apiUrl = "http://localhost:1234/v1/chat/completions"
        let original = ModelConfigurationLibrary(
            configurations: [cloud, local],
            activeConfigurationID: local.id
        )
        original.save(to: defaults)

        let patched = ModelConfiguration.migratedLegacy(
            provider: "qwen",
            aiModel: "local/new-model",
            apiUrl: local.apiUrl,
            apiKey: "new-key"
        )
        ModelConfigurationLibrary.synchronizeActiveConfiguration(
            in: defaults,
            legacyConfiguration: patched
        )

        let loaded = ModelConfigurationLibrary.load(from: defaults, legacyConfiguration: cloud)
        #expect(loaded.configurations[0] == cloud)
        #expect(loaded.configurations[1].id == local.id)
        #expect(loaded.configurations[1].name == "LM Studio 本地")
        #expect(loaded.configurations[1].aiModel == "local/new-model")
        #expect(loaded.configurations[1].apiKey == "new-key")
    }
}

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

    @Test
    func alignmentUsesTheVisibleArtworkBoundsInsteadOfTheTransparentCanvas() {
        let bounds = PetArtworkBounds(
            sourceSize: CGSize(width: 360, height: 534),
            visibleMinX: 94,
            visibleMaxX: 280
        )

        let left = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            placement: .left
        )
        let center = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            placement: .center
        )
        let right = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            placement: .right
        )

        #expect(abs(left + 94.91) < 0.02)
        #expect(abs(center + 3.67) < 0.02)
        #expect(abs(right - 87.57) < 0.02)
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
