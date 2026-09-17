//
//  PetRootView.swift
//  看板娘
//

import SwiftUI

/// `scaleEffect` 只改变绘制结果，不会改变 SwiftUI 的布局占位。桌宠窗口跟随缩放
/// 变小时，未缩放的布局占位会超出 NSHostingView，最终把 GIF 的下半部分裁掉。
/// 这个布局用缩放后的尺寸参与父布局，同时仍按未缩放尺寸放置内容，保证视觉变换
/// 后的内容恰好落在窗口范围内。
struct PetWindowScaledLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let contentSize = subview.sizeThatFits(.unspecified)
        let resolvedScale = max(scale, 0)
        return CGSize(
            width: contentSize.width * resolvedScale,
            height: contentSize.height * resolvedScale
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let contentSize = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.maxY),
            anchor: .bottom,
            proposal: ProposedViewSize(contentSize)
        )
    }
}

struct PetWindowScaledContent<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        PetWindowScaledLayout(scale: scale) {
            content
                .scaleEffect(scale, anchor: .bottom)
        }
    }
}

enum PetListeningLayoutSynchronization {
    static func statusHeightDelta(
        focused: Bool,
        activityState: PetActivityState,
        renderedState: PetActivityState,
        rowHeight: CGFloat
    ) -> CGFloat {
        let statusIsVisible = renderedState != .idle

        let statusWillBeVisible: Bool
        if focused, activityState == .idle || activityState == .sleeping {
            statusWillBeVisible = true
        } else if !focused, activityState == .listening {
            statusWillBeVisible = false
        } else {
            statusWillBeVisible = statusIsVisible
        }

        guard statusWillBeVisible != statusIsVisible else { return 0 }
        return statusWillBeVisible ? rowHeight : -rowHeight
    }
}

struct PetRootView: View {
    @ObservedObject var petViewBackend: PetViewBackend
    @ObservedObject private var coordinator: PetStateCoordinator
    @ObservedObject private var windowController: PetWindowController
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3
    @AppStorage("commandConfirmationStyle") private var commandConfirmationStyle = "nearPet"
    @AppStorage(PetHorizontalPosition.storageKey) private var horizontalPosition = PetHorizontalPosition.defaultValue
    @AppStorage(AgentWorkspaceSettings.showCloudTransferNoticeKey) private var showCloudTransferNotice = false
    @AppStorage(AgentWorkspaceSettings.showDirectoryAccessStatusKey) private var showDirectoryAccessStatus = false

    @State private var isHoveringPet = false
    @State private var isHoveringInput = false
    @State private var keepInputVisible = false
    @State private var hasInputText = false
    @State private var showQuickMenu = false
    @State private var isFileDropTargeted = false
    @State private var hasAppeared = false
    @FocusState private var isInputFocused: Bool

