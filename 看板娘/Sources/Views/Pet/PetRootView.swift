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

struct PetRootView: View {
    @ObservedObject var petViewBackend: PetViewBackend
    @ObservedObject private var coordinator: PetStateCoordinator
    @ObservedObject private var windowController: PetWindowController
    @AppStorage("commandConfirmationStyle") private var commandConfirmationStyle = "nearPet"
    @AppStorage(PetHorizontalPlacement.storageKey) private var storedHorizontalPlacement = PetHorizontalPlacement.defaultValue.rawValue

    @State private var isHoveringPet = false
    @State private var isHoveringInput = false
    @State private var keepInputVisible = false
    @State private var showQuickMenu = false
    @State private var hasAppeared = false
    @FocusState private var isInputFocused: Bool

    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        _coordinator = ObservedObject(wrappedValue: petViewBackend.stateCoordinator)
        _windowController = ObservedObject(wrappedValue: PetWindowController.shared)
    }

    private var shouldShowInput: Bool {
        isHoveringPet || isHoveringInput || isInputFocused || keepInputVisible || !petViewBackend.userInput.isEmpty
    }

    private var usesNearbyConfirmation: Bool {
        commandConfirmationStyle == "nearPet"
    }

    private var petHorizontalAlignment: Alignment {
        switch PetHorizontalPlacement(rawValue: storedHorizontalPlacement) ?? .defaultValue {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if showQuickMenu {
                PetQuickMenuView(
                    backend: petViewBackend,
                    onDismiss: { withAnimation(DesignAnimation.fast) { showQuickMenu = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if usesNearbyConfirmation && petViewBackend.showCommandConfirm {
                PetConfirmationCardView(
                    command: petViewBackend.pendingCommand,
                    onConfirm: petViewBackend.confirmAndRunCommand,
                    onCancel: petViewBackend.cancelPendingCommand
                )
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            }

            if petViewBackend.showOutputBox && !petViewBackend.streamedResponse.isEmpty {
                PetSpeechBubbleView(
                    text: petViewBackend.streamedResponse,
                    state: coordinator.snapshot.renderedState,
                    canCancel: canCancelCurrentRequest,
                    onCancel: petViewBackend.cancelActiveRequest,
                    onDismiss: petViewBackend.dismissOutputBox,
                    onOpenDialog: { AppWindowRouter.shared.showDialog() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if coordinator.snapshot.renderedState != .idle {
                PetStatusIndicatorView(state: coordinator.snapshot.renderedState)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            // 始终保留输入框的布局槽。悬浮不改变根视图的固有尺寸；用户通过
            // Option 调整窗口时，由窗口控制器在固有尺寸之外统一缩放整套界面。
            ZStack(alignment: .bottom) {
                if shouldShowInput {
                    PetInputView(
                        text: $petViewBackend.userInput,
                        isFocused: $isInputFocused,
                        isDisabled: coordinator.snapshot.activityState == .waitingForConfirmation,
                        onHover: { isHoveringInput = $0 },
                        onSubmit: submitInput
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .bottom)
            .animation(DesignAnimation.fast, value: shouldShowInput)

            PetWindowScaledContent(scale: windowController.contentScale) {
                PetCharacterView(
                    backend: petViewBackend,
                    coordinator: coordinator,
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
                    onDragEnded: { PetWindowController.shared.endDragging() }
                )
            }
            .scaleEffect(hasAppeared ? 1 : 0.96, anchor: .bottom)
            // 面板宽度跟随窗口，角色在这段可用宽度内按设置对齐。
            .frame(maxWidth: .infinity, alignment: petHorizontalAlignment)
            .animation(DesignAnimation.fast, value: storedHorizontalPlacement)
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
            petViewBackend.handleInputFocusChanged(focused)
        }
        .alert("执行命令确认", isPresented: systemConfirmationBinding) {
            Button("执行") { petViewBackend.confirmAndRunCommand() }
            Button("取消", role: .cancel) { petViewBackend.cancelPendingCommand() }
        } message: {
            Text("将执行命令：\(petViewBackend.pendingCommand)")
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

    private func submitInput() {
        petViewBackend.submitInput()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isInputFocused = false
        }
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
}
