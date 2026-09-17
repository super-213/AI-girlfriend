//
//  ComputerUseTools.swift
//  看板娘
//
//  Screen observation, Accessibility inspection and native input for the
//  observe -> act -> observe desktop-control loop.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

private struct DesktopObservation {
    let text: String
    let imagePaths: [String]
    let hasUsefulContent: Bool
}

private struct AccessibilitySnapshot {
    let observationID: UUID
    let application: NSRunningApplication
    let text: String
}

private struct ScreenCaptureObservation {
    let path: String
    let sourceFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    var coordinateMappingDescription: String {
        "screenshot_frame_global=[\(format(sourceFrame.minX)),\(format(sourceFrame.minY)),\(format(sourceFrame.width)),\(format(sourceFrame.height))] "
            + "screenshot_pixels=[\(pixelWidth),\(pixelHeight)] "
            + "mapping=global_x=frame_x+pixel_x*frame_width/pixel_width;global_y=frame_y+pixel_y*frame_height/pixel_height"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", value)
    }
}

private enum ComputerUseError: LocalizedError {
    case applicationNotFound(String)
    case accessibilityPermissionMissing
    case screenCapturePermissionMissing
    case elementNotFound(String)
    case invalidArguments(String)
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let name):
            return "未找到正在运行的应用“\(name)”"
        case .accessibilityPermissionMissing:
            return "尚未授予辅助功能权限。请在系统设置 → 隐私与安全性 → 辅助功能中允许看板娘。"
        case .screenCapturePermissionMissing:
            return "尚未授予屏幕录制权限。请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许看板娘。"
        case .elementNotFound(let label):
            return "未找到可操作的界面元素“\(label)”，请先重新观察界面"
        case .invalidArguments(let message), .actionFailed(let message):
            return message
        }
    }
}

@MainActor
private final class AccessibilityComputerUseService {
    static let shared = AccessibilityComputerUseService()

    private struct StoredElement {
        let observationID: UUID
        let processIdentifier: pid_t
        let element: AXUIElement
        let frame: CGRect?
        let label: String
    }

    private var elementsByHandle: [String: StoredElement] = [:]

    func resolveApplication(_ identifier: String?) throws -> NSRunningApplication {
        let workspace = NSWorkspace.shared
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else {
            if let frontmost = workspace.frontmostApplication {
                return frontmost
            }
            throw ComputerUseError.applicationNotFound("前台应用")
        }

        let needle = identifier.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matches = workspace.runningApplications.filter { app in
            let name = app.localizedName?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let bundleID = app.bundleIdentifier?.lowercased()
            return name == needle || bundleID == identifier.lowercased()
        }
        guard let match = matches.first(where: { $0.isActive }) ?? matches.first else {
            throw ComputerUseError.applicationNotFound(identifier)
        }
        return match
    }

    func snapshot(
        application: NSRunningApplication,
        maxDepth: Int,
        maxNodes: Int
    ) throws -> AccessibilitySnapshot {
        try ensurePermission()
        let observationID = UUID()
        elementsByHandle.removeAll(keepingCapacity: true)
        let root = AXUIElementCreateApplication(application.processIdentifier)
        var lines: [String] = []
        var nodeCount = 0
        appendNode(
            root,
            depth: 0,
            maxDepth: max(1, min(maxDepth, 12)),
            maxNodes: max(10, min(maxNodes, 1_000)),
            observationID: observationID,
            processIdentifier: application.processIdentifier,
            nodeCount: &nodeCount,
            lines: &lines
        )
        let header = "Accessibility observation_id=\(observationID.uuidString), nodes=\(nodeCount)"
        return AccessibilitySnapshot(
            observationID: observationID,
            application: application,
            text: ([header] + lines).joined(separator: "\n")
        )
    }

    func resolveElement(
        application: NSRunningApplication,
        handle: String?,
        label: String?,
        role: String?
    ) throws -> (element: AXUIElement, frame: CGRect?, label: String) {
        try ensurePermission()
        if let handle,
           let stored = elementsByHandle[handle],
           stored.processIdentifier == application.processIdentifier {
            return (stored.element, stored.frame ?? frame(of: stored.element), stored.label)
        }

        guard let rawLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines), !rawLabel.isEmpty else {
            throw ComputerUseError.invalidArguments("操作 Accessibility 元素需要 element_handle 或 label")
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        var visited: Set<CFHashCode> = []
        guard let match = findElement(root, label: rawLabel, role: role, visited: &visited) else {
            throw ComputerUseError.elementNotFound(rawLabel)
        }
        return (match, frame(of: match), elementLabel(match))
    }

