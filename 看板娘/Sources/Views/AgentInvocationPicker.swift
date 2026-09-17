//
//  AgentInvocationPicker.swift
//  看板娘
//
//  Shared command palette for explicit /tool and $skill selection.
//

import SwiftUI

struct AgentInvocationPicker: View {
    let kind: AgentInvocationKind
    let options: [AgentInvocationOption]
    @Binding var selectedIndex: Int
    let compact: Bool
    let onSelect: (AgentInvocationOption) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func preferredHeight(optionCount: Int, compact: Bool = false) -> CGFloat {
        if optionCount == 0 { return compact ? 78 : 90 }
        let rowHeight: CGFloat = compact ? 40 : 46
        let chromeHeight: CGFloat = compact ? 40 : 58
        return min(CGFloat(optionCount), compact ? 4 : 6) * rowHeight + chromeHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if options.isEmpty {
                emptyState
            } else {
                optionList
            }

            if !compact && !options.isEmpty {
                HStack(spacing: 10) {
                    Label("选择", systemImage: "return")
                    Text("↑↓ 浏览")
                    Text("esc 关闭")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .frame(height: 25)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("选择\(kind.title)")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: kind == .tool ? "wrench.and.screwdriver" : "puzzlepiece.extension")
                .foregroundStyle(DesignColors.primary)
            Text(kind == .tool ? "显式附加工具" : "显式附加技能")
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
            Spacer(minLength: 0)
            Text(String(kind.prefix))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, compact ? 10 : 12)
        .frame(height: compact ? 32 : 34)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            Text(kind == .skill ? "没有匹配的已启用技能" : "没有匹配的工具")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: compact ? 11 : 12))
        .padding(.horizontal, compact ? 10 : 12)
        .frame(maxHeight: .infinity)
    }

    private var optionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionRow(option, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
            .onChange(of: selectedIndex) { _, index in
                guard options.indices.contains(index) else { return }
                if reduceMotion {
                    proxy.scrollTo(index, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func optionRow(_ option: AgentInvocationOption, index: Int) -> some View {
        let isSelected = index == selectedIndex

        return Button {
            selectedIndex = index
            onSelect(option)
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: option.kind == .tool ? "wrench" : "puzzlepiece.extension.fill")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(isSelected ? DesignColors.primary : Color.secondary)
                    .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                    .background(Color.primary.opacity(isSelected ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.token)
                        .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !compact || option.description.count < 70 {
                        Text(option.description)
                            .font(.system(size: compact ? 9.5 : 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, compact ? 7 : 8)
            .frame(height: compact ? 38 : 44)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? DesignColors.primary.opacity(0.11) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selectedIndex = index }
        }
        .accessibilityLabel(option.token)
        .accessibilityHint(option.description)
    }
}
