//
//  LayoutComponents.swift
//  桌面宠物应用
//
//  布局设置相关的UI组件
//

import AppKit
import SwiftUI

/// 重叠比例滑块控制
struct OverlapSliderControl: View {
    @Binding var overlapRatio: Double

    private var percentage: Int {
        Int((overlapRatio * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("界面重叠")
                        .font(.system(size: 13, weight: .medium))
                    Text("调整角色进入对话区域的程度")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(percentage)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .contentTransition(.numericText())
            }

            Slider(value: $overlapRatio, in: 0...1, step: 0.01)
                .accessibilityLabel("界面重叠比例")
                .accessibilityValue("\(percentage)%")

            HStack {
                Text("分离")
                Spacer()
                Text("紧凑")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
    }
}

/// 角色水平位置无级滑块控制。
struct HorizontalPositionSliderControl: View {
    @Binding var horizontalPosition: Double

    private var percentage: Int {
        PetHorizontalPosition.percentage(for: horizontalPosition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("角色水平位置")
                        .font(.system(size: 13, weight: .medium))
                    Text("连续调整角色在对话界面下方的位置")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(percentage)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .contentTransition(.numericText())
            }

            Slider(value: $horizontalPosition, in: PetHorizontalPosition.range)
                .accessibilityLabel("角色水平位置")
                .accessibilityValue("距左侧 \(percentage)%")

            HStack {
                Text("左侧")
                Spacer()
                Text("居中")
                Spacer()
                Text("右侧")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
    }
}

/// 当前桌宠界面的等比、实时布局预览。
struct OverlapPreview: View {
    let overlapRatio: Double
    let horizontalPosition: Double
    let character: PetCharacter

    private let layoutMetrics = PetLayoutMetrics.live.scaled(by: 0.95)

    private var percentage: Int {
        Int((overlapRatio * 100).rounded())
    }

    private var horizontalPercentage: Int {
        PetHorizontalPosition.percentage(for: horizontalPosition)
    }

    private var overlapSpacing: CGFloat {
        layoutMetrics.petStackSpacing(for: overlapRatio)
    }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader

            Divider()
                .opacity(0.55)

            GeometryReader { proxy in
                previewScene(width: proxy.size.width)
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("实时布局预览，角色距左侧 \(horizontalPercentage)%，界面重叠 \(percentage)%")
    }

    private var previewHeader: some View {
        HStack(spacing: DesignSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("实时预览")
                    .font(.system(size: 12, weight: .semibold))
                Text(character.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Label("水平 \(horizontalPercentage)%", systemImage: "arrow.left.and.right")
                .lineLimit(1)
                .monospacedDigit()

            Text("·")
                .foregroundStyle(.tertiary)

            Text("重叠 \(percentage)%")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignSpacing.lg)
        .frame(height: 46)
    }

    private func previewScene(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.075),
                    Color.cyan.opacity(0.045),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.055))
                .frame(width: 170, height: 170)
                .blur(radius: 1)
                .offset(x: -width * 0.33, y: 54)

            Capsule()
                .fill(.primary.opacity(0.08))
                .frame(width: min(width * 0.68, 380), height: 2)
                .padding(.bottom, 11)

            VStack(spacing: overlapSpacing) {
                VStack(spacing: 6) {
                    speechBubble
                    inputCapsule
                }
                .zIndex(2)

                PetHorizontalPositionLayout(position: horizontalPosition) {
                    characterArtwork
                }
                .frame(maxWidth: .infinity)
                .zIndex(1)
            }
            .frame(width: min(max(width * 0.54, 230), 320))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .clipped()
    }

    private var speechBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("回答中")
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Image(systemName: "xmark")
            }
            .font(.system(size: 8.5, weight: .medium))

            Text("指挥官，你好。布局变化会在这里即时呈现。")
                .font(.system(size: 9.5))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.23), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    private var inputCapsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text("问问 \(character.name)…")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 9.5))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.09), radius: 7, y: 3)
    }

    @ViewBuilder
    private var characterArtwork: some View {
        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(character.displayOptions.scale)
                .offset(
                    x: character.displayOptions.horizontalOffset * 0.45,
                    y: character.displayOptions.verticalOffset * 0.45
                )
                .frame(height: 112)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 5)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.secondary.opacity(0.65))
                .frame(height: 112)
                .accessibilityHidden(true)
        }
    }

    private var previewImage: NSImage? {
        let location = character.normalGif
        if location.hasPrefix("/") {
            return NSImage(contentsOfFile: location)
        }
        guard let url = Bundle.main.url(forResource: location, withExtension: nil) else {
            return NSImage(named: location)
        }
        return NSImage(contentsOf: url)
    }
}
