//
//  SkillsSettingsTab.swift
//  桌面宠物应用
//
//  Agent 和 Skill 文件管理设置页
//

import SwiftUI

struct SkillsSettingsTab: View {
    let agentFile: AgentFile?
    let skillFiles: [SkillFile]
    let onImportAgent: () -> Void
    let onGenerateAgent: () -> Void
    let onRemoveAgent: () -> Void
    let onImportSkills: () -> Void
    let onDeleteSkill: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                agentSection

                Divider()
                    .padding(.vertical, LayoutConstants.fieldSpacing)

                skillsSection
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("技能设置标签")
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("agent.md")
                .font(DesignFonts.headline)

            Text("用于控制模型根据用户输入选择正常输出、调用系统命令或使用 skill。")
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)

            if let agentFile {
                SkillFileRow(
                    title: agentFile.name,
                    subtitle: agentFile.path,
                    onDelete: onRemoveAgent
                )
            } else {
                Text("未添加 agent.md")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSpacing.sm)
            }

            HStack(spacing: DesignSpacing.sm) {
                Button(action: onImportAgent) {
                    Label(agentFile == nil ? "导入 agent.md" : "替换 agent.md", systemImage: "doc.fill.badge.plus")
                }

                Button(action: onGenerateAgent) {
                    Label("生成示例", systemImage: "wand.and.stars")
                }
            }
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack {
                Text("skill.md")
                    .font(DesignFonts.headline)
                Spacer()
                Button(action: onImportSkills) {
                    Label("导入", systemImage: "plus.circle.fill")
                }
            }

            Text("一个或多个 skill 文件，用于扩展模型的能力。")
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)

            if skillFiles.isEmpty {
                Text("暂无 skill.md，点击导入按钮添加")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignSpacing.lg)
            } else {
                ForEach(Array(skillFiles.enumerated()), id: \.element.id) { index, skill in
                    SkillFileRow(
                        title: skill.name,
                        subtitle: skill.path,
                        onDelete: { onDeleteSkill(index) }
                    )
                }
            }
        }
    }
}

private struct SkillFileRow: View {
    let title: String
    let subtitle: String
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignFonts.body)
                Text(subtitle)
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
