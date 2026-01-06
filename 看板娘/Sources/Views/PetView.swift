import SwiftUI
import SDWebImageSwiftUI

struct PetView: View {
    
    // MARK: - 属性
    
    @ObservedObject var petViewBackend: PetViewBackend
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3
    
    // MARK: - 主体
    var body: some View {
        VStack(spacing: 0) {
            inputField
            
            Spacer().frame(height: 8)  // inputField 和 chatOutput 之间的间距
            
            // 使用 ZStack 实现重叠效果
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    chatOutput
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    // 根据重叠比例计算偏移量
                    let chatHeight: CGFloat = 80
                    let noOverlapSpacing: CGFloat = 30  // 0% 时的间距（30像素）
                    let maxOverlap = chatHeight + noOverlapSpacing  // 最大重叠量（从30px间距到完全重叠）
                    let overlapAmount = maxOverlap * overlapRatio
                    
                    // 从 chatHeight + 30px 开始，随着 overlapRatio 增加而减少间距
                    Spacer().frame(height: chatHeight + noOverlapSpacing - overlapAmount)
                    
                    petImage
                        .frame(width: 200, height: 200)
                }
            }
        }
        .onAppear {
            petViewBackend.onAppear()
        }
        .onDisappear {
            petViewBackend.onDisappear()
        }
    }
    
    // MARK: - 子视图
    private var inputField: some View {
        TextField("我会帮助指挥官解决问题...", text: $petViewBackend.userInput)
            .textFieldStyle(PlainTextFieldStyle())
            .modifier(EnhancedTextFieldStyle())
            .padding([.top, .leading, .trailing])
            .onSubmit {
                withAnimation(DesignAnimation.spring) {
                    petViewBackend.submitInput()
                }
            }
    }
    private var chatOutput: some View {
        ScrollView {
            Text(petViewBackend.streamedResponse)
                .font(DesignFonts.body)
                .lineSpacing(4)
                .padding(DesignSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .frame(maxWidth: .infinity, maxHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignColors.surfaceLight)
        )
        .modifier(SmoothScrollStyle())
        .padding([.leading, .trailing])
    }
    private var petImage: some View {
        AnimatedImage(name: petViewBackend.currentGif)
            .resizable()
            .id(petViewBackend.currentGif)
            .scaledToFit()
            .frame(width: 300, height: 300)
            .onTapGesture {
                petViewBackend.handleTap()
            }
    }
}
