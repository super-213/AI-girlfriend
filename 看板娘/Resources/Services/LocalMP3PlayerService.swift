//
//  LocalMP3PlayerService.swift
//  桌面宠物应用
//
//  本地 MP3 文件播放服务
//

import AVFoundation
import Foundation

enum LocalMP3PlayerError: LocalizedError {
    case missingBookmark
    case bookmarkStale
    case fileNotFound
    case unreadableFile
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .missingBookmark:
            return "尚未选择 MP3 文件"
        case .bookmarkStale:
            return "MP3 文件授权已失效，请重新选择文件"
        case .fileNotFound:
            return "MP3 文件不存在"
        case .unreadableFile:
            return "MP3 文件不可读或无访问权限"
        case .unsupportedFile:
            return "请选择 .mp3 文件"
        }
    }
}

final class LocalMP3PlayerService: NSObject, AVAudioPlayerDelegate {
    static let shared = LocalMP3PlayerService()

    private var player: AVAudioPlayer?
    private var scopedURL: URL?
    private var activeTriggerId: UUID?
    private var onFinish: ((UUID) -> Void)?

    func play(
        bookmarkData: Data?,
        triggerId: UUID,
        onFinish: @escaping (UUID) -> Void
    ) throws {
        stop()

        guard let bookmarkData else {
            throw LocalMP3PlayerError.missingBookmark
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard !isStale else {
            throw LocalMP3PlayerError.bookmarkStale
        }

        guard url.pathExtension.lowercased() == "mp3" else {
            throw LocalMP3PlayerError.unsupportedFile
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocalMP3PlayerError.fileNotFound
        }

        guard FileManager.default.isReadableFile(atPath: url.path),
              url.startAccessingSecurityScopedResource() else {
            throw LocalMP3PlayerError.unreadableFile
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.currentTime = 0
            player.prepareToPlay()

            self.player = player
            self.scopedURL = url
            self.activeTriggerId = triggerId
            self.onFinish = onFinish

            guard player.play() else {
                cleanupScopedResource()
                throw LocalMP3PlayerError.unreadableFile
            }
        } catch {
            cleanupScopedResource()
            throw error
        }
    }

    func stop() {
        player?.stop()
        cleanupScopedResource()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let activeTriggerId else {
            cleanupScopedResource()
            return
        }

        let finish = onFinish
        cleanupScopedResource()
        finish?(activeTriggerId)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        cleanupScopedResource()
    }

    private func cleanupScopedResource() {
        player?.delegate = nil
        player = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        activeTriggerId = nil
        onFinish = nil
    }
}
