//
//  CharacterStateAssetsEditor.swift
//  看板娘
//

import AppKit
import SwiftUI

struct CharacterStateAssetsEditor: View {
    let character: PetCharacter
    let onAdd: (PetActivityState) -> Void
    let onRemove: (PetActivityState, String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(character.name).font(.title2.weight(.semibold))
                    Text("每个状态可配置多份素材，进入状态后每 60 秒轮换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(PetActivityState.allCases) { state in
                        stateRow(state)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 620, height: 560)
    }

    private func stateRow(_ state: PetActivityState) -> some View {
        let assets = character.assetsByState[state] ?? []
        return HStack(alignment: .top, spacing: 14) {
            Label(state.displayName, systemImage: state.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 128, alignment: .leading)

            if assets.isEmpty {
                Text("使用回退素材")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(assets) { asset in
                            VStack(spacing: 4) {
                                CharacterAssetThumbnail(asset: asset)
                                Text(URL(fileURLWithPath: asset.location).lastPathComponent)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .frame(width: 76)
                                if !(state == .idle && assets.count == 1) {
                                    Button("移除") { onRemove(state, asset.id) }
                                        .font(.caption2)
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { onAdd(state) } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .help("添加素材")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct CharacterAssetThumbnail: View {
    let asset: PetAnimationAsset

    var body: some View {
        Group {
            if let image = NSImage(contentsOfFile: asset.location) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
