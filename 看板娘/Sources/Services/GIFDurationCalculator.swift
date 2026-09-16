//
//  GIFDurationCalculator.swift
//  看板娘
//
//  GIF动画时长计算服务
//

import Foundation
import ImageIO
import AppKit

/// GIF/APNG 动画时长计算器（保留原名称以兼容现有调用）。
struct GIFDurationCalculator {
    private final class DurationCache: @unchecked Sendable {
        let values = NSCache<NSString, NSNumber>()
    }

    private static let cache = DurationCache()

    /// Returns a previously calculated duration without touching the GIF file.
    /// Interaction handlers use this method so pointer feedback never waits for
    /// ImageIO metadata parsing.
    static func cachedDuration(for gifName: String) -> TimeInterval? {
        cache.values.object(forKey: gifName as NSString)?.doubleValue
    }

    /// Warms the duration cache away from the main actor. The original GIF is
    /// left untouched and remains the source used by the animated image view.
    static func prefetchDuration(for gifName: String) {
        guard cachedDuration(for: gifName) == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = getDuration(for: gifName)
        }
    }
    
    /// 计算GIF动画的实际播放时长
    /// - Parameter gifName: GIF文件名或路径
    /// - Returns: GIF的总播放时长（秒）
    static func getDuration(for gifName: String) -> TimeInterval {
        if let cached = cachedDuration(for: gifName) {
            return cached
        }

        guard let gifUrl = getImageURL(name: gifName) else {
            return 2.0
        }

        guard let imageSource = CGImageSourceCreateWithURL(gifUrl as CFURL, nil) else {
            return 2.0
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        var totalDuration: TimeInterval = 0

        for i in 0..<frameCount {
            let frameDuration = getFrameDuration(from: imageSource, at: i)
            totalDuration += frameDuration
        }

        let resolvedDuration = totalDuration >= 0.5 ? totalDuration : 2.0
        cache.values.setObject(NSNumber(value: resolvedDuration), forKey: gifName as NSString)
        return resolvedDuration
    }

    
    /// 获取单帧的延迟时间
    private static func getFrameDuration(from imageSource: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any] else {
            return 0.1
        }

        let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let pngInfo = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
        let frameDuration = positiveDuration(
            gifInfo?[kCGImagePropertyGIFUnclampedDelayTime as String],
            gifInfo?[kCGImagePropertyGIFDelayTime as String],
            pngInfo?[kCGImagePropertyAPNGUnclampedDelayTime as String],
            pngInfo?[kCGImagePropertyAPNGDelayTime as String]
        ) ?? 0.1
        
        return frameDuration
    }

    private static func positiveDuration(_ values: Any?...) -> TimeInterval? {
        values.lazy.compactMap { value -> TimeInterval? in
            if let value = value as? NSNumber, value.doubleValue > 0 {
                return value.doubleValue
            }
            return nil
        }.first
    }
    
    /// 获取GIF文件的URL
    private static func getImageURL(name gifName: String) -> URL? {
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
            
            return nil
        }
    }
}
