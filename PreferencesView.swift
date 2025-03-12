//
//  setting.swift
//  看板娘
//
//  Created by 姜智浩 on 2025/3/10.
//

import SwiftUI

struct PreferencesView: View {
    // 使用AppStorage自动连接到UserDefaults
    @AppStorage("apiKey") private var apiKey = "请删除并替换自己的API key"
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    
    // 环境变量，用于关闭窗口
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        TabView {
            // 第一个选项卡 - 风格设置
            VStack(alignment: .leading, spacing: 20) {
                Text("系统提示词:")
                TextEditor(text: $systemPrompt)
                    .frame(width: 300, height: 180)
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
            .tabItem {
                Label("风格", systemImage: "person.crop.circle")
            }
            
            // 第二个选项卡 - 模型设置
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Text("模型：(仅支持智谱清言)")
                    TextEditor(text: $aiModel)
                        .frame(width: 300, height: 20)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .font(.system(size: 14))                }
                .padding(.bottom, 10)
                
                VStack(alignment: .leading) {
                    Text("API Key:")
                    TextEditor(text: $apiKey)
                        .frame(width: 300, height: 100)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .font(.system(size: 14))
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
            .tabItem {
                Label("模型设置", systemImage: "network")
            }
            
            // 第三个选项卡 - 关于
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
        }
        .frame(width: 400, height: 350)
        .onDisappear {
            // 当设置窗口关闭时，发送通知来更新应用设置
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
