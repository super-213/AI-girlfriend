//
//  MusicPlayerService.swift
//  桌面宠物应用
//
//  音乐播放服务
//

import Foundation
import AppKit

/// 音乐播放服务
struct MusicPlayerService {
    
    /// 从用户输入中提取歌曲名称
    /// - Parameter input: 用户输入的文本
    /// - Returns: 提取出的歌曲名称
    static func extractSongName(from input: String) -> String {
        let keywords = ["我想听", "播放", "来一首", "来点", "帮我放"]
        var result = input
        
        for keyword in keywords {
            result = result.replacingOccurrences(of: keyword, with: "")
        }
        
        result = result.replacingOccurrences(of: "的歌", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 在Apple Music中播放指定歌曲
    /// - Parameter songName: 歌曲名称
    /// - Returns: 播放结果消息
    static func playSong(named songName: String) -> String {
        guard let encoded = songName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "歌名好像有点奇怪呢～(｡•́︿•̀｡)"
        }
        
        if let appUrl = URL(string: "music://music.apple.com/search?term=\(encoded)"),
           NSWorkspace.shared.urlForApplication(toOpen: appUrl) != nil {
            NSWorkspace.shared.open(appUrl)
            return successMessage(for: songName)
        } else if let webUrl = URL(string: "https://music.apple.com/search?term=\(encoded)") {
            NSWorkspace.shared.open(webUrl)
            return successMessage(for: songName)
        } else {
            return "呜～好像打不开音乐应用呢 (｡•́︿•̀｡)"
        }
    }
    
    private static func successMessage(for songName: String) -> String {
        "已经帮指挥官打开《\(songName)》的搜索啦～记得点击播放哦 (๑ᴖ◡ᴖ๑)♪\n布偶熊·觅语随时陪伴指挥官哦～"
    }
}