    private let layoutMetrics = PetLayoutMetrics.live

    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        _coordinator = ObservedObject(wrappedValue: petViewBackend.stateCoordinator)
        _windowController = ObservedObject(wrappedValue: PetWindowController.shared)
    }

    private var shouldShowInput: Bool {
        isHoveringPet || isHoveringInput || isInputFocused || keepInputVisible || hasInputText
            || !petViewBackend.pendingAttachments.isEmpty
    }

    private var usesNearbyConfirmation: Bool {
        commandConfirmationStyle == "nearPet"
    }

    private var petStackSpacing: CGFloat {
        layoutMetrics.petStackSpacing(for: overlapRatio)
    }

    var body: some View {
        VStack(spacing: petStackSpacing) {
            VStack(spacing: PetPanelLayoutMetrics.spacing) {
                if showQuickMenu {
                    PetQuickMenuView(
                        backend: petViewBackend,
                        onDismiss: { withAnimation(DesignAnimation.fast) { showQuickMenu = false } }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if usesNearbyConfirmation && petViewBackend.showCommandConfirm {
                    PetConfirmationCardView(
                        summary: petViewBackend.pendingCommand,
                        onConfirm: petViewBackend.confirmAndRunCommand,
                        onCancel: petViewBackend.cancelPendingCommand
                    )
                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
                }

                if petViewBackend.showOutputBox {
                    PetSpeechBubbleContainer(
                        responseStore: petViewBackend.streamedResponseStore,
                        state: coordinator.snapshot.renderedState,
                        canCancel: canCancelCurrentRequest,
                        onCancel: petViewBackend.cancelActiveRequest,
                        onDismiss: petViewBackend.dismissOutputBox,
                        onOpenDialog: { AppWindowRouter.shared.showDialog() }
                    )
                    // 输出框高度由流式文本决定。如果再从底部移入，
                    // 它会与窗口扩展产生两套纵向运动，让下方的 GIF 看起来上下移动。
                    .transition(.opacity)
                }

                if coordinator.snapshot.renderedState != .idle {
                    PetStatusIndicatorView(state: coordinator.snapshot.renderedState)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if !petViewBackend.pendingAttachments.isEmpty {
                    VStack(spacing: 5) {
                        PetAttachmentTrayView(
                            attachments: petViewBackend.pendingAttachments,
                            onRemove: petViewBackend.removeAttachment,
                            onClear: petViewBackend.clearAttachments
                        )
                        if showCloudTransferNotice && AgentWorkspaceSettings.isCloudModel() {
                            Label("附件将由云端模型处理", systemImage: "icloud.and.arrow.up")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }
                        if showDirectoryAccessStatus && AgentFileAccessStore.shared.requiresAuthorization {
                            Label("已授权本轮附件", systemImage: "folder.badge.checkmark")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // 始终保留输入框的布局槽。悬浮不改变根视图的固有尺寸；用户通过
                // Option 调整窗口时，由窗口控制器在固有尺寸之外统一缩放整套界面。
                ZStack(alignment: .bottom) {
                    if shouldShowInput {
                        PetInputView(
                            isFocused: $isInputFocused,
                            placeholder: inputPlaceholder,
                            isDisabled: coordinator.snapshot.activityState == .waitingForConfirmation,
                            onHover: { isHoveringInput = $0 },
                            onTextPresenceChanged: { hasInputText = $0 },
                            onSubmit: submitInput,
                            onCancel: cancelInput
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: PetPanelLayoutMetrics.inputHeight,
                    maxHeight: PetPanelLayoutMetrics.inputHeight,
                    alignment: .bottom
                )
                .animation(DesignAnimation.fast, value: shouldShowInput)
            }
            .zIndex(2)

            PetHorizontalPositionLayout(position: horizontalPosition) {
                PetWindowScaledContent(scale: windowController.contentScale) {
                    PetCharacterView(
                        character: petViewBackend.currentCharacter,
                        resolvedAsset: petViewBackend.currentResolvedAsset,
                        coordinator: coordinator,
                        horizontalPosition: horizontalPosition,
                        isFileDropTargeted: isFileDropTargeted,
                        onHover: handlePetHover,
                        onTap: petViewBackend.handleTap,
                        onDoubleTap: { AppWindowRouter.shared.showDialog() },
                        onRightClick: {
                            withAnimation(DesignAnimation.spring) { showQuickMenu.toggle() }
                        },
                        onDragBegan: {
                            showQuickMenu = false
                            PetWindowController.shared.beginDragging()
                        },
                        onDragChanged: { initialOrigin, delta in
                            PetWindowController.shared.dragWindow(from: initialOrigin, screenDelta: delta)
                        },
                        onDragEnded: { PetWindowController.shared.endDragging() },
                        onFileDrop: handleFileDrop,
                        onFileDropTargetChanged: { targeted in
                            withAnimation(DesignAnimation.fast) {
                                isFileDropTargeted = targeted
                            }
                        }
                    )
                    .equatable()
                }
                .scaleEffect(hasAppeared ? 1 : 0.96, anchor: .bottom)
            }
            // 面板宽度跟随窗口，角色在这段可用宽度内连续移动。
            .frame(maxWidth: .infinity)
            .zIndex(1)
        }
        .frame(width: PetWindowSizing.panelWidth(for: windowController.contentScale))
        .padding(8)
        .fixedSize(horizontal: true, vertical: true)
        .background(PetWindowAccessor())
        .reportPetWindowContentSize()
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            petViewBackend.onAppear()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { hasAppeared = true }
        }
        .onDisappear {
            petViewBackend.onDisappear()
            PetWindowController.shared.setInteractionLocked(false)
        }
        .onChange(of: isInputFocused) { _, focused in
            synchronizeWindowForListeningChange(focused: focused)
            petViewBackend.handleInputFocusChanged(focused)
        }
        .alert("工具调用确认", isPresented: systemConfirmationBinding) {
            Button("执行") { petViewBackend.confirmAndRunCommand() }
            Button("取消", role: .cancel) { petViewBackend.cancelPendingCommand() }
        } message: {
            Text("Agent 请求执行：\(petViewBackend.pendingCommand)")
        }
    }

    private var canCancelCurrentRequest: Bool {
        switch coordinator.snapshot.activityState {
        case .thinking, .talking, .automation:
            return true
        default:
            return false
        }
    }

    private var systemConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !usesNearbyConfirmation && petViewBackend.showCommandConfirm },
            set: { newValue in
                if !newValue, petViewBackend.showCommandConfirm {
                    petViewBackend.cancelPendingCommand()
                }
            }
        )
    }

    private var inputPlaceholder: String {
        let count = petViewBackend.pendingAttachments.count
        guard count > 0 else { return petViewBackend.conversationStyle.inputPlaceholder }
        return "想让我怎么处理这 \(count) 个项目？"
    }

    private func submitInput(_ text: String) {
        petViewBackend.submitExternalInput(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isInputFocused = false
        }
    }

    private func cancelInput() {
        isInputFocused = false
        isHoveringInput = false
        hasInputText = false
        keepInputVisible = false
        petViewBackend.clearAttachments()
    }

    private func handleFileDrop(_ urls: [URL]) {
        let added = petViewBackend.attachFiles(urls)
        guard added > 0 else { return }
        showQuickMenu = false
        keepInputVisible = true
        isInputFocused = true
    }

    private func handlePetHover(_ hovering: Bool) {
        isHoveringPet = hovering
        if hovering {
            keepInputVisible = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !isHoveringPet && !isHoveringInput && !isInputFocused {
                    keepInputVisible = false
                }
            }
        }
    }

    /// Focus changes are the only state transition where the status row is
    /// introduced by the input control itself. Resize the bottom-anchored
    /// window before publishing `listening`, so SwiftUI never lays out the
    /// extra row inside the previous, shorter window for a single frame.
    private func synchronizeWindowForListeningChange(focused: Bool) {
        let snapshot = coordinator.snapshot
        let rowHeight = PetStatusIndicatorView.height + PetPanelLayoutMetrics.spacing
        let heightDelta = PetListeningLayoutSynchronization.statusHeightDelta(
            focused: focused,
            activityState: snapshot.activityState,
            renderedState: snapshot.renderedState,
            rowHeight: rowHeight
        )
        windowController.resizeForImmediateContentHeightChange(by: heightDelta)
    }
}
