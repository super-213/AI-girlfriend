//
//  PetQuickMenuView.swift
//  看板娘
//

import AppKit
import SwiftUI

struct PetQuickMenuView: View {
    @ObservedObject var backend: PetViewBackend
    @AppStorage("petMuted") private var isMuted = false
    let onDismiss: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            item("对话", "bubble.left.and.bubble.right.fill") { AppWindowRouter.shared.showDialog() }
            item("设置", "gearshape.fill") { AppWindowRouter.shared.showPreferences() }
            item("换角色", "arrow.triangle.2.circlepath") { backend.cycleCharacter() }
            item("自动化", "clock.arrow.circlepath") { AppWindowRouter.shared.showPreferences(section: .automation) }
            item("触发器", "bolt.badge.clock.fill") { AppWindowRouter.shared.showPreferences(section: .triggers) }
            item(isMuted ? "取消静音" : "静音", isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill") { isMuted.toggle() }
            item("收起", "chevron.down") { onDismiss() }
            item("退出", "power", tint: .red) { NSApp.terminate(nil) }
        }
        .padding(10)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
        .petInteractiveRegion()
    }

    private func item(_ title: String, _ icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button {
            action()
            if title != "收起" { onDismiss() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