    func press(_ element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw ComputerUseError.actionFailed("Accessibility 按压失败：\(result.rawValue)")
        }
    }

    func setValue(_ value: String, on element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        guard result == .success else {
            throw ComputerUseError.actionFailed("Accessibility 设置值失败：\(result.rawValue)")
        }
    }

    func ensureInputPermission() throws {
        try ensurePermission()
    }

    func storedLabel(for handle: String?) -> String? {
        guard let handle else { return nil }
        return elementsByHandle[handle]?.label
    }

    private func ensurePermission() throws {
        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            throw ComputerUseError.accessibilityPermissionMissing
        }
    }

    private func appendNode(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        observationID: UUID,
        processIdentifier: pid_t,
        nodeCount: inout Int,
        lines: inout [String]
    ) {
        guard nodeCount < maxNodes else { return }
        nodeCount += 1
        let handle = "ax-\(observationID.uuidString.prefix(8))-\(nodeCount)"
        let role = stringAttribute(kAXRoleAttribute, element: element) ?? "AXUnknown"
        let subrole = stringAttribute(kAXSubroleAttribute, element: element)
        let title = stringAttribute(kAXTitleAttribute, element: element)
        let description = stringAttribute(kAXDescriptionAttribute, element: element)
        let identifier = stringAttribute(kAXIdentifierAttribute, element: element)
        let value = safeValue(element: element, role: role, subrole: subrole)
        let enabled = boolAttribute(kAXEnabledAttribute, element: element)
        let currentFrame = frame(of: element)
        let label = [title, description, identifier].compactMap { $0 }.first ?? value ?? role
        elementsByHandle[handle] = StoredElement(
            observationID: observationID,
            processIdentifier: processIdentifier,
            element: element,
            frame: currentFrame,
            label: label
        )

        var properties = ["handle=\(handle)", "role=\(role)"]
        if let subrole { properties.append("subrole=\(subrole)") }
        if let title, !title.isEmpty { properties.append("title=\(quoted(title))") }
        if let description, !description.isEmpty, description != title { properties.append("description=\(quoted(description))") }
        if let identifier, !identifier.isEmpty { properties.append("identifier=\(quoted(identifier))") }
        if let value, !value.isEmpty, value != title { properties.append("value=\(quoted(value))") }
        if let enabled { properties.append("enabled=\(enabled)") }
        if let currentFrame {
            properties.append("frame=[\(rounded(currentFrame.minX)),\(rounded(currentFrame.minY)),\(rounded(currentFrame.width)),\(rounded(currentFrame.height))]")
        }
        let actions = actionNames(element)
        if !actions.isEmpty { properties.append("actions=\(actions.joined(separator: ","))") }
        lines.append(String(repeating: "  ", count: depth) + properties.joined(separator: " "))

        guard depth < maxDepth else { return }
        for child in children(element) where nodeCount < maxNodes {
            appendNode(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                observationID: observationID,
                processIdentifier: processIdentifier,
                nodeCount: &nodeCount,
                lines: &lines
            )
        }
    }

    private func findElement(
        _ element: AXUIElement,
        label: String,
        role: String?,
        visited: inout Set<CFHashCode>
    ) -> AXUIElement? {
        guard visited.count < 1_500, visited.insert(CFHash(element)).inserted else { return nil }
        let expected = normalized(label)
        let actualRole = stringAttribute(kAXRoleAttribute, element: element)
        let roleMatches = role == nil || normalized(actualRole ?? "") == normalized(role ?? "")
        let candidates = [
            stringAttribute(kAXTitleAttribute, element: element),
            stringAttribute(kAXDescriptionAttribute, element: element),
            stringAttribute(kAXIdentifierAttribute, element: element),
            stringAttribute(kAXValueAttribute, element: element)
        ].compactMap { $0 }.map(normalized)
        if roleMatches, candidates.contains(expected) {
            return element
        }
        for child in children(element) {
            if let match = findElement(child, label: label, role: role, visited: &visited) {
                return match
            }
        }
        if roleMatches, candidates.contains(where: { $0.contains(expected) }) {
            return element
        }
        return nil
    }

    private func elementLabel(_ element: AXUIElement) -> String {
        stringAttribute(kAXTitleAttribute, element: element)
            ?? stringAttribute(kAXDescriptionAttribute, element: element)
            ?? stringAttribute(kAXIdentifierAttribute, element: element)
            ?? stringAttribute(kAXRoleAttribute, element: element)
            ?? "Accessibility element"
    }

    private func attribute(_ name: CFString, element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ name: String, element: AXUIElement) -> String? {
        guard let value = attribute(name as CFString, element: element) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func boolAttribute(_ name: String, element: AXUIElement) -> Bool? {
        guard let value = attribute(name as CFString, element: element) as? NSNumber else { return nil }
        return value.boolValue
    }

    private func safeValue(element: AXUIElement, role: String, subrole: String?) -> String? {
        let securityDescription = (role + " " + (subrole ?? "")).lowercased()
        if securityDescription.contains("secure") { return "<secure>" }
        guard let value = stringAttribute(kAXValueAttribute, element: element) else { return nil }
        return String(value.prefix(240))
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute as CFString, element: element) as? [AXUIElement] ?? []
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let rawPosition = attribute(kAXPositionAttribute as CFString, element: element),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = attribute(kAXSizeAttribute as CFString, element: element),
              CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func actionNames(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func quoted(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\n", with: " ")
        return "\"\(String(cleaned.prefix(240)))\""
    }

    private func rounded(_ value: CGFloat) -> String {
        String(format: "%.0f", value)
    }
}

@MainActor
private final class ScreenCaptureComputerUseService {
    static let shared = ScreenCaptureComputerUseService()

    func capture(application: NSRunningApplication?) async throws -> ScreenCaptureObservation {
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            throw ComputerUseError.screenCapturePermissionMissing
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        let sourceFrame: CGRect
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = true
        configuration.ignoreShadowsSingleWindow = true

        if let application,
           let window = content.windows
            .first(where: { $0.owningApplication?.processID == application.processIdentifier && $0.isOnScreen && $0.frame.width > 40 && $0.frame.height > 40 }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            sourceFrame = window.frame
            let size = boundedPixelSize(width: window.frame.width, height: window.frame.height)
            configuration.width = size.width
            configuration.height = size.height
        } else {
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                throw ComputerUseError.actionFailed("未找到可捕获的显示器")
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let excludedApplications = content.applications.filter { $0.processID == ownPID }
            filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            sourceFrame = CGDisplayBounds(display.displayID)
            let size = boundedPixelSize(width: CGFloat(display.width), height: CGFloat(display.height))
            configuration.width = size.width
            configuration.height = size.height
        }

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return ScreenCaptureObservation(
            path: try writePNG(image),
            sourceFrame: sourceFrame,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }

    private func boundedPixelSize(width: CGFloat, height: CGFloat) -> (width: Int, height: Int) {
        let longest = max(width, height)
        let scale = longest > 2_048 ? 2_048 / longest : 1
        return (max(1, Int(width * scale)), max(1, Int(height * scale)))
    }

    private func writePNG(_ image: CGImage) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-computer-use", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeExpiredCaptures(in: directory)
        let url = directory.appendingPathComponent("observation-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ComputerUseError.actionFailed("无法创建屏幕截图文件")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ComputerUseError.actionFailed("无法写入屏幕截图")
        }
        return url.path
    }

    private func removeExpiredCaptures(in directory: URL) {
        let expiration = Date().addingTimeInterval(-3_600)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate,
                  date < expiration else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
private final class DesktopObservationService {
    static let shared = DesktopObservationService()

    func observe(
        applicationIdentifier: String?,
        includeScreenshot: Bool,
        includeAccessibility: Bool,
        maxDepth: Int,
        maxNodes: Int
    ) async -> DesktopObservation {
        var sections: [String] = []
        var imagePaths: [String] = []
        var useful = false
        let application: NSRunningApplication?
        do {
            application = try AccessibilityComputerUseService.shared.resolveApplication(applicationIdentifier)
            if let application {
                sections.append("target_application=\(application.localizedName ?? "Unknown") bundle_id=\(application.bundleIdentifier ?? "unknown") pid=\(application.processIdentifier)")
            }
        } catch {
            sections.append("application_error=\(error.localizedDescription)")
            if let applicationIdentifier,
               !applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DesktopObservation(
                    text: sections.joined(separator: "\n"),
                    imagePaths: [],
                    hasUsefulContent: false
                )
            }
            application = nil
        }

        if includeAccessibility, let application {
            do {
                let snapshot = try AccessibilityComputerUseService.shared.snapshot(
                    application: application,
                    maxDepth: maxDepth,
                    maxNodes: maxNodes
                )
                sections.append(snapshot.text)
                useful = true
            } catch {
                sections.append("accessibility_error=\(error.localizedDescription)")
            }
        }

        if includeScreenshot {
            do {
                let capture = try await ScreenCaptureComputerUseService.shared.capture(application: application)
                imagePaths.append(capture.path)
                sections.append("screenshot=\(capture.path)")
                sections.append(capture.coordinateMappingDescription)
                useful = true
            } catch {
                sections.append("screenshot_error=\(error.localizedDescription)")
            }
        }

        return DesktopObservation(
            text: sections.joined(separator: "\n"),
            imagePaths: imagePaths,
            hasUsefulContent: useful
        )
    }
}

@MainActor
private enum UIActionRiskPolicy {
    private static let highRiskTerms = [
        "send", "submit", "publish", "post", "upload", "share", "delete", "remove", "erase",
        "overwrite", "replace", "install", "confirm", "pay", "purchase", "buy", "transfer",
        "confirm payment", "place order", "发送", "提交", "发布", "上传", "共享", "删除", "移除",
        "清空", "覆盖", "替换", "安装", "确认", "付款", "购买", "下单", "转账"
    ]

    static func requiresConfirmation(arguments: [String: Any]) -> Bool {
        let action = (arguments["action"] as? String ?? "").lowercased()
        let storedLabel = AccessibilityComputerUseService.shared.storedLabel(
            for: arguments["element_handle"] as? String
        )
        let semanticContext = [
            arguments["label"] as? String,
            storedLabel
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        let canCommit = ["press", "click", "double_click", "right_click", "drag", "key_press"].contains(action)
        if canCommit, highRiskTerms.contains(where: semanticContext.contains) { return true }

        let semanticTargetProvided = arguments["label"] != nil || storedLabel != nil
        if ["press", "click", "double_click", "right_click", "drag"].contains(action), !semanticTargetProvided {
            return true
        }
        if action == "key_press",
           let key = arguments["key"] as? String,
           ["return", "enter", "delete"].contains(key.lowercased()) {
            return true
        }
        return false
    }
}

@MainActor
private final class NativeInputService {
    static let shared = NativeInputService()

    func perform(arguments: [String: Any], application: NSRunningApplication) throws -> String {
        guard let action = arguments["action"] as? String else {
            throw ComputerUseError.invalidArguments("缺少 action")
        }
        try AccessibilityComputerUseService.shared.ensureInputPermission()
        application.activate()

        switch action {
        case "press":
            let target = try accessibilityTarget(arguments: arguments, application: application)
            do {
                try AccessibilityComputerUseService.shared.press(target.element)
            } catch {
                guard let frame = target.frame else { throw error }
                click(point: CGPoint(x: frame.midX, y: frame.midY), button: .left, count: 1)
            }
            return "已按压 \(target.label)"
        case "set_value":
            guard let value = arguments["text"] as? String else {
                throw ComputerUseError.invalidArguments("set_value 缺少 text")
            }
            let target = try accessibilityTarget(arguments: arguments, application: application)
            try AccessibilityComputerUseService.shared.setValue(value, on: target.element)
            return "已设置 \(target.label) 的值"
        case "click", "double_click", "right_click":
            let point = try targetPoint(arguments: arguments, application: application)
            let button: CGMouseButton = action == "right_click" ? .right : .left
            click(point: point, button: button, count: action == "double_click" ? 2 : 1)
            return "已在 (\(Int(point.x)), \(Int(point.y))) 执行 \(action)"
        case "scroll":
            let point = optionalPoint(arguments: arguments)
            if let point { movePointer(to: point) }
            let deltaX = intValue(arguments["delta_x"]) ?? 0
            let deltaY = intValue(arguments["delta_y"]) ?? -480
            scroll(deltaX: deltaX, deltaY: deltaY)
            return "已滚动 delta_x=\(deltaX), delta_y=\(deltaY)"
        case "drag":
            let start = try requiredPoint(arguments: arguments, xKey: "x", yKey: "y")
            let end = try requiredPoint(arguments: arguments, xKey: "to_x", yKey: "to_y")
            drag(from: start, to: end)
            return "已从 (\(Int(start.x)), \(Int(start.y))) 拖动到 (\(Int(end.x)), \(Int(end.y)))"
        case "key_press":
            guard let key = arguments["key"] as? String, let keyCode = keyCode(for: key) else {
                throw ComputerUseError.invalidArguments("不支持的 key")
            }
            let modifiers = eventFlags(arguments["modifiers"] as? [String] ?? [])
            keyPress(code: keyCode, flags: modifiers)
            return "已按下快捷键 \((arguments["modifiers"] as? [String] ?? []).joined(separator: "+"))\(modifiers.isEmpty ? "" : "+")\(key)"
        case "type_text":
            guard let text = arguments["text"] as? String else {
                throw ComputerUseError.invalidArguments("type_text 缺少 text")
            }
            typeText(text)
            return "已输入 \(text.count) 个字符"
        default:
            throw ComputerUseError.invalidArguments("不支持的 action：\(action)")
        }
    }

    private func accessibilityTarget(
        arguments: [String: Any],
        application: NSRunningApplication
    ) throws -> (element: AXUIElement, frame: CGRect?, label: String) {
        try AccessibilityComputerUseService.shared.resolveElement(
            application: application,
            handle: arguments["element_handle"] as? String,
            label: arguments["label"] as? String,
            role: arguments["role"] as? String
        )
    }

    private func targetPoint(arguments: [String: Any], application: NSRunningApplication) throws -> CGPoint {
        if arguments["element_handle"] != nil || arguments["label"] != nil {
            let target = try accessibilityTarget(arguments: arguments, application: application)
            guard let frame = target.frame else {
                throw ComputerUseError.actionFailed("目标元素没有可用的坐标")
            }
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return try requiredPoint(arguments: arguments, xKey: "x", yKey: "y")
    }

    private func optionalPoint(arguments: [String: Any]) -> CGPoint? {
        guard let x = doubleValue(arguments["x"]), let y = doubleValue(arguments["y"]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func requiredPoint(arguments: [String: Any], xKey: String, yKey: String) throws -> CGPoint {
        guard let x = doubleValue(arguments[xKey]), let y = doubleValue(arguments[yKey]) else {
            throw ComputerUseError.invalidArguments("缺少坐标 \(xKey)/\(yKey)")
        }
        return CGPoint(x: x, y: y)
    }

    private func click(point: CGPoint, button: CGMouseButton, count: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        for index in 1...count {
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button)
            let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func movePointer(to point: CGPoint) {
        CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func scroll(deltaX: Int32, deltaY: Int32) {
        CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )?.post(tap: .cghidEventTap)
    }

    private func drag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        for step in 1...12 {
            let progress = CGFloat(step) / 12
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func keyPress(code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        let utf16 = Array(text.utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        utf16.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        let values: [String: CGKeyCode] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
            "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126,
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6,
            "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
            "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
            "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47, "`": 50
        ]
        return values[key.lowercased()]
    }

    private func eventFlags(_ modifiers: [String]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { result, modifier in
            switch modifier.lowercased() {
            case "command", "cmd": result.insert(.maskCommand)
            case "shift": result.insert(.maskShift)
            case "option", "alt": result.insert(.maskAlternate)
            case "control", "ctrl": result.insert(.maskControl)
            default: break
            }
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "")
    }

    private func intValue(_ value: Any?) -> Int32? {
        guard let number = doubleValue(value) else { return nil }
        return Int32(clamping: Int(number))
    }
}

@MainActor
final class ObserveDesktopTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "observe_desktop",
        description: "观察当前 macOS 应用界面，返回目标窗口截图和 Accessibility 元素树。在使用 perform_ui_action 前和操作后用它确认界面状态。",
        parameters: [
            "type": "object",
            "properties": [
                "application": ["type": "string", "description": "可选的应用名称或 bundle identifier；省略时观察前台应用"],
                "include_screenshot": ["type": "boolean", "description": "是否截图，默认 true"],
                "include_accessibility": ["type": "boolean", "description": "是否读取 Accessibility 元素树，默认 true"],
                "max_depth": ["type": "integer", "description": "Accessibility 树最大深度，默认 6"],
                "max_nodes": ["type": "integer", "description": "Accessibility 树最大节点数，默认 240"]
            ],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "观察 \(arguments["application"] as? String ?? "前台应用") 界面"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let includeScreenshot = arguments["include_screenshot"] as? Bool ?? true
        let includeAccessibility = arguments["include_accessibility"] as? Bool ?? true
        guard includeScreenshot || includeAccessibility else {
            completion(.failure("include_screenshot 和 include_accessibility 不能同时为 false"))
            return
        }
        let maxDepth = (arguments["max_depth"] as? NSNumber)?.intValue ?? 6
        let maxNodes = (arguments["max_nodes"] as? NSNumber)?.intValue ?? 240
        Task { @MainActor in
            let observation = await DesktopObservationService.shared.observe(
                applicationIdentifier: arguments["application"] as? String,
                includeScreenshot: includeScreenshot,
                includeAccessibility: includeAccessibility,
                maxDepth: maxDepth,
                maxNodes: maxNodes
            )
            if observation.hasUsefulContent {
                completion(.success(observation.text, imagePaths: observation.imagePaths))
            } else {
                completion(.failure(observation.text))
            }
        }
    }
}

@MainActor
final class PerformUIActionTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "perform_ui_action",
        description: "对 macOS 应用执行单步界面操作。优先使用 observe_desktop 返回的 element_handle 或控件 label，只在无法语义定位时使用坐标。操作后会自动返回新的截图和 Accessibility 状态。",
        parameters: [
            "type": "object",
            "properties": [
                "application": ["type": "string", "description": "应用名称或 bundle identifier"],
                "action": ["type": "string", "enum": ["press", "set_value", "click", "double_click", "right_click", "scroll", "drag", "key_press", "type_text"]],
                "element_handle": ["type": "string", "description": "observe_desktop 返回的 AX 元素句柄"],
                "label": ["type": "string", "description": "控件名称；也用于向用户说明高风险操作"],
                "role": ["type": "string", "description": "可选 AX role，用于缩小同名控件范围"],
                "text": ["type": "string", "description": "set_value 或 type_text 的文本"],
                "x": ["type": "number"], "y": ["type": "number"],
                "to_x": ["type": "number"], "to_y": ["type": "number"],
                "delta_x": ["type": "integer"], "delta_y": ["type": "integer"],
                "key": ["type": "string", "description": "key_press 的按键，例如 return/tab/escape/a"],
                "modifiers": ["type": "array", "items": ["type": "string", "enum": ["command", "shift", "option", "control"]]]
            ],
            "required": ["application", "action"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func requiresConfirmation(arguments: [String: Any]) -> Bool {
        UIActionRiskPolicy.requiresConfirmation(arguments: arguments)
    }

    func approvalSummary(arguments: [String: Any]) -> String {
        let application = arguments["application"] as? String ?? "目标应用"
        let action = arguments["action"] as? String ?? "界面操作"
        let target = arguments["label"] as? String ?? {
            if let x = arguments["x"], let y = arguments["y"] { return "坐标 (\(x), \(y))" }
            return arguments["element_handle"] as? String ?? "当前焦点"
        }()
        return "在 \(application) 中执行 \(action)：\(target)"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        do {
            let applicationName = arguments["application"] as? String
            let application = try AccessibilityComputerUseService.shared.resolveApplication(applicationName)
            let actionResult = try NativeInputService.shared.perform(arguments: arguments, application: application)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                let observation = await DesktopObservationService.shared.observe(
                    applicationIdentifier: application.bundleIdentifier ?? application.localizedName,
                    includeScreenshot: true,
                    includeAccessibility: true,
                    maxDepth: 6,
                    maxNodes: 240
                )
                let result = "\(actionResult)\n\n操作后状态：\n\(observation.text)"
                completion(.success(result, imagePaths: observation.imagePaths))
            }
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}
