//
//  MemoryOptimizer.swift
//  桌面宠物应用
//
//  内存优化工具
//

import Foundation
import SDWebImage

/// 内存优化管理器
class MemoryOptimizer {
    
    static let shared = MemoryOptimizer()
    
    private init() {
        setupSDWebImageConfig()
        setupMemoryWarningObserver()
    }
    
    /// 配置 SDWebImage 以减少内存占用
    private func setupSDWebImageConfig() {
        let cache = SDImageCache.shared
        
        // 限制内存缓存大小为 50MB（默认可能更大）
        cache.config.maxMemoryCost = 50 * 1024 * 1024
        
        // 限制缓存的图片数量
        cache.config.maxMemoryCount = 10
        
        // GIF解码选项 - 只保留部分帧在内存中
        SDImageCodersManager.shared.addCoder(SDImageGIFCoder.shared)
        
        // 启用内存缓存过期策略
        cache.config.shouldUseWeakMemoryCache = true
    }
    
    /// 监听内存警告
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSNotification.Name("NSApplicationDidReceiveMemoryWarning"),
            object: nil
        )
    }
    
    /// 处理内存警告
    @objc private func handleMemoryWarning() {
        clearCache()
    }
    
    /// 清理缓存
    func clearCache() {
        SDImageCache.shared.clearMemory()
        #if DEBUG
        print("已清理图片缓存")
        #endif
    }
    
    /// 定期清理缓存
    func periodicCleanup() {
        // 只清理过期的缓存，不清理全部
        SDImageCache.shared.clearMemory()
    }
}
