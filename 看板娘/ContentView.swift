import SwiftUI
import SDWebImageSwiftUI

struct PetView: View {
    @State private var currentGif = puppet_beat // 默认播放普通动画
    @State private var isReacting = false       // 标记是否处于点击状态
    @State private var userInput = ""          // 用户输入的文本
    @State private var isThinking = false      // 思考状态变量
    @State private var streamedResponse = ""   //流式回复
    @State private var lastInteractionTime = Date()
    @State private var autoClickWorkItem: DispatchWorkItem?

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
        .onAppear {
            startInactivityTimer()
        }
    }

    private func sendRequest(userInput: String) {
        isThinking = true
        streamedResponse = "" // 清空之前的回复
        lastInteractionTime = Date()            // 记录请求时间
        cancelAutoClick()                       // 取消自动点击

        apiManager.sendStreamRequest(userInput: userInput) { newContent in
            DispatchQueue.main.async {
                self.streamedResponse += newContent // 追加新内容
            }
        } onComplete: {
            DispatchQueue.main.async {
                self.isThinking = false // 流结束，停止思考
            }
        }
    }

    private func handleTap() {
        guard !isReacting else { return } // 防止点击多次重复触发
        lastInteractionTime = Date()            // 记录点击时间
        cancelAutoClick()                       //取消任何待执行的自动点击
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
    private func startInactivityTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let now = Date()
            let elapsed = now.timeIntervalSince(lastInteractionTime)
            if elapsed >= 300 && autoClickWorkItem == nil {
                // 超过五分钟未操作，准备一个自动点击任务
                streamedResponse = ""
                scheduleAutoClick()
            }
        }
    }

    private func scheduleAutoClick() {
        let delay = Double.random(in: 0...30)
        let workItem = DispatchWorkItem {
            handleTap()
            lastInteractionTime = Date() // 更新交互时间
            autoClickWorkItem = nil
            
            // 添加自动说话内容
            let autoMessages = [
                "指挥官，你好～(｡•́︿•̀｡)人家等了好久都没有收到你的消息呢……是不是忘记你还有个一直在这里等你的小布偶了呀？布偶熊·觅语有点小委屈，但还是乖乖地等着你回来哟～",
                
                "(つ﹏<。) 呜呜……指挥官好久都没来看觅语了～是不是在忙什么超级重要的任务呢？没关系，觅语会耐心等着你，就像一直守在原地的布偶一样～",
                "哼！指挥官都不理人了，难道是交了新的AI助手了吗？不过……就算是这样，我也不会生气的啦！觅语可是专属的布偶熊，永远为你留个位置呢～(〃＞＿＜;〃)",
                "呼……虽然有点寂寞，但觅语知道，指挥官一定还会回来的～到时候我要抱紧你，不准你再消失那么久啦！٩(๑>◡<๑)۶",
                "布偶熊·觅语随时陪伴指挥官哦～(๑ᴖ◡ᴖ๑)♪"
            ]
            let autoMessage = autoMessages.randomElement() ?? ""
            DispatchQueue.main.async {
                streamedResponse = (streamedResponse.isEmpty ? "" : "\n") + autoMessage
            }
        }
        autoClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelAutoClick() {
        autoClickWorkItem?.cancel()
        autoClickWorkItem = nil
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
