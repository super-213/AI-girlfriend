//
//  setting.swift
//  看板娘
//
//  Created by 姜智浩 on 2025/3/10.
//

import SwiftUI

struct PreferencesView: View {
    // 使用AppStorage自动连接到UserDefaults
    @AppStorage("apiKey") private var apiKey = "d9110ecebbf244aab69d3db43781f03c.W4KB9WyATuiwpYsf"
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    
    // 环境变量，用于关闭窗口
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        TabView {
            
            // 第一页 - 风格设置
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("系统提示词:")
                    TextEditor(text: $systemPrompt)
                        .frame(height: 180)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .font(.system(size: 14))

                    Spacer()
                    HStack {
                        Spacer()
                        Button("保存") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("风格", systemImage: "person.crop.circle")
            }

            // 第二页 - 模型设置
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("模型：(仅支持智谱清言)")
                        TextField("请输入模型", text: $aiModel)
                            .frame(width: 300)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    VStack(alignment: .leading) {
                        Text("API 地址：")
                        TextField("请输入 API 地址", text: $apiUrl)
                            .frame(width: 300)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    VStack(alignment: .leading) {
                        Text("API Key:")
                        TextEditor(text: $apiKey)
                            .frame(height: 100)
                            .border(Color.gray.opacity(0.3), width: 1)
                    }

                    Spacer()
                    HStack {
                        Spacer()
                        Button("保存") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("模型设置", systemImage: "network")
            }

            // 第三页 - 关于
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "heart.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.pink)
                        .padding()

                    Text("布偶熊·觅语")
                        .font(.title)
                        .bold()

                    Text("版本 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("一个可爱的桌面AI伴侣")
                        .padding(.top, 5)

                    Spacer()
                    HStack {
                        Spacer()
                        Button("关闭") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
        }
        .frame(width: 400, height: 350)
        .onDisappear {
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
