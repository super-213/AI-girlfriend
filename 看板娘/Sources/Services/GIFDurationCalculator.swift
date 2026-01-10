//
//  GIFDurationCalculator.swift
//  桌面宠物应用
//
//  GIF动画时长计算服务
//

import Foundation
import ImageIO
import AppKit

/// GIF动画时长计算器
struct GIFDurationCalculator {
    
    /// 计算GIF动画的实际播放时长
    /// - Parameter gifName: GIF文件名或路径
    /// - Returns: GIF的总播放时长（秒）
    static func getDuration(for gifName: String) -> TimeInterval {
        guard let gifUrl = getGifUrl(gifName: gifName) else {
            #if DEBUG
            print("无法获取GIF URL: \(gifName)")
            #endif
            return 2.0
        }
        
        #if DEBUG
        print("GIF路径: \(gifUrl.path)")
        #endif
        
        guard let imageSource = CGImageSourceCreateWithURL(gifUrl as CFURL, nil) else {
            #if DEBUG
            print("无法创建ImageSource")
            #endif
            return 2.0
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)
        #if DEBUG
        print("总帧数: \(frameCount)")
        #endif
        
        var totalDuration: TimeInterval = 0
        
        for i in 0..<frameCount {
            let frameDuration = getFrameDuration(from: imageSource, at: i)
            totalDuration += frameDuration
            
            #if DEBUG
            print("第\(i)帧延迟: \(frameDuration)秒")
            #endif
        }
        
        #if DEBUG
        print("总时长: \(totalDuration)秒")
        #endif
        
        return totalDuration >= 0.5 ? totalDuration : 2.0
    }

    
    /// 获取单帧的延迟时间
    private static func getFrameDuration(from imageSource: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any],
              let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            #if DEBUG
            print("第\(index)帧无法读取属性")
            #endif
            return 0.1
        }
        
        var frameDuration: TimeInterval = 0.1
        
        // 优先使用 UnclampedDelayTime
        if let unclampedDelay = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval,
           unclampedDelay > 0 {
            frameDuration = unclampedDelay
        } else if let delay = gifInfo[kCGImagePropertyGIFDelayTime as String] as? TimeInterval,
                  delay > 0 {
            frameDuration = delay
        }
        
        // 限制最小延迟
        if frameDuration < 0.02 {
            frameDuration = 0.1
        }
        
        return frameDuration
    }
    
    /// 获取GIF文件的URL
    private static func getGifUrl(gifName: String) -> URL? {
        if gifName.hasPrefix("/") {
            return URL(fileURLWithPath: gifName)
        } else {
            if let url = Bundle.main.url(forResource: gifName, withExtension: nil) {
                return url
            }
            
            let nameWithoutExtension = gifName.replacingOccurrences(of: ".gif", with: "")
            if let url = Bundle.main.url(forResource: nameWithoutExtension, withExtension: "gif") {
                return url
            }
            
            if let url = Bundle.main.url(forResource: gifName, withExtension: nil, subdirectory: "Resources/Animations") {
                return url
            }
            
            if let url = Bundle.main.url(forResource: nameWithoutExtension, withExtension: "gif", subdirectory: "Resources/Animations") {
                return url
            }
            
            #if DEBUG
            print("尝试了所有路径都找不到: \(gifName)")
            #endif
            return nil
        }
    }
}
