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
import Vision

private struct DesktopObservation {
    let observationID: UUID
    let text: String
    let imagePaths: [String]
    let hasUsefulContent: Bool
    let state: UIObservationState
}

private struct AccessibilitySnapshot {
    let observationID: UUID
    let application: NSRunningApplication
    let text: String
    let fingerprint: String
    let searchableText: String
    let elementLabels: Set<String>
    let windowTitles: [String]
    let focusedWindowFrame: CGRect?
    let focusedWindowTitle: String?
    let meaningfulElementCount: Int
    let needsVisualFallback: Bool
    let focusedElementLabel: String?
    let selectedElementLabels: Set<String>
    let disabledElementLabels: Set<String>
    let modalWindowTitles: [String]
}

struct UIElementSemanticRecord: Equatable {
    let handle: String
    let parentHandle: String?
    let ancestorHandles: [String]
    let windowHandle: String?
    let role: String
    let label: String
    let identifier: String?
    let frame: CGRect?
    let enabled: Bool?
    let focused: Bool
    let selected: Bool
    let modal: Bool
    let ancestorLabels: [String]

    var semanticSignature: String {
        [
            role,
            label,
            identifier ?? "",
            enabled.map(String.init) ?? "unknown",
            String(focused),
            String(selected),
            String(modal),
            frame.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" } ?? ""
        ].joined(separator: "|")
    }
}

struct UIElementScopeQuery: Equatable {
    let label: String
    let role: String?
    let scopeHandle: String?
    let windowHandle: String?
    let rowLabel: String?
    let occurrence: Int?
    let selectedOnly: Bool

