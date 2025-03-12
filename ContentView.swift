import SwiftUI
import SDWebImageSwiftUI

struct PetView: View {
    @State private var currentGif = puppet_beat // 默认播放普通动画
    @State private var isReacting = false       // 标记是否处于点击状态
    @State private var userInput = ""          // 用户输入的文本
    @State private var aiResponse = ""         // AI 的回复
    @State private var isThinking = false      // 思考状态变量

    let normalGif = puppet_beat                // 普通动画
    let clickGifs = loop_puppet_bear             // 点击时的多个反应动画
    let gifDurations = puppet_bear_duration // 每个 GIF 动画对应的播放时长（秒）

    private let apiManager = APIManager()

    var body: some View {
        VStack {
            // 输入框
            TextField("我会帮助指挥官解决问题...", text: $userInput)
                .padding(10)
                .background(Color.white.opacity(0.2)) // 透明背景
                .cornerRadius(8)
                .textFieldStyle(PlainTextFieldStyle()) // 去除默认边框和蓝色框选
                .padding([.top, .leading, .trailing])
                .onSubmit {
                    // 当按下回车键时触发提交操作
                    sendRequest(userInput: userInput)
                    userInput = "" // 清空输入框
                }

            // 显示 AI 回复的区域，支持滚动
            ScrollView {
                Text(streamedResponse)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isThinking ? 0.6 : 1) // 思考时文字显示为半透明
            }
            .frame(maxWidth: .infinity, maxHeight: 80) // 限制输出框的高度
            .background(Color.white.opacity(0.2)) // 透明背景
            .cornerRadius(8)
            .padding([.leading, .trailing])

            ZStack {
                Color.clear // 背景透明
                AnimatedImage(name: currentGif) // 根据状态显示对应 GIF
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .onTapGesture {
                        handleTap() // 点击事件
                    }
            }
            .frame(width: 200, height: 200)
        }
    }

    @State private var streamedResponse = ""

    private func sendRequest(userInput: String) {
        isThinking = true
        streamedResponse = ""

        apiManager.sendStreamRequest(userInput: userInput) { [self] newContent in
            DispatchQueue.main.async {
                self.streamedResponse += newContent
            }
        } onComplete: {
            DispatchQueue.main.async {
                self.isThinking = false
            }
        }
    }

    private func handleTap() {
        guard !isReacting else { return } // 防止点击多次重复触发
        isReacting = true

        // 创建一个队列依次播放多个 GIF 动画
        playNextGif(index: 0)
    }

    private func playNextGif(index: Int) {
        guard index < clickGifs.count else {
            // 所有动画播放完毕后恢复普通动画
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                currentGif = normalGif
                isReacting = false
            }
            return
        }

        // 播放当前 GIF
        currentGif = clickGifs[index]

        // 获取当前 GIF 的播放时长
        let gifDuration = gifDurations[index]

        DispatchQueue.main.asyncAfter(deadline: .now() + gifDuration) {
            // 播放下一个 GIF
            playNextGif(index: index + 1)
        }
    }
}

struct ContentView: View {
    var body: some View {
        PetView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
