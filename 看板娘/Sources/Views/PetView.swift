//
//  PetView.swift
//  桌面宠物应用
//
//  宠物主视图，显示输入框、对话输出和宠物动画
//

import SwiftUI
import SDWebImageSwiftUI
import SDWebImage

// MARK: - 宠物视图

/// 宠物主视图
/// 包含用户输入、对话输出和宠物动画显示
struct PetView: View {
    
    // MARK: - 属性
    
    /// 宠物视图后端
    @ObservedObject var petViewBackend: PetViewBackend
    
    /// 界面重叠比例
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3

    private let layoutMetrics = PetLayoutMetrics.live
    
    /// 鼠标是否悬停在宠物动图上
    @State private var isHoveringPet = false
    
    /// 输入框获得焦点时保持显示
    @FocusState private var isInputFocused: Bool
    
    /// 输入框是否应该显示（悬停或聚焦时）
    private var shouldShowInput: Bool {
        isHoveringPet || isInputFocused || !petViewBackend.userInput.isEmpty
    }
    
    // MARK: - 主体
    var body: some View {
        VStack(spacing: 0) {
            // 输入框：始终占据布局空间，通过 opacity 控制显隐
            // 当输出框不显示时，输入框紧贴动图上方；有输出框时在输出框上方
            inputField
                .opacity(shouldShowInput ? 1 : 0)
                .scaleEffect(shouldShowInput ? 1 : 0.9)
                .offset(y: shouldShowInput ? 0 : 10)
                .allowsHitTesting(shouldShowInput)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: shouldShowInput)
            
            Spacer().frame(height: layoutMetrics.inputToChatSpacing)
            
            // 使用 ZStack 实现重叠效果（保持原始布局）
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // 输出框：始终占据布局空间，通过 opacity 控制显隐
                    chatOutput
                        .opacity(petViewBackend.showOutputBox ? 1 : 0)
                        .scaleEffect(petViewBackend.showOutputBox ? 1 : 0.92)
                        .offset(y: petViewBackend.showOutputBox ? 0 : -8)
                        .allowsHitTesting(petViewBackend.showOutputBox)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.1),
                            value: petViewBackend.showOutputBox
                        )
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    Spacer().frame(height: layoutMetrics.petTopSpacing(for: overlapRatio))
                    
                    petImage
                        .frame(width: layoutMetrics.petFrameSize, height: layoutMetrics.petFrameSize)
                }
            }
        }
        .onAppear {
            petViewBackend.onAppear()
        }
        .onDisappear {
            petViewBackend.onDisappear()
        }
        .alert("执行命令确认", isPresented: $petViewBackend.showCommandConfirm) {
            Button("执行", role: .none) {
                petViewBackend.confirmAndRunCommand()
            }
            Button("取消", role: .cancel) {
                petViewBackend.cancelPendingCommand()
            }
        } message: {
            Text("将执行命令：\(petViewBackend.pendingCommand)")
        }
    }
    
    // MARK: - 子视图
    
    /// 用户输入框
    private var inputField: some View {
        TextField(
            "用户输入",
            text: $petViewBackend.userInput,
            prompt: Text("我会帮助指挥官解决问题...")
                .foregroundColor(.gray)
        )
            .textFieldStyle(PlainTextFieldStyle())
            .foregroundColor(.black)
            .modifier(EnhancedTextFieldStyle())
            .focused($isInputFocused)
            .padding([.top, .leading, .trailing])
            .onSubmit {
                withAnimation(DesignAnimation.spring) {
                    petViewBackend.submitInput()
                }
                // 提交后延迟取消焦点，让输入框优雅消失
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isInputFocused = false
                }
            }
    }
    
    /// 对话输出区域
    private var chatOutput: some View {
        ScrollView {
            Text(petViewBackend.streamedResponse)
                .font(DesignFonts.body)
                .foregroundColor(.black)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(DesignSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .frame(maxWidth: .infinity, maxHeight: layoutMetrics.chatHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignColors.surfaceLight)
        )
        .modifier(SmoothScrollStyle())
        .padding([.leading, .trailing])
        .onTapGesture {
            // 点击输出框时重置自动隐藏计时器
            petViewBackend.revealOutputBox(autoHideAfter: 15)
        }
    }
    
    /// 宠物图像显示
    /// 使用 AlphaHitTestOverlay 实现透明像素穿透，只有点击到非透明区域才触发动作
    private var petImage: some View {
        Group {
            if petViewBackend.currentGif.hasPrefix("/") {
                // 自定义角色：从文件系统加载
                AnimatedImage(url: URL(fileURLWithPath: petViewBackend.currentGif))
                    .resizable()
                    .id(petViewBackend.currentGif)
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .overlay(
                        AlphaHitTestOverlay {
                            petViewBackend.handleTap()
                        }
                    )
                    .onDisappear {
                        SDImageCache.shared.clearMemory()
                    }
            } else {
                // 内置角色：从Bundle加载
                AnimatedImage(name: petViewBackend.currentGif)
                    .resizable()
                    .id(petViewBackend.currentGif)
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .overlay(
                        AlphaHitTestOverlay {
                            petViewBackend.handleTap()
                        }
                    )
                    .onDisappear {
                        SDImageCache.shared.clearMemory()
                    }
            }
        }
        .onHover { hovering in
            isHoveringPet = hovering
        }
    }
}
