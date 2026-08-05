//
//  CharacterComponents.swift
//  看板娘
//
//  角色库、详情预览与导入工作表。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CharacterLibraryRow: View {
    let character: PetCharacter
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSpacing.sm) {
                CharacterThumbnail(character: character, size: 38, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(isCurrent ? "当前角色" : characterAssetSummary(character))
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? Color.green : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(character.name)
        .accessibilityValue(isCurrent ? "当前角色" : "可绑定")
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: isSelected)
    }
}

struct CharacterDetailPane: View {
    let character: PetCharacter
    let isCustom: Bool
    let isCurrent: Bool
    let statusMessage: String?
    let onBind: () -> Void
    let onConfigure: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.xl) {
                preview
                identity
                metrics

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, DesignSpacing.sm)
                        .background(Color.green.opacity(0.09), in: Capsule())
                        .transition(.opacity)
                }

                bindingAction

                if isCustom {
                    Divider()
                        .padding(.horizontal, DesignSpacing.xxl)
                    customActions
                }
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignSpacing.xxl)
            .padding(.vertical, 28)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: isCurrent)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: statusMessage)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)

            CharacterThumbnail(character: character, size: 176, cornerRadius: 20, showsBackground: false)
                .padding(DesignSpacing.lg)
        }
        .frame(width: 220, height: 220)
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                Label("当前", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green, in: Capsule())
                    .padding(DesignSpacing.md)
            }
        }
    }

    private var identity: some View {
        VStack(spacing: DesignSpacing.xs) {
            Text(character.name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Label(isCustom ? "自定义角色" : "内置角色", systemImage: isCustom ? "person.crop.circle.badge.plus" : "shippingbox.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            CharacterMetric(value: "\(configuredStateCount)", label: "已配置状态")
            Divider().frame(height: 30)
            CharacterMetric(value: "\(totalAssetCount)", label: "状态素材")
            Divider().frame(height: 30)
            CharacterMetric(value: character.interactionAssets.isEmpty ? "无" : "有", label: "互动素材")
        }
        .padding(.vertical, DesignSpacing.md)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    @ViewBuilder
    private var bindingAction: some View {
        if isCurrent {
            Label("正在使用", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: 260)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityLabel("正在使用的角色")
        } else {
            Button(action: onBind) {
                Label("设为当前角色", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .help("将桌面角色切换为 \(character.name)")
        }
    }

    private var customActions: some View {
        HStack(spacing: DesignSpacing.md) {
            if let onConfigure {
                Button(action: onConfigure) {
                    Label("编辑状态素材", systemImage: "photo.on.rectangle.angled")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("删除角色", systemImage: "trash")
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var configuredStateCount: Int {
        character.assetsByState.values.filter { !$0.isEmpty }.count
    }

    private var totalAssetCount: Int {
        character.assetsByState.values.reduce(0) { $0 + $1.count }
    }
}

struct CharacterImportSheet: View {
    let onImport: (URL?, URL?, String) -> Bool
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var characterName = ""
    @State private var idleAssetURL: URL?
    @State private var interactionAssetURL: URL?
    @State private var confirmsUsageRights = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DesignSpacing.md) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)

                Text("导入新角色")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(DesignSpacing.xl)

            Divider()

            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("角色名称")
                        .font(.headline)
                    TextField("例如：小狐狸", text: $characterName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                }

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("角色素材")
                        .font(.headline)
                    CharacterImportAssetRow(
                        title: "待命素材",
                        detail: "必选 · GIF、PNG 或 JPEG",
                        systemImage: "figure.stand",
                        url: idleAssetURL,
                        onChoose: { chooseAsset(title: "选择角色待命素材") { idleAssetURL = $0 } },
                        onRemove: { idleAssetURL = nil }
                    )
                    CharacterImportAssetRow(
                        title: "互动素材",
                        detail: "可选 · 点击角色时播放",
                        systemImage: "hand.tap",
                        url: interactionAssetURL,
                        onChoose: { chooseAsset(title: "选择角色互动素材") { interactionAssetURL = $0 } },
                        onRemove: { interactionAssetURL = nil }
                    )
                }

                Toggle(isOn: $confirmsUsageRights) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("我确认拥有这些素材的使用权")
                        Text("导入的文件将复制到应用的支持目录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(DesignSpacing.xl)

            Divider()

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("导入角色", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(DesignSpacing.lg)
            .background(.bar)
        }
        .frame(width: 520)
        .onAppear { isNameFocused = true }
        .interactiveDismissDisabled(hasEnteredContent)
    }

    private var trimmedName: String {
        characterName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && idleAssetURL != nil && confirmsUsageRights
    }

    private var hasEnteredContent: Bool {
        !trimmedName.isEmpty || idleAssetURL != nil || interactionAssetURL != nil
    }

    private func submit() {
        guard canSubmit else { return }
        if onImport(idleAssetURL, interactionAssetURL, trimmedName) {
            onComplete(trimmedName)
        }
    }

    private func chooseAsset(title: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = "支持 GIF、PNG 与 JPEG 文件"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.gif, .png, .jpeg]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}

private struct CharacterImportAssetRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let url: URL?
    let onChoose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            Group {
                if let url, let image = characterPreviewImage(location: url.path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(url?.lastPathComponent ?? detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if url != nil {
                Button("移除", action: onRemove)
                    .buttonStyle(.borderless)
            }
            Button(url == nil ? "选择…" : "更换…", action: onChoose)
        }
        .padding(DesignSpacing.md)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct CharacterMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct CharacterThumbnail: View {
    let character: PetCharacter
    let size: CGFloat
    let cornerRadius: CGFloat
    var showsBackground = true

    var body: some View {
        Group {
            if let image = characterPreviewImage(location: character.normalGif) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

private func characterPreviewImage(location: String) -> NSImage? {
    if location.hasPrefix("/") {
        return NSImage(contentsOfFile: location)
    }
    if let url = Bundle.main.url(forResource: location, withExtension: nil) {
        return NSImage(contentsOf: url)
    }
    return NSImage(named: location)
}

private func characterAssetSummary(_ character: PetCharacter) -> String {
    let stateCount = character.assetsByState.values.filter { !$0.isEmpty }.count
    let assetCount = character.assetsByState.values.reduce(0) { $0 + $1.count }
    return "\(stateCount) 个状态 · \(assetCount) 份素材"
}
