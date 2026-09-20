//
//  SystemPermissionCenter.swift
//  看板娘
//
//  User-initiated macOS privacy permission requests and live status.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum SystemPermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case screenRecording
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "设备控制"
        case .screenRecording: return "录屏"
        case .automation: return "自动化"
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.inset.filled.and.person.filled"
        case .automation: return "gearshape.2"
        }
    }

    var detail: String {
        switch self {
        case .accessibility:
            return "允许读取界面元素并在你确认后操作其他 App。"
        case .screenRecording:
            return "允许截取你指定的 App 窗口，用于视觉识别和操作结果验证。"
        case .automation:
            return "Apple Events 权限按目标 App 单独授予，首次执行已确认的脚本时由系统询问。"
        }
    }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .automation: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

@MainActor
final class SystemPermissionCenter: ObservableObject {
    enum Status: Equatable {
        case granted
        case notGranted
        case perApplication

        var title: String {
            switch self {
            case .granted: return "已授权"
            case .notGranted: return "未授权"
            case .perApplication: return "按 App 授权"
            }
        }

        var systemImage: String {
            switch self {
            case .granted: return "checkmark.circle.fill"
            case .notGranted: return "exclamationmark.circle.fill"
            case .perApplication: return "info.circle.fill"
            }
        }
    }

    @Published private(set) var accessibilityStatus: Status = .notGranted
    @Published private(set) var screenRecordingStatus: Status = .notGranted

    init() {
        refresh()
    }

    func status(for kind: SystemPermissionKind) -> Status {
        switch kind {
        case .accessibility: return accessibilityStatus
        case .screenRecording: return screenRecordingStatus
        case .automation: return .perApplication
        }
    }

    func refresh() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .notGranted
        screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    func request(_ kind: SystemPermissionKind) {
        switch kind {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            refresh()
            if accessibilityStatus != .granted {
                openSettings(for: kind)
            }
        case .screenRecording:
            let granted = CGRequestScreenCaptureAccess()
            refresh()
            if !granted {
                openSettings(for: kind)
            }
        case .automation:
            openSettings(for: kind)
        }
    }

    func openSettings(for kind: SystemPermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
