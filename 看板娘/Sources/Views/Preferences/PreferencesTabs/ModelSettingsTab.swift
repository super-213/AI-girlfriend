//
//  ModelSettingsTab.swift
//  看板娘
//
//  多模型配置库：左侧选择配置，右侧编辑详情。
//

import SwiftUI

struct ModelSettingsTab: View {
    @Binding var configurations: [ModelConfiguration]
    @Binding var selectedConfigurationID: String
    @Binding var activeConfigurationID: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding

    let onSave: () -> Void
    let onCancel: () -> Void
    let hasUnsavedChanges: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var configurationPendingDeletion: ModelConfiguration?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                configurationSidebar
                    .frame(minWidth: 190, idealWidth: 210, maxWidth: 230)

                Divider()

                editorArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            EnhancedActionButtons(
                onSave: onSave,
                onCancel: onCancel,
                isSaveDisabled: configurations.contains(where: { !$0.isValid }),
                hasUnsavedChanges: hasUnsavedChanges
            )
            .padding(.horizontal, DesignSpacing.xl)
            .padding(.vertical, DesignSpacing.md)
            .background(.bar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("模型设置")
        .confirmationDialog(
            "删除“\(configurationPendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { configurationPendingDeletion != nil },
                set: { if !$0 { configurationPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除配置", role: .destructive) {
                if let configurationPendingDeletion {
                    delete(configurationPendingDeletion)
                }
                configurationPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                configurationPendingDeletion = nil
            }
        } message: {
            Text("该操作会在保存设置后生效。")
        }
    }

    private var configurationSidebar: some View {
        VStack(spacing: DesignSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("模型配置")
                        .font(.headline)
                    Text("\(configurations.count) 个已保存连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: DesignSpacing.sm)

                addConfigurationMenu(labelStyle: .iconOnly)
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.top, DesignSpacing.lg)

            ScrollView {
                LazyVStack(spacing: DesignSpacing.xs) {
                    ForEach(configurations) { configuration in
                        configurationRow(configuration)
                    }
                }
                .padding(.horizontal, DesignSpacing.sm)
                .padding(.bottom, DesignSpacing.sm)
            }

            addConfigurationMenu(labelStyle: .titleAndIcon)
                .padding(.horizontal, DesignSpacing.md)
                .padding(.bottom, DesignSpacing.md)
        }
        .background {
            if reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private enum AddLabelStyle {
        case iconOnly
        case titleAndIcon
    }

    @ViewBuilder
    private func addConfigurationMenu(labelStyle: AddLabelStyle) -> some View {
        Menu {
            ForEach(ModelProvider.allCases) { provider in
                Button {
                    addConfiguration(for: provider)
                } label: {
                    Label(provider.displayName, systemImage: provider.systemImage)
                }
            }
        } label: {
            switch labelStyle {
            case .iconOnly:
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            case .titleAndIcon:
                Label("添加配置", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
        }
        .menuStyle(.borderlessButton)
        .help("添加一个独立的模型服务配置")
        .accessibilityLabel("添加模型配置")
    }

    private func configurationRow(_ configuration: ModelConfiguration) -> some View {
        let isSelected = selectedConfigurationID == configuration.id
        let isActive = activeConfigurationID == configuration.id

        return Button {
            selectedConfigurationID = configuration.id
        } label: {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: configuration.providerKind.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name.isEmpty ? "未命名配置" : configuration.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if isActive {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("正在使用")
                        } else {
                            Text(configuration.aiModel.isEmpty ? configuration.providerKind.shortName : configuration.aiModel)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !configuration.isValid {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .help("该配置尚未填写完整")
                }
            }
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("制作副本", systemImage: "plus.square.on.square") {
                duplicate(configuration)
            }
            if configurations.count > 1 {
                Divider()
                Button("删除", systemImage: "trash", role: .destructive) {
                    configurationPendingDeletion = configuration
                }
            }
        }
        .accessibilityLabel(configuration.name)
        .accessibilityValue(isActive ? "正在使用" : configuration.aiModel)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
            value: isSelected
        )
    }

    @ViewBuilder
    private var editorArea: some View {
        if let configuration = selectedConfigurationBinding {
            ModelConfigurationEditor(
                configuration: configuration,
                isActive: configuration.wrappedValue.id == activeConfigurationID,
                canDelete: configurations.count > 1,
                focusedField: focusedField,
                onProviderChange: { provider in
                    changeProvider(of: configuration, to: provider)
                },
                onActivate: {
                    activeConfigurationID = configuration.wrappedValue.id
                },
                onDuplicate: {
                    duplicate(configuration.wrappedValue)
                },
                onDelete: {
                    configurationPendingDeletion = configuration.wrappedValue
                }
            )
            .id(configuration.wrappedValue.id)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .animation(
                reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.35, dampingFraction: 1),
                value: selectedConfigurationID
            )
        } else {
            ContentUnavailableView(
                "选择一个模型配置",
                systemImage: "network",
                description: Text("从左侧选择配置，或添加新的服务连接。")
            )
        }
    }

    private var selectedConfigurationBinding: Binding<ModelConfiguration>? {
        guard let index = configurations.firstIndex(where: { $0.id == selectedConfigurationID }) else {
            return nil
        }
        return $configurations[index]
    }

    private func addConfiguration(for provider: ModelProvider) {
        var configuration = ModelConfiguration.preset(for: provider)
        configuration.name = uniqueName(for: configuration.name)
        configurations.append(configuration)
        selectedConfigurationID = configuration.id
    }

    private func duplicate(_ source: ModelConfiguration) {
        var copy = source
        copy.id = UUID().uuidString
        copy.name = uniqueName(for: "\(source.name) 副本")
        configurations.append(copy)
        selectedConfigurationID = copy.id
    }

    private func delete(_ configuration: ModelConfiguration) {
        guard configurations.count > 1,
              let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }

        configurations.remove(at: index)
        let replacement = configurations[min(index, configurations.count - 1)]
        selectedConfigurationID = replacement.id
        if activeConfigurationID == configuration.id {
            activeConfigurationID = replacement.id
        }
    }

    private func uniqueName(for proposedName: String) -> String {
        let existingNames = Set(configurations.map(\.name))
        guard existingNames.contains(proposedName) else { return proposedName }

        var suffix = 2
        while existingNames.contains("\(proposedName) \(suffix)") {
            suffix += 1
        }
        return "\(proposedName) \(suffix)"
    }

    private func changeProvider(
        of configuration: Binding<ModelConfiguration>,
        to newProvider: ModelProvider
    ) {
        let oldProvider = configuration.wrappedValue.providerKind
        guard oldProvider != newProvider else { return }

        let oldPreset = ModelConfiguration.preset(for: oldProvider)
        let newPreset = ModelConfiguration.preset(for: newProvider)
        var updated = configuration.wrappedValue
        updated.providerKind = newProvider

        if updated.aiModel.isEmpty || updated.aiModel == oldPreset.aiModel {
            updated.aiModel = newPreset.aiModel
        }
        if updated.apiUrl.isEmpty || updated.apiUrl == oldPreset.apiUrl {
            updated.apiUrl = newPreset.apiUrl
        }
        if updated.apiKey.isEmpty || updated.apiKey == oldPreset.apiKey {
            updated.apiKey = newPreset.apiKey
        }

        configuration.wrappedValue = updated
    }
}

private struct ModelConfigurationEditor: View {
    @Binding var configuration: ModelConfiguration
    let isActive: Bool
    let canDelete: Bool
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    let onProviderChange: (ModelProvider) -> Void
    let onActivate: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var revealsAPIKey = false
    @State private var showsProviderHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                header

                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    labeledField("配置名称") {
                        TextField("如：通义千问云端", text: $configuration.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        HStack(spacing: DesignSpacing.xs) {
                            Text("服务类型")
                                .font(.subheadline.weight(.semibold))

                            Button {
                                showsProviderHelp.toggle()
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("查看服务连接说明")
                            .accessibilityLabel("查看服务连接说明")
                            .popover(isPresented: $showsProviderHelp, arrowEdge: .top) {
                                providerHelp
                            }
                        }

                        Picker("服务类型", selection: providerBinding) {
                            ForEach(ModelProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .focused(focusedField, equals: .provider)
                    }

                    labeledField("模型") {
                        TextField(modelPlaceholder, text: $configuration.aiModel)
                            .textFieldStyle(.roundedBorder)
                            .focused(focusedField, equals: .model)
                    }

                    labeledField("API 地址") {
                        TextField(urlPlaceholder, text: $configuration.apiUrl)
                            .textFieldStyle(.roundedBorder)
                            .focused(focusedField, equals: .apiUrl)
                    }

                    apiKeyField
                    if !configuration.isValid {
                        Label("请填写配置名称、模型和有效的 HTTP(S) API 地址。", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("配置不完整")
                    }
                }
                .padding(DesignSpacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(DesignSpacing.xl)
            .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSpacing.md) {
            Image(systemName: configuration.providerKind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))

            HStack(spacing: DesignSpacing.sm) {
                Text(configuration.name.isEmpty ? "未命名配置" : configuration.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if isActive {
                    Text("正在使用")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.11)))
                }
            }

            Spacer()

            if !isActive {
                Button("设为当前") {
                    onActivate()
                }
                .buttonStyle(.borderedProminent)
                .help("保存后将使用该配置发起对话")
            }

            Menu {
                Button("制作副本", systemImage: "plus.square.on.square", action: onDuplicate)
                if canDelete {
                    Divider()
                    Button("删除配置", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("配置操作")
        }
    }

    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    @ViewBuilder
    private var apiKeyField: some View {
        if configuration.providerKind != .ollama {
            labeledField("API Key") {
                HStack(spacing: DesignSpacing.sm) {
                    Group {
                        if revealsAPIKey {
                            TextField("API Key", text: $configuration.apiKey)
                        } else {
                            SecureField("API Key", text: $configuration.apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedField, equals: .apiKey)
                    .help("本地服务不校验密钥时可以留空")

                    Button {
                        revealsAPIKey.toggle()
                    } label: {
                        Image(systemName: revealsAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealsAPIKey ? "隐藏 API Key" : "显示 API Key")
                }
            }
        }
    }

    private var providerHelp: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Label(configuration.providerKind.displayName, systemImage: configuration.providerKind.systemImage)
                .font(.headline)
            Text(providerHelpText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSpacing.lg)
        .frame(width: 300, alignment: .leading)
    }

    private var providerBinding: Binding<ModelProvider> {
        Binding(
            get: { configuration.providerKind },
            set: { newProvider in
                onProviderChange(newProvider)
            }
        )
    }

    private var modelPlaceholder: String {
        switch configuration.providerKind {
        case .zhipu: return "glm-4v-flash"
        case .openAICompatible: return "qwen-plus 或本地模型 ID"
        case .ollama: return "qwen2.5 或 llama3"
        }
    }

    private var urlPlaceholder: String {
        switch configuration.providerKind {
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .openAICompatible: return "http://localhost:1234/v1/chat/completions"
        case .ollama: return "http://localhost:11434/api/chat"
        }
    }

    private var providerHelpText: String {
        switch configuration.providerKind {
        case .zhipu:
            return "使用智谱 Chat Completions 流式接口。"
        case .openAICompatible:
            return "每个兼容服务都可保存为独立配置。支持 DashScope、LM Studio、vLLM 和 LocalAI 等 /v1/chat/completions 接口。"
        case .ollama:
            return "请先启动 Ollama 并下载对应模型，默认连接本机 11434 端口。"
        }
    }
}