    init(arguments: [String: Any]) {
        label = (arguments["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        role = Self.trimmed(arguments["role"])
        scopeHandle = Self.trimmed(arguments["scope_handle"])
        windowHandle = Self.trimmed(arguments["window_handle"])
        rowLabel = Self.trimmed(arguments["row_label"])
        occurrence = (arguments["occurrence"] as? NSNumber)?.intValue
        selectedOnly = arguments["selected_only"] as? Bool ?? false
    }

    init(
        label: String,
        role: String? = nil,
        scopeHandle: String? = nil,
        windowHandle: String? = nil,
        rowLabel: String? = nil,
        occurrence: Int? = nil,
        selectedOnly: Bool = false
    ) {
        self.label = label
        self.role = role
        self.scopeHandle = scopeHandle
        self.windowHandle = windowHandle
        self.rowLabel = rowLabel
        self.occurrence = occurrence
        self.selectedOnly = selectedOnly
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum UIElementScopeResolution: Equatable {
    case match(UIElementSemanticRecord)
    case notFound
    case ambiguous([UIElementSemanticRecord])
}

enum UIElementScopeResolver {
    static func resolve(
        records: [UIElementSemanticRecord],
        query: UIElementScopeQuery
    ) -> UIElementScopeResolution {
        let expected = normalized(query.label)
        var matches = records.filter { record in
            let roleMatches = query.role == nil || normalized(record.role) == normalized(query.role ?? "")
            let label = normalized(record.label)
            let labelMatches = label == expected || label.contains(expected)
            let scopeMatches = query.scopeHandle == nil
                || record.parentHandle == query.scopeHandle
                || record.ancestorHandles.contains(query.scopeHandle ?? "")
            let windowMatches = query.windowHandle == nil || record.windowHandle == query.windowHandle
            let rowMatches = query.rowLabel == nil
                || record.ancestorLabels.contains(where: { normalized($0).contains(normalized(query.rowLabel ?? "")) })
            return roleMatches && labelMatches && scopeMatches && windowMatches && rowMatches
                && (!query.selectedOnly || record.selected)
        }
        let exact = matches.filter { normalized($0.label) == expected }
        if !exact.isEmpty { matches = exact }
        matches.sort {
            if $0.focused != $1.focused { return $0.focused }
            if $0.selected != $1.selected { return $0.selected }
            let lhsY = $0.frame?.minY ?? .greatestFiniteMagnitude
            let rhsY = $1.frame?.minY ?? .greatestFiniteMagnitude
            if lhsY != rhsY { return lhsY < rhsY }
            return ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude)
        }
        if let occurrence = query.occurrence {
            guard occurrence > 0, occurrence <= matches.count else { return .notFound }
            return .match(matches[occurrence - 1])
        }
        if matches.count == 1, let match = matches.first { return .match(match) }
        if matches.isEmpty { return .notFound }
        return .ambiguous(matches)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum UIStableElementIdentity {
    static func stableKey(
        applicationIdentifier: String,
        parentHandle: String?,
        role: String,
        subrole: String?,
        identifier: String?,
        label: String,
        siblingIndex: Int,
        windowRuntimeIdentity: UInt?
    ) -> String {
        let identity: String
        if let identifier, !identifier.isEmpty {
            identity = "id:\(normalized(identifier))"
        } else if let windowRuntimeIdentity {
            identity = "window:\(normalized(subrole ?? "")):\(windowRuntimeIdentity)"
        } else {
            identity = "semantic:\(normalized(label)):\(siblingIndex)"
        }
        return [applicationIdentifier.lowercased(), parentHandle ?? "root", role, subrole ?? "", identity]
            .joined(separator: "|")
    }

    static func handle(for stableKey: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in stableKey.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "ax-\(String(hash, radix: 16))"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct VisualTextRegion {
    let handle: String
    let text: String
    let confidence: Float
    let globalFrame: CGRect
}

private struct ScreenCaptureObservation {
    let observationID: UUID
    let path: String?
    let sourceFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let signature: [UInt8]
    let recognizedText: String
    let visualTextRegions: [VisualTextRegion]

    var coordinateMappingDescription: String {
        "screenshot_frame_global=[\(format(sourceFrame.minX)),\(format(sourceFrame.minY)),\(format(sourceFrame.width)),\(format(sourceFrame.height))] "
            + "screenshot_pixels=[\(pixelWidth),\(pixelHeight)] "
            + "mapping=global_x=frame_x+pixel_x*frame_width/pixel_width;global_y=frame_y+pixel_y*frame_height/pixel_height"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", value)
    }
}

struct UIObservationState: Equatable {
    var observationID: String?
    var applicationIdentifier: String?
    var accessibilityFingerprint: String?
    var screenshotSignature: [UInt8]?
    var searchableText = ""
    var elementLabels: Set<String> = []
    var windowTitles: [String] = []
    var ocrText = ""
    var focusedElementLabel: String?
    var selectedElementLabels: Set<String> = []
    var disabledElementLabels: Set<String> = []
    var modalWindowTitles: [String] = []

    var hasAnySource: Bool {
        accessibilityFingerprint != nil || screenshotSignature != nil
    }

    func materiallyDiffers(from previous: UIObservationState) -> Bool {
        if let lhs = applicationIdentifier,
           let rhs = previous.applicationIdentifier,
           lhs != rhs {
            return true
        }
        if let lhs = accessibilityFingerprint,
           let rhs = previous.accessibilityFingerprint,
           lhs != rhs {
            return true
        }
        guard let lhs = screenshotSignature,
              let rhs = previous.screenshotSignature,
              lhs.count == rhs.count,
              !lhs.isEmpty else {
            return false
        }
        let totalDifference = zip(lhs, rhs).reduce(0) { partial, values in
            partial + abs(Int(values.0) - Int(values.1))
        }
        let normalizedDifference = Double(totalDifference) / Double(lhs.count * 255)
        return normalizedDifference >= 0.018
    }
}

struct UIActionExpectation: Equatable {
    let expectedText: String?
    let expectedElement: String?
    let expectedElementAbsent: String?
    let expectedWindowTitle: String?
    let expectedFocusedElement: String?
    let expectedSelectedElement: String?
    let verifyChange: Bool

    init(arguments: [String: Any]) {
        expectedText = Self.trimmed(arguments["expected_text"])
        expectedElement = Self.trimmed(arguments["expected_element"])
        expectedElementAbsent = Self.trimmed(arguments["expected_element_absent"])
        expectedWindowTitle = Self.trimmed(arguments["expected_window_title"])
        expectedFocusedElement = Self.trimmed(arguments["expected_focused_element"])
        expectedSelectedElement = Self.trimmed(arguments["expected_selected_element"])
        verifyChange = arguments["verify_change"] as? Bool ?? true
    }

    var hasExplicitCondition: Bool {
        expectedText != nil
            || expectedElement != nil
            || expectedElementAbsent != nil
            || expectedWindowTitle != nil
            || expectedFocusedElement != nil
            || expectedSelectedElement != nil
    }

    func evaluate(state: UIObservationState, stateChanged: Bool) -> UIActionVerificationEvaluation {
        var unmet: [String] = []
        let searchable = Self.normalized([state.searchableText, state.ocrText].joined(separator: "\n"))
        let labels = Set(state.elementLabels.map(Self.normalized))
        let windowTitles = state.windowTitles.map(Self.normalized)
        if let expectedText, !searchable.contains(Self.normalized(expectedText)) {
            unmet.append("未找到预期文本“\(expectedText)”")
        }
        if expectedText != nil,
           state.accessibilityFingerprint == nil,
           state.ocrText.isEmpty {
            unmet.append("无法通过 Accessibility 或 OCR 验证文本")
        }
        if let expectedElement,
           !labels.contains(where: { $0 == Self.normalized(expectedElement) || $0.contains(Self.normalized(expectedElement)) }) {
            unmet.append("未找到预期控件“\(expectedElement)”")
        }
        if let expectedElementAbsent,
           labels.contains(where: { $0 == Self.normalized(expectedElementAbsent) || $0.contains(Self.normalized(expectedElementAbsent)) }) {
            unmet.append("控件“\(expectedElementAbsent)”仍然存在")
        }
        if let expectedWindowTitle,
           !windowTitles.contains(where: { $0.contains(Self.normalized(expectedWindowTitle)) }) {
            unmet.append("未出现预期窗口“\(expectedWindowTitle)”")
        }
        if (expectedElement != nil || expectedElementAbsent != nil || expectedWindowTitle != nil
            || expectedFocusedElement != nil || expectedSelectedElement != nil),
           state.accessibilityFingerprint == nil {
            unmet.append("无法读取 Accessibility 状态，不能验证控件或窗口条件")
        }
        if let expectedFocusedElement,
           !Self.normalized(state.focusedElementLabel ?? "").contains(Self.normalized(expectedFocusedElement)) {
            unmet.append("当前焦点不是“\(expectedFocusedElement)”")
        }
        if let expectedSelectedElement,
           !state.selectedElementLabels.map(Self.normalized).contains(where: {
               $0 == Self.normalized(expectedSelectedElement) || $0.contains(Self.normalized(expectedSelectedElement))
           }) {
            unmet.append("未选中“\(expectedSelectedElement)”")
        }
        if !hasExplicitCondition, verifyChange, !stateChanged {
            unmet.append("界面状态未发生可观测变化")
        }
        return UIActionVerificationEvaluation(satisfied: unmet.isEmpty, unmetConditions: unmet)
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct UIActionVerificationEvaluation: Equatable {
    let satisfied: Bool
    let unmetConditions: [String]
}

private struct UIActionVerificationResult {
    let passed: Bool
    let stateChanged: Bool
    let attempts: Int
    let elapsedMilliseconds: Int
    let unmetConditions: [String]
    let observedApplicationIdentifier: String?

    var summary: String {
        var lines = [
            "verification_passed=\(passed)",
            "state_changed=\(stateChanged)",
            "verification_attempts=\(attempts)",
            "verification_elapsed_ms=\(elapsedMilliseconds)"
        ]
        if !unmetConditions.isEmpty {
            lines.append("unmet_conditions=\(unmetConditions.joined(separator: "；"))")
        }
        if let observedApplicationIdentifier {
            lines.append("observed_application=\(observedApplicationIdentifier)")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
private final class DesktopApplicationReliabilityService {
    static let shared = DesktopApplicationReliabilityService()

    func activateAndWait(_ application: NSRunningApplication, timeoutMilliseconds: Int = 1_500) async throws {
        application.activate()
        let startedAt = Date()
        repeat {
            if application.isActive
                || NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                return
            }
            try? await Task.sleep(for: .milliseconds(60))
        } while Date().timeIntervalSince(startedAt) * 1_000 < Double(timeoutMilliseconds)
        throw ComputerUseError.actionFailed(
            "无法将应用“\(application.localizedName ?? application.bundleIdentifier ?? "Unknown")”切换到前台"
        )
    }

    func interactionApplication(fallback: NSRunningApplication) -> NSRunningApplication {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier,
              frontmost.processIdentifier != fallback.processIdentifier,
              isSystemTransientApplication(frontmost) else {
            return fallback
        }
        return frontmost
    }

    private func isSystemTransientApplication(_ application: NSRunningApplication) -> Bool {
        let bundleID = application.bundleIdentifier?.lowercased() ?? ""
        let knownPrefixes = [
            "com.apple.appkit.xpc.openandsavepanelservice",
            "com.apple.securityagent",
            "com.apple.coreservicesuiagent",
            "com.apple.viewbridgeauxiliary"
        ]
        return application.activationPolicy == .prohibited
            || knownPrefixes.contains(where: bundleID.hasPrefix)
    }
}

private enum ComputerUseError: LocalizedError {
    case applicationNotFound(String)
    case accessibilityPermissionMissing
    case screenCapturePermissionMissing
    case elementNotFound(String)
    case ambiguousElement(String)
    case reobservationRequired(String)
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
        case .ambiguousElement(let message):
            return "控件定位不唯一：\(message)"
        case .reobservationRequired(let message):
            return "视觉坐标无法安全确认，已重新观察界面：\(message)"
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
        let stableKey: String
        let record: UIElementSemanticRecord
    }

    private var elementsByHandle: [String: StoredElement] = [:]
    private var latestHandlesByProcess: [pid_t: Set<String>] = [:]
    private var previousRecordsByProcess: [pid_t: [String: UIElementSemanticRecord]] = [:]
    private var latestObservationByProcess: [pid_t: UUID] = [:]

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
        maxNodes: Int,
        observationID: UUID = UUID(),
        storeElements: Bool = true
    ) throws -> AccessibilitySnapshot {
        try ensurePermission()
        let root = AXUIElementCreateApplication(application.processIdentifier)
        var lines: [String] = []
        var canonicalLines: [String] = []
        var searchableParts: [String] = []
        var elementLabels: Set<String> = []
        var windowTitles: [String] = []
        var records: [String: UIElementSemanticRecord] = [:]
        var visited: Set<CFHashCode> = []
        var nodeCount = 0
        let focusedWindow: AXUIElement?
        if let rawFocusedWindow = attribute(kAXFocusedWindowAttribute as CFString, element: root),
           CFGetTypeID(rawFocusedWindow) == AXUIElementGetTypeID() {
            focusedWindow = (rawFocusedWindow as! AXUIElement)
        } else {
            focusedWindow = nil
        }
        let focusedWindowFrame = focusedWindow.flatMap { frame(of: $0) }
        let focusedWindowTitle = focusedWindow.flatMap {
            stringAttribute(kAXTitleAttribute, element: $0)
        }
        let focusedElementHash: CFHashCode? = {
            guard let value = attribute(kAXFocusedUIElementAttribute as CFString, element: root),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return CFHash(value)
        }()
        appendNode(
            root,
            depth: 0,
            maxDepth: max(1, min(maxDepth, 12)),
            maxNodes: max(10, min(maxNodes, 1_000)),
            observationID: observationID,
            processIdentifier: application.processIdentifier,
            applicationIdentifier: application.bundleIdentifier ?? application.localizedName ?? "unknown",
            storeElements: storeElements,
            parentHandle: nil,
            ancestorHandles: [],
            ancestorLabels: [],
            owningWindowHandle: nil,
            siblingIndex: 0,
            focusedElementHash: focusedElementHash,
            visited: &visited,
            records: &records,
            nodeCount: &nodeCount,
            lines: &lines,
            canonicalLines: &canonicalLines,
            searchableParts: &searchableParts,
            elementLabels: &elementLabels,
            windowTitles: &windowTitles
        )
        if let focusedWindowTitle, !windowTitles.contains(focusedWindowTitle) {
            windowTitles.append(focusedWindowTitle)
        }
        if let focusedWindowTitle {
            canonicalLines.insert("focused_window=\(focusedWindowTitle)", at: 0)
        }
        if let focusedWindowFrame {
            canonicalLines.insert(
                "focused_window_frame=\(rounded(focusedWindowFrame.minX)),\(rounded(focusedWindowFrame.minY)),\(rounded(focusedWindowFrame.width)),\(rounded(focusedWindowFrame.height))",
                at: 0
            )
        }
        let previousRecords = previousRecordsByProcess[application.processIdentifier] ?? [:]
        let added = records.keys.filter { previousRecords[$0] == nil }.sorted()
        let removed = previousRecords.keys.filter { records[$0] == nil }.sorted()
        let changed = records.keys.filter {
            guard let previous = previousRecords[$0], let current = records[$0] else { return false }
            return previous.semanticSignature != current.semanticSignature
        }.sorted()
        if storeElements {
            previousRecordsByProcess[application.processIdentifier] = records
            latestObservationByProcess[application.processIdentifier] = observationID
            latestHandlesByProcess[application.processIdentifier] = Set(records.keys)
            pruneStoredElements()
        }

        var header = "Accessibility observation_id=\(observationID.uuidString), nodes=\(nodeCount), stable_elements=\(records.count)"
        if let focusedWindowTitle, !focusedWindowTitle.isEmpty {
            header += ", focused_window=\(quoted(focusedWindowTitle))"
        }
        let delta = "AX delta added=\(added.count) changed=\(changed.count) removed=\(removed.count)"
        let deltaDetails = [
            added.isEmpty ? nil : "  added_handles=\(added.prefix(40).joined(separator: ","))",
            changed.isEmpty ? nil : "  changed_handles=\(changed.prefix(40).joined(separator: ","))",
            removed.isEmpty ? nil : "  removed_handles=\(removed.prefix(40).joined(separator: ","))"
        ].compactMap { $0 }
        let focusedLabel = records.values.first(where: \.focused)?.label
        let selectedLabels = Set(records.values.filter(\.selected).map(\.label))
        let disabledLabels = Set(records.values.filter { $0.enabled == false }.map(\.label))
        let modalTitles = records.values.filter { $0.modal && $0.role == kAXWindowRole }.map(\.label)
        let meaningfulElementCount = records.values.filter {
            !$0.label.isEmpty && normalized($0.label) != normalized($0.role)
        }.count
        let containsWebContent = records.values.contains { $0.role == "AXWebArea" }
        return AccessibilitySnapshot(
            observationID: observationID,
            application: application,
            text: ([header, delta] + deltaDetails + lines).joined(separator: "\n"),
            fingerprint: stableFingerprint(canonicalLines.joined(separator: "\n")),
            searchableText: searchableParts.joined(separator: "\n"),
            elementLabels: elementLabels,
            windowTitles: windowTitles,
            focusedWindowFrame: focusedWindowFrame,
            focusedWindowTitle: focusedWindowTitle,
            meaningfulElementCount: meaningfulElementCount,
            needsVisualFallback: meaningfulElementCount < 4 || containsWebContent,
            focusedElementLabel: focusedLabel,
            selectedElementLabels: selectedLabels,
            disabledElementLabels: disabledLabels,
            modalWindowTitles: modalTitles
        )
    }

    func resolveElement(
        application: NSRunningApplication,
        arguments: [String: Any]
    ) throws -> (element: AXUIElement, frame: CGRect?, label: String) {
        try ensurePermission()
        if let handle = arguments["element_handle"] as? String {
            _ = try snapshot(application: application, maxDepth: 12, maxNodes: 1_000)
            if let stored = elementsByHandle[handle], stored.record.enabled == false {
                throw ComputerUseError.actionFailed("目标控件“\(stored.label)”当前已禁用")
            }
            if let target = validatedStoredElement(handle: handle, application: application) {
                return target
            }
            throw ComputerUseError.elementNotFound("过期或已移除的元素 \(handle)")
        }

        var query = UIElementScopeQuery(arguments: arguments)
        guard !query.label.isEmpty else {
            throw ComputerUseError.invalidArguments("操作 Accessibility 元素需要 element_handle 或 label")
        }
        _ = try snapshot(application: application, maxDepth: 12, maxNodes: 1_000)
        let records = currentRecords(for: application.processIdentifier)

        if query.scopeHandle == nil,
           let scopeLabel = arguments["scope_label"] as? String,
           !scopeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let scopeResolution = UIElementScopeResolver.resolve(
                records: records,
                query: UIElementScopeQuery(label: scopeLabel)
            )
            switch scopeResolution {
            case .match(let scope):
                query = UIElementScopeQuery(
                    label: query.label,
                    role: query.role,
                    scopeHandle: scope.handle,
                    windowHandle: query.windowHandle,
                    rowLabel: query.rowLabel,
                    occurrence: query.occurrence,
                    selectedOnly: query.selectedOnly
                )
            case .ambiguous(let scopes):
                throw ComputerUseError.ambiguousElement(
                    "作用域“\(scopeLabel)”有 \(scopes.count) 个匹配，请使用 scope_handle"
                )
            case .notFound:
                throw ComputerUseError.elementNotFound("作用域 \(scopeLabel)")
            }
        }

        switch UIElementScopeResolver.resolve(records: records, query: query) {
        case .match(let record):
            if record.enabled == false {
                throw ComputerUseError.actionFailed("目标控件“\(record.label)”当前已禁用")
            }
            guard let target = validatedStoredElement(handle: record.handle, application: application) else {
                throw ComputerUseError.elementNotFound(record.label)
            }
            return target
        case .notFound:
            throw ComputerUseError.elementNotFound(query.label)
        case .ambiguous(let matches):
            let choices = matches.prefix(8).map { record in
                let scope = record.ancestorLabels.suffix(2).joined(separator: " > ")
                return "\(record.handle){role=\(record.role),scope=\(scope.isEmpty ? "root" : scope)}"
            }.joined(separator: "; ")
            throw ComputerUseError.ambiguousElement(
                "“\(query.label)”有 \(matches.count) 个匹配：\(choices)。请提供 element_handle、scope_handle、window_handle、row_label 或 occurrence"
            )
        }
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
        applicationIdentifier: String,
        storeElements: Bool,
        parentHandle: String?,
        ancestorHandles: [String],
        ancestorLabels: [String],
        owningWindowHandle: String?,
        siblingIndex: Int,
        focusedElementHash: CFHashCode?,
        visited: inout Set<CFHashCode>,
        records: inout [String: UIElementSemanticRecord],
        nodeCount: inout Int,
        lines: inout [String],
        canonicalLines: inout [String],
        searchableParts: inout [String],
        elementLabels: inout Set<String>,
        windowTitles: inout [String]
    ) {
        let elementHash = CFHash(element)
        guard nodeCount < maxNodes, visited.insert(elementHash).inserted else { return }
        nodeCount += 1
        let role = stringAttribute(kAXRoleAttribute, element: element) ?? "AXUnknown"
        let subrole = stringAttribute(kAXSubroleAttribute, element: element)
        let title = stringAttribute(kAXTitleAttribute, element: element)
        let description = stringAttribute(kAXDescriptionAttribute, element: element)
        let identifier = stringAttribute(kAXIdentifierAttribute, element: element)
        let value = safeValue(element: element, role: role, subrole: subrole)
        let enabled = boolAttribute(kAXEnabledAttribute, element: element)
        let focused = boolAttribute(kAXFocusedAttribute, element: element) == true
            || focusedElementHash == elementHash
        let selected = boolAttribute(kAXSelectedAttribute, element: element) == true
        let modal = boolAttribute(kAXModalAttribute, element: element) == true
        let expanded = boolAttribute(kAXExpandedAttribute, element: element)
        let disclosureLevel = stringAttribute(kAXDisclosureLevelAttribute, element: element)
        let orientation = stringAttribute(kAXOrientationAttribute, element: element)
        let currentFrame = frame(of: element)
        let label = [title, description, identifier].compactMap { $0 }.first ?? value ?? role
        let identityLabel = [title, description, identifier].compactMap { $0 }.first ?? role
        let stableKey = UIStableElementIdentity.stableKey(
            applicationIdentifier: applicationIdentifier,
            parentHandle: parentHandle,
            role: role,
            subrole: subrole,
            identifier: identifier,
            label: identityLabel,
            siblingIndex: siblingIndex,
            windowRuntimeIdentity: role == kAXWindowRole ? elementHash : nil
        )
        let handle = UIStableElementIdentity.handle(for: stableKey)
        let windowHandle = role == kAXWindowRole ? handle : owningWindowHandle
        let record = UIElementSemanticRecord(
            handle: handle,
            parentHandle: parentHandle,
            ancestorHandles: ancestorHandles,
            windowHandle: windowHandle,
            role: role,
            label: label,
            identifier: identifier,
            frame: currentFrame,
            enabled: enabled,
            focused: focused,
            selected: selected,
            modal: modal,
            ancestorLabels: ancestorLabels
        )
        records[handle] = record
        if storeElements {
            elementsByHandle[handle] = StoredElement(
                observationID: observationID,
                processIdentifier: processIdentifier,
                element: element,
                frame: currentFrame,
                label: label,
                stableKey: stableKey,
                record: record
            )
        }

        var properties = ["handle=\(handle)", "role=\(role)"]
        if let subrole { properties.append("subrole=\(subrole)") }
        if let title, !title.isEmpty { properties.append("title=\(quoted(title))") }
        if let description, !description.isEmpty, description != title { properties.append("description=\(quoted(description))") }
        if let identifier, !identifier.isEmpty { properties.append("identifier=\(quoted(identifier))") }
        if let value, !value.isEmpty, value != title { properties.append("value=\(quoted(value))") }
        if let enabled { properties.append("enabled=\(enabled)") }
        if focused { properties.append("focused=true") }
        if selected { properties.append("selected=true") }
        if modal { properties.append("modal=true") }
        if let expanded { properties.append("expanded=\(expanded)") }
        if let disclosureLevel { properties.append("disclosure_level=\(disclosureLevel)") }
        if let orientation { properties.append("orientation=\(orientation)") }
        if let windowHandle, role != kAXWindowRole { properties.append("window=\(windowHandle)") }
        if let parentHandle { properties.append("parent=\(parentHandle)") }
        if let currentFrame {
            properties.append("frame=[\(rounded(currentFrame.minX)),\(rounded(currentFrame.minY)),\(rounded(currentFrame.width)),\(rounded(currentFrame.height))]")
        }
        let actions = actionNames(element)
        if !actions.isEmpty { properties.append("actions=\(actions.joined(separator: ","))") }
        lines.append(String(repeating: "  ", count: depth) + properties.joined(separator: " "))
        let canonicalProperties = properties.filter {
            !$0.hasPrefix("handle=") && !$0.hasPrefix("parent=") && !$0.hasPrefix("window=")
        }
        canonicalLines.append(String(repeating: "  ", count: depth) + canonicalProperties.joined(separator: " "))
        for part in [title, description, identifier, value].compactMap({ $0 }) where !part.isEmpty {
            searchableParts.append(part)
        }
        if !label.isEmpty { elementLabels.insert(label) }
        if role == kAXWindowRole, let title, !title.isEmpty { windowTitles.append(title) }

        guard depth < maxDepth else { return }
        let nextAncestorHandles = ancestorHandles + [handle]
        let nextAncestorLabels = label == role ? ancestorLabels : ancestorLabels + [label]
        var siblingOccurrences: [String: Int] = [:]
        for child in semanticChildren(element) where nodeCount < maxNodes {
            let identitySeed = siblingIdentitySeed(child)
            let occurrence = siblingOccurrences[identitySeed, default: 0]
            siblingOccurrences[identitySeed] = occurrence + 1
            appendNode(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                observationID: observationID,
                processIdentifier: processIdentifier,
                applicationIdentifier: applicationIdentifier,
                storeElements: storeElements,
                parentHandle: handle,
                ancestorHandles: nextAncestorHandles,
                ancestorLabels: nextAncestorLabels,
                owningWindowHandle: windowHandle,
                siblingIndex: occurrence,
                focusedElementHash: focusedElementHash,
                visited: &visited,
                records: &records,
                nodeCount: &nodeCount,
                lines: &lines,
                canonicalLines: &canonicalLines,
                searchableParts: &searchableParts,
                elementLabels: &elementLabels,
                windowTitles: &windowTitles
            )
        }
    }

    private func validatedStoredElement(
        handle: String,
        application: NSRunningApplication
    ) -> (element: AXUIElement, frame: CGRect?, label: String)? {
        guard latestHandlesByProcess[application.processIdentifier]?.contains(handle) == true,
              let stored = elementsByHandle[handle],
              stored.processIdentifier == application.processIdentifier else { return nil }
        let currentRole = stringAttribute(kAXRoleAttribute, element: stored.element)
        let currentLabel = elementLabel(stored.element)
        guard currentRole == stored.record.role,
              normalized(currentLabel) == normalized(stored.label) else { return nil }
        if let enabled = boolAttribute(kAXEnabledAttribute, element: stored.element), !enabled {
            return nil
        }
        return (stored.element, frame(of: stored.element) ?? stored.frame, currentLabel)
    }

    private func currentRecords(for processIdentifier: pid_t) -> [UIElementSemanticRecord] {
        let handles = latestHandlesByProcess[processIdentifier] ?? []
        return handles.compactMap { elementsByHandle[$0]?.record }
    }

    private func pruneStoredElements() {
        let currentHandles = latestHandlesByProcess.values.reduce(into: Set<String>()) { result, handles in
            result.formUnion(handles)
        }
        elementsByHandle = elementsByHandle.filter { currentHandles.contains($0.key) }
        if previousRecordsByProcess.count > 16 {
            let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
            previousRecordsByProcess = previousRecordsByProcess.filter { running.contains($0.key) }
            latestHandlesByProcess = latestHandlesByProcess.filter { running.contains($0.key) }
            latestObservationByProcess = latestObservationByProcess.filter { running.contains($0.key) }
        }
    }

    private func elementLabel(_ element: AXUIElement) -> String {
        let role = stringAttribute(kAXRoleAttribute, element: element) ?? "AXUnknown"
        let subrole = stringAttribute(kAXSubroleAttribute, element: element)
        return stringAttribute(kAXTitleAttribute, element: element)
            ?? stringAttribute(kAXDescriptionAttribute, element: element)
            ?? stringAttribute(kAXIdentifierAttribute, element: element)
            ?? safeValue(element: element, role: role, subrole: subrole)
            ?? role
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

    private func semanticChildren(_ element: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXChildrenAttribute,
            "AXChildrenInNavigationOrder",
            "AXVisibleChildren",
            kAXRowsAttribute,
            "AXVisibleRows",
            "AXVisibleCells",
            kAXContentsAttribute,
            kAXSelectedRowsAttribute,
            kAXSelectedChildrenAttribute
        ]
        var seen: Set<CFHashCode> = []
        var result: [AXUIElement] = []
        for name in attributes {
            let values = elementArrayAttribute(name as CFString, element: element, limit: 1_000)
            for child in values where seen.insert(CFHash(child)).inserted {
                result.append(child)
            }
        }
        return result
    }

    private func elementArrayAttribute(
        _ name: CFString,
        element: AXUIElement,
        limit: Int
    ) -> [AXUIElement] {
        var count: CFIndex = 0
        if AXUIElementGetAttributeValueCount(element, name, &count) == .success, count > 0 {
            var values: CFArray?
            let requested = min(count, CFIndex(limit))
            if AXUIElementCopyAttributeValues(element, name, 0, requested, &values) == .success {
                return values as? [AXUIElement] ?? []
            }
        }
        return attribute(name, element: element) as? [AXUIElement] ?? []
    }

    private func siblingIdentitySeed(_ element: AXUIElement) -> String {
        let role = stringAttribute(kAXRoleAttribute, element: element) ?? "AXUnknown"
        let identifier = stringAttribute(kAXIdentifierAttribute, element: element)
        let title = stringAttribute(kAXTitleAttribute, element: element)
        let description = stringAttribute(kAXDescriptionAttribute, element: element)
        let label = identifier ?? title ?? description ?? role
        return "\(role)|\(normalized(label))"
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

    private func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

@MainActor
private final class ScreenCaptureComputerUseService {
    static let shared = ScreenCaptureComputerUseService()
    private var didRequestPermission = false

    private struct VisualObservationContext {
        let processIdentifier: pid_t?
        let signature: [UInt8]
        let sourceFrame: CGRect
        let targets: [String: VisualTextRegion]
    }

    private var contextsByObservationID: [UUID: VisualObservationContext] = [:]
    private var visualTargetsByHandle: [String: (observationID: UUID, region: VisualTextRegion)] = [:]
    private var observationOrder: [UUID] = []

    func capture(
        application: NSRunningApplication?,
        preferredWindowFrame: CGRect? = nil,
        persist: Bool = true,
        observationID: UUID = UUID(),
        performOCR: Bool = false
    ) async throws -> ScreenCaptureObservation {
        if !CGPreflightScreenCaptureAccess() {
            if !didRequestPermission {
                didRequestPermission = true
                guard CGRequestScreenCaptureAccess() else {
                    throw ComputerUseError.screenCapturePermissionMissing
                }
            } else {
                throw ComputerUseError.screenCapturePermissionMissing
            }
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        let sourceFrame: CGRect
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        if let application,
           let window = preferredWindow(
            from: content.windows.filter {
                $0.owningApplication?.processID == application.processIdentifier
                    && $0.isOnScreen
                    && $0.frame.width > 40
                    && $0.frame.height > 40
            },
            matching: preferredWindowFrame
           ) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            sourceFrame = window.frame
            let size = boundedPixelSize(width: window.frame.width, height: window.frame.height)
            configuration.width = size.width
            configuration.height = size.height
        } else {
            guard let display = preferredDisplay(
                from: content.displays,
                matching: preferredWindowFrame
            ) else {
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
        let signature = pixelSignature(image)
        let regions = performOCR
            ? recognizeText(in: image, sourceFrame: sourceFrame, observationID: observationID)
            : []
        let targets = Dictionary(uniqueKeysWithValues: regions.map { ($0.handle, $0) })
        contextsByObservationID[observationID] = VisualObservationContext(
            processIdentifier: application?.processIdentifier,
            signature: signature,
            sourceFrame: sourceFrame,
            targets: targets
        )
        observationOrder.removeAll(where: { $0 == observationID })
        observationOrder.append(observationID)
        for region in regions {
            visualTargetsByHandle[region.handle] = (observationID, region)
        }
        pruneVisualContexts()
        return ScreenCaptureObservation(
            observationID: observationID,
            path: persist ? try writePNG(image) : nil,
            sourceFrame: sourceFrame,
            pixelWidth: image.width,
            pixelHeight: image.height,
            signature: signature,
            recognizedText: regions.map(\.text).joined(separator: "\n"),
            visualTextRegions: regions
        )
    }

    func resolveVisualTarget(
        handle: String,
        application: NSRunningApplication,
        currentSignature: [UInt8]?
    ) throws -> CGPoint {
        guard let target = visualTargetsByHandle[handle],
              let context = contextsByObservationID[target.observationID],
              context.processIdentifier == application.processIdentifier else {
            throw ComputerUseError.reobservationRequired("视觉元素 \(handle) 已过期")
        }
        guard let currentSignature,
              !signatureMateriallyDiffers(context.signature, currentSignature) else {
            throw ComputerUseError.reobservationRequired("截图已发生变化，不再使用旧的 OCR 坐标")
        }
        return CGPoint(x: target.region.globalFrame.midX, y: target.region.globalFrame.midY)
    }

    func validateCoordinateObservation(
        _ rawObservationID: String?,
        application: NSRunningApplication,
        currentSignature: [UInt8]?
    ) throws {
        guard let rawObservationID,
              let observationID = UUID(uuidString: rawObservationID),
              let context = contextsByObservationID[observationID],
              context.processIdentifier == application.processIdentifier else {
            throw ComputerUseError.reobservationRequired("坐标操作必须携带最近 observe_desktop 返回的 coordinate_observation_id")
        }
        guard let currentSignature,
              !signatureMateriallyDiffers(context.signature, currentSignature) else {
            throw ComputerUseError.reobservationRequired("当前界面与坐标所属观察不一致")
        }
    }

    private func preferredWindow(from windows: [SCWindow], matching frame: CGRect?) -> SCWindow? {
        guard let frame else { return windows.first }
        return windows.min { lhs, rhs in
            windowDistance(lhs.frame, frame) < windowDistance(rhs.frame, frame)
        }
    }

    private func preferredDisplay(from displays: [SCDisplay], matching frame: CGRect?) -> SCDisplay? {
        if let frame,
           let display = displays.max(by: {
               CGDisplayBounds($0.displayID).intersection(frame).area
                   < CGDisplayBounds($1.displayID).intersection(frame).area
           }),
           CGDisplayBounds(display.displayID).intersects(frame) {
            return display
        }
        if let pointer = CGEvent(source: nil)?.location,
           let display = displays.first(where: { CGDisplayBounds($0.displayID).contains(pointer) }) {
            return display
        }
        return displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays.first
    }

    private func windowDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let centerDistance = pow(lhs.midX - rhs.midX, 2) + pow(lhs.midY - rhs.midY, 2)
        let sizeDistance = abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
        return centerDistance + sizeDistance * sizeDistance
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

    private func pixelSignature(_ image: CGImage) -> [UInt8] {
        let width = 24
        let height = 24
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return [] }
        var signature: [UInt8] = []
        signature.reserveCapacity(width * height * 3)
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            signature.append(pixels[index])
            signature.append(pixels[index + 1])
            signature.append(pixels[index + 2])
        }
        return signature
    }

    private func recognizeText(
        in image: CGImage,
        sourceFrame: CGRect,
        observationID: UUID
    ) -> [VisualTextRegion] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).enumerated().compactMap { index, observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let globalFrame = CGRect(
                x: sourceFrame.minX + box.minX * sourceFrame.width,
                y: sourceFrame.minY + (1 - box.maxY) * sourceFrame.height,
                width: box.width * sourceFrame.width,
                height: box.height * sourceFrame.height
            )
            return VisualTextRegion(
                handle: "visual-\(observationID.uuidString.prefix(8))-\(index + 1)",
                text: candidate.string,
                confidence: candidate.confidence,
                globalFrame: globalFrame
            )
        }
    }

    private func signatureMateriallyDiffers(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return true }
        let totalDifference = zip(lhs, rhs).reduce(0) { partial, values in
            partial + abs(Int(values.0) - Int(values.1))
        }
        return Double(totalDifference) / Double(lhs.count * 255) >= 0.018
    }

    private func pruneVisualContexts() {
        guard observationOrder.count > 12 else { return }
        observationOrder = Array(observationOrder.suffix(12))
        let retainedIDs = Set(observationOrder)
        contextsByObservationID = contextsByObservationID.filter { retainedIDs.contains($0.key) }
        visualTargetsByHandle = visualTargetsByHandle.filter { retainedIDs.contains($0.value.observationID) }
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

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
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
        maxNodes: Int,
        persistScreenshot: Bool = true,
        storeElements: Bool = true
    ) async -> DesktopObservation {
        let observationID = UUID()
        var sections: [String] = []
        var imagePaths: [String] = []
        var useful = false
        var state = UIObservationState()
        var accessibilitySnapshot: AccessibilitySnapshot?
        state.observationID = observationID.uuidString
        sections.append("coordinate_observation_id=\(observationID.uuidString)")
        sections.append(
            "permissions_before_observation accessibility=\(AXIsProcessTrusted()) screen_capture=\(CGPreflightScreenCaptureAccess())"
        )
        let application: NSRunningApplication?
        do {
            application = try AccessibilityComputerUseService.shared.resolveApplication(applicationIdentifier)
            if let application {
                state.applicationIdentifier = application.bundleIdentifier ?? application.localizedName
                sections.append("target_application=\(application.localizedName ?? "Unknown") bundle_id=\(application.bundleIdentifier ?? "unknown") pid=\(application.processIdentifier)")
            }
        } catch {
            sections.append("application_error=\(error.localizedDescription)")
            if let applicationIdentifier,
               !applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DesktopObservation(
                    observationID: observationID,
                    text: sections.joined(separator: "\n"),
                    imagePaths: [],
                    hasUsefulContent: false,
                    state: state
                )
            }
            application = nil
        }

        if includeAccessibility, let application {
            do {
                let snapshot = try AccessibilityComputerUseService.shared.snapshot(
                    application: application,
                    maxDepth: maxDepth,
                    maxNodes: maxNodes,
                    observationID: observationID,
                    storeElements: storeElements
                )
                accessibilitySnapshot = snapshot
                sections.append(snapshot.text)
                sections.append(
                    "semantic_state focused=\(snapshot.focusedElementLabel ?? "none") "
                        + "selected=\(snapshot.selectedElementLabels.sorted().joined(separator: "|")) "
                        + "disabled=\(snapshot.disabledElementLabels.sorted().joined(separator: "|")) "
                        + "modal_windows=\(snapshot.modalWindowTitles.joined(separator: "|"))"
                )
                state.accessibilityFingerprint = snapshot.fingerprint
                state.searchableText = snapshot.searchableText
                state.elementLabels = snapshot.elementLabels
                state.windowTitles = snapshot.windowTitles
                state.focusedElementLabel = snapshot.focusedElementLabel
                state.selectedElementLabels = snapshot.selectedElementLabels
                state.disabledElementLabels = snapshot.disabledElementLabels
                state.modalWindowTitles = snapshot.modalWindowTitles
                useful = true
            } catch {
                sections.append("accessibility_error=\(error.localizedDescription)")
            }
        }

        if includeScreenshot {
            do {
                let capture = try await ScreenCaptureComputerUseService.shared.capture(
                    application: application,
                    preferredWindowFrame: accessibilitySnapshot?.focusedWindowFrame,
                    persist: persistScreenshot,
                    observationID: observationID,
                    performOCR: accessibilitySnapshot?.needsVisualFallback ?? true
                )
                if let path = capture.path {
                    imagePaths.append(path)
                    sections.append("screenshot=\(path)")
                }
                sections.append(capture.coordinateMappingDescription)
                state.screenshotSignature = capture.signature
                state.ocrText = capture.recognizedText
                if accessibilitySnapshot?.needsVisualFallback ?? true {
                    sections.append("ocr_fallback_attempted=true recognized_regions=\(capture.visualTextRegions.count)")
                }
                if !capture.visualTextRegions.isEmpty {
                    sections.append("OCR visual fallback (use visual_handle instead of raw coordinates):")
                    sections.append(contentsOf: capture.visualTextRegions.prefix(120).map { region in
                        let frame = region.globalFrame
                        return "  visual_handle=\(region.handle) text=\(quotedOCR(region.text)) confidence=\(String(format: "%.2f", region.confidence)) frame=[\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))]"
                    })
                }
                useful = true
            } catch {
                sections.append("screenshot_error=\(error.localizedDescription)")
            }
        }

        sections.append(
            "permissions_after_observation accessibility=\(AXIsProcessTrusted()) screen_capture=\(CGPreflightScreenCaptureAccess())"
        )
        return DesktopObservation(
            observationID: observationID,
            text: sections.joined(separator: "\n"),
            imagePaths: imagePaths,
            hasUsefulContent: useful,
            state: state
        )
    }

    private func quotedOCR(_ value: String) -> String {
        "\"\(String(value.replacingOccurrences(of: "\n", with: " ").prefix(240)))\""
    }
}

@MainActor
private final class UIActionVerifier {
    static let shared = UIActionVerifier()

    func captureState(
        application: NSRunningApplication,
        followFocusedApplication: Bool
    ) async -> UIObservationState {
        let observedApplication = followFocusedApplication
            ? DesktopApplicationReliabilityService.shared.interactionApplication(fallback: application)
            : application
        let observation = await DesktopObservationService.shared.observe(
            applicationIdentifier: observedApplication.bundleIdentifier ?? observedApplication.localizedName,
            includeScreenshot: true,
            includeAccessibility: true,
            maxDepth: 8,
            maxNodes: 500,
            persistScreenshot: false,
            storeElements: false
        )
        return observation.state
    }

    func verify(
        before: UIObservationState,
        application: NSRunningApplication,
        expectation: UIActionExpectation,
        timeoutMilliseconds: Int
    ) async -> UIActionVerificationResult {
        let timeout = max(250, min(timeoutMilliseconds, 10_000))
        let startedAt = Date()
        var attempts = 0
        var lastEvaluation = UIActionVerificationEvaluation(
            satisfied: false,
            unmetConditions: ["尚未读取操作后状态"]
        )
        var lastChanged = false
        let beforeEvaluation = expectation.evaluate(state: before, stateChanged: false)
        var observedApplicationIdentifier: String?

        repeat {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(attempts == 1 ? 180 : 260))
            let current = await captureState(application: application, followFocusedApplication: true)
            observedApplicationIdentifier = current.applicationIdentifier
            lastChanged = current.materiallyDiffers(from: before)
            if !current.hasAnySource {
                lastEvaluation = UIActionVerificationEvaluation(
                    satisfied: false,
                    unmetConditions: ["无法读取操作后的 Accessibility 或屏幕状态"]
                )
            } else {
                lastEvaluation = expectation.evaluate(state: current, stateChanged: lastChanged)
                if expectation.hasExplicitCondition,
                   expectation.verifyChange,
                   beforeEvaluation.satisfied,
                   lastEvaluation.satisfied,
                   !lastChanged {
                    lastEvaluation = UIActionVerificationEvaluation(
                        satisfied: false,
                        unmetConditions: ["预期状态在操作前已存在，且操作后界面无变化"]
                    )
                }
            }
            if lastEvaluation.satisfied { break }
        } while Date().timeIntervalSince(startedAt) * 1_000 < Double(timeout)

        return UIActionVerificationResult(
            passed: lastEvaluation.satisfied,
            stateChanged: lastChanged,
            attempts: attempts,
            elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
            unmetConditions: lastEvaluation.unmetConditions,
            observedApplicationIdentifier: observedApplicationIdentifier
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

    func perform(
        arguments: [String: Any],
        application: NSRunningApplication,
        currentState: UIObservationState
    ) async throws -> String {
        guard let action = arguments["action"] as? String else {
            throw ComputerUseError.invalidArguments("缺少 action")
        }
        try AccessibilityComputerUseService.shared.ensureInputPermission()
        application.activate()
        try validateVisualContext(
            action: action,
            arguments: arguments,
            application: application,
            currentState: currentState
        )

        switch action {
        case "press":
            let target = try accessibilityTarget(arguments: arguments, application: application)
            do {
                try AccessibilityComputerUseService.shared.press(target.element)
            } catch {
                guard let frame = target.frame else { throw error }
                await click(point: CGPoint(x: frame.midX, y: frame.midY), button: .left, count: 1)
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
            let point = try targetPoint(
                arguments: arguments,
                application: application,
                currentState: currentState
            )
            let button: CGMouseButton = action == "right_click" ? .right : .left
            await click(point: point, button: button, count: action == "double_click" ? 2 : 1)
            return "已在 (\(Int(point.x)), \(Int(point.y))) 执行 \(action)"
        case "scroll":
            let point: CGPoint?
            if arguments["element_handle"] != nil
                || arguments["label"] != nil
                || arguments["visual_handle"] != nil {
                point = try targetPoint(
                    arguments: arguments,
                    application: application,
                    currentState: currentState
                )
            } else {
                point = optionalPoint(arguments: arguments)
            }
            if let point { movePointer(to: point) }
            let deltaX = intValue(arguments["delta_x"]) ?? 0
            let deltaY = intValue(arguments["delta_y"]) ?? -480
            scroll(deltaX: deltaX, deltaY: deltaY)
            return "已滚动 delta_x=\(deltaX), delta_y=\(deltaY)"
        case "drag":
            let start = try requiredPoint(arguments: arguments, xKey: "x", yKey: "y")
            let end = try requiredPoint(arguments: arguments, xKey: "to_x", yKey: "to_y")
            await drag(from: start, to: end)
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
            await typeText(text)
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
            arguments: arguments
        )
    }

    private func targetPoint(
        arguments: [String: Any],
        application: NSRunningApplication,
        currentState: UIObservationState
    ) throws -> CGPoint {
        if arguments["element_handle"] != nil || arguments["label"] != nil {
            let target = try accessibilityTarget(arguments: arguments, application: application)
            guard let frame = target.frame else {
                throw ComputerUseError.actionFailed("目标元素没有可用的坐标")
            }
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        if let visualHandle = arguments["visual_handle"] as? String {
            return try ScreenCaptureComputerUseService.shared.resolveVisualTarget(
                handle: visualHandle,
                application: application,
                currentSignature: currentState.screenshotSignature
            )
        }
        return try requiredPoint(arguments: arguments, xKey: "x", yKey: "y")
    }

    private func validateVisualContext(
        action: String,
        arguments: [String: Any],
        application: NSRunningApplication,
        currentState: UIObservationState
    ) throws {
        let hasSemanticTarget = arguments["element_handle"] != nil || arguments["label"] != nil
        if arguments["visual_handle"] != nil { return }
        let usesRawCoordinates: Bool
        switch action {
        case "click", "double_click", "right_click":
            usesRawCoordinates = !hasSemanticTarget
        case "drag":
            usesRawCoordinates = true
        case "scroll":
            usesRawCoordinates = arguments["x"] != nil || arguments["y"] != nil
        default:
            usesRawCoordinates = false
        }
        guard usesRawCoordinates else { return }
        try ScreenCaptureComputerUseService.shared.validateCoordinateObservation(
            arguments["coordinate_observation_id"] as? String,
            application: application,
            currentSignature: currentState.screenshotSignature
        )
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

    private func click(point: CGPoint, button: CGMouseButton, count: Int) async {
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
            if index < count { try? await Task.sleep(for: .milliseconds(70)) }
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

    private func drag(from start: CGPoint, to end: CGPoint) async {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        for step in 1...12 {
            let progress = CGFloat(step) / 12
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(10))
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

    private func typeText(_ text: String) async {
        let utf16 = Array(text.utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        for start in stride(from: 0, to: utf16.count, by: 20) {
            let end = min(start + 20, utf16.count)
            let chunk = Array(utf16[start..<end])
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            chunk.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            if end < utf16.count { try? await Task.sleep(for: .milliseconds(8)) }
        }
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
        description: "观察当前 macOS 应用界面，返回稳定窗口/元素句柄、AX 树增量变化、焦点/选中/禁用/弹窗状态与截图。AX 信息稀疏时自动 OCR 并返回 visual_handle。",
        parameters: [
            "type": "object",
            "properties": [
                "application": ["type": "string", "description": "可选的应用名称或 bundle identifier；省略时观察前台应用"],
                "include_screenshot": ["type": "boolean", "description": "是否截图，默认 true"],
                "include_accessibility": ["type": "boolean", "description": "是否读取 Accessibility 元素树，默认 true"],
                "max_depth": ["type": "integer", "description": "Accessibility 树最大深度，默认 8"],
                "max_nodes": ["type": "integer", "description": "Accessibility 树最大节点数，默认 500"]
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
        let maxDepth = (arguments["max_depth"] as? NSNumber)?.intValue ?? 8
        let maxNodes = (arguments["max_nodes"] as? NSNumber)?.intValue ?? 500
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
        description: "对 macOS 应用执行单步界面操作。优先使用稳定 element_handle；同名控件用 scope_handle、window_handle、row_label 或 occurrence 缩小范围。AX 不足时使用 visual_handle。原始坐标必须携带 coordinate_observation_id，界面变化时会拒绝操作并主动重新观察。",
        parameters: [
            "type": "object",
            "properties": [
                "application": ["type": "string", "description": "应用名称或 bundle identifier"],
                "action": ["type": "string", "enum": ["press", "set_value", "click", "double_click", "right_click", "scroll", "drag", "key_press", "type_text"]],
                "element_handle": ["type": "string", "description": "observe_desktop 返回的 AX 元素句柄"],
                "label": ["type": "string", "description": "控件名称；也用于向用户说明高风险操作"],
                "role": ["type": "string", "description": "可选 AX role，用于缩小同名控件范围"],
                "scope_handle": ["type": "string", "description": "只在该窗口、组、表格、列表、行或 Web 容器后代中定位"],
                "scope_label": ["type": "string", "description": "作用域名称；作用域也同名时改用 scope_handle"],
                "window_handle": ["type": "string", "description": "限定目标所属窗口或弹窗"],
                "row_label": ["type": "string", "description": "限定目标所属表格行、树节点或列表项"],
                "occurrence": ["type": "integer", "description": "在已限定作用域内选择第 N 个匹配，从 1 开始"],
                "selected_only": ["type": "boolean", "description": "是否只在当前选中项内匹配"],
                "visual_handle": ["type": "string", "description": "AX 不足时 observe_desktop OCR 返回的视觉文本句柄"],
                "coordinate_observation_id": ["type": "string", "description": "使用原始坐标时必须提供的最近观察 ID"],
                "text": ["type": "string", "description": "set_value 或 type_text 的文本"],
                "x": ["type": "number"], "y": ["type": "number"],
                "to_x": ["type": "number"], "to_y": ["type": "number"],
                "delta_x": ["type": "integer"], "delta_y": ["type": "integer"],
                "key": ["type": "string", "description": "key_press 的按键，例如 return/tab/escape/a"],
                "modifiers": ["type": "array", "items": ["type": "string", "enum": ["command", "shift", "option", "control"]]],
                "expected_text": ["type": "string", "description": "操作后必须出现的可访问文本"],
                "expected_element": ["type": "string", "description": "操作后必须出现的控件名称"],
                "expected_element_absent": ["type": "string", "description": "操作后必须消失的控件名称"],
                "expected_window_title": ["type": "string", "description": "操作后必须出现的窗口标题"],
                "expected_focused_element": ["type": "string", "description": "操作后必须获得焦点的元素"],
                "expected_selected_element": ["type": "string", "description": "操作后必须处于选中状态的行、树节点、列表项或控件"],
                "verify_change": ["type": "boolean", "description": "是否要求操作后界面状态发生变化，默认 true；显式设为 false 才允许预期条件在操作前已经成立"],
                "verification_timeout_ms": ["type": "integer", "description": "操作后等待验证的毫秒数，默认 2500，最大 10000"]
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
        Task { @MainActor in
            var resolvedApplication: NSRunningApplication?
            do {
                let applicationName = arguments["application"] as? String
                let application = try AccessibilityComputerUseService.shared.resolveApplication(applicationName)
                resolvedApplication = application
                try await DesktopApplicationReliabilityService.shared.activateAndWait(application)
                let before = await UIActionVerifier.shared.captureState(
                    application: application,
                    followFocusedApplication: false
                )
                let actionResult = try await NativeInputService.shared.perform(
                    arguments: arguments,
                    application: application,
                    currentState: before
                )
                let expectation = UIActionExpectation(arguments: arguments)
                let timeout = (arguments["verification_timeout_ms"] as? NSNumber)?.intValue ?? 2_500
                let verification = await UIActionVerifier.shared.verify(
                    before: before,
                    application: application,
                    expectation: expectation,
                    timeoutMilliseconds: timeout
                )
                let observation = await DesktopObservationService.shared.observe(
                    applicationIdentifier: verification.observedApplicationIdentifier
                        ?? application.bundleIdentifier
                        ?? application.localizedName,
                    includeScreenshot: true,
                    includeAccessibility: true,
                    maxDepth: 6,
                    maxNodes: 240
                )
                let result = "\(actionResult)\n\n自动验证：\n\(verification.summary)\n\n操作后状态：\n\(observation.text)"
                if verification.passed {
                    completion(.success(result, imagePaths: observation.imagePaths))
                } else {
                    completion(.failure("操作已发出，但自动验证未通过。\n\n\(result)", imagePaths: observation.imagePaths))
                }
            } catch let error as ComputerUseError {
                if case .reobservationRequired = error, let application = resolvedApplication {
                    let refreshed = await DesktopObservationService.shared.observe(
                        applicationIdentifier: application.bundleIdentifier ?? application.localizedName,
                        includeScreenshot: true,
                        includeAccessibility: true,
                        maxDepth: 8,
                        maxNodes: 500
                    )
                    completion(.failure(
                        "\(error.localizedDescription)\n\n最新观察：\n\(refreshed.text)",
                        imagePaths: refreshed.imagePaths
                    ))
                } else {
                    completion(.failure(error.localizedDescription))
                }
            } catch {
                completion(.failure(error.localizedDescription))
            }
        }
    }
}
