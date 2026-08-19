//
//  LayoutComponents.swift
//  桌面宠物应用
//
//  布局设置相关的UI组件
//

import AppKit
import SwiftUI

private struct CharacterLayoutWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 84

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 当前桌宠界面的等比、实时布局预览。
struct OverlapPreview: View {
    @Binding var overlapRatio: Double
    @Binding var horizontalPosition: Double
    @Binding var contentScale: Double
    let character: PetCharacter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var characterLayoutWidth: CGFloat = 190
    @State private var previousDragTranslation: CGSize?
    @State private var magnificationOrigin: Double?
    @State private var isCharacterHovered = false
    @State private var isDraggingCharacter = false

    private var percentage: Int {
        Int((overlapRatio * 100).rounded())
    }

    private var horizontalPercentage: Int {
        PetHorizontalPosition.percentage(for: horizontalPosition)
    }

    private var sizePercentage: Int {
        Int((contentScale * 100).rounded())
    }

    private var isDefaultLayout: Bool {
        abs(overlapRatio - 0.3) < 0.001
            && abs(horizontalPosition - PetHorizontalPosition.defaultValue) < 0.001
            && abs(contentScale - 1) < 0.001
    }

    var body: some View {
        VStack(spacing: 0) {
            previewHeader

            Divider()
                .opacity(0.55)

            GeometryReader { proxy in
                previewScene(size: proxy.size)
            }

            Divider()
                .opacity(0.45)

            previewToolbar
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 16, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("可交互布局预览")
    }

    private var previewHeader: some View {
        HStack(spacing: DesignSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.13))
                    .frame(width: 24, height: 24)
                Image(systemName: "move.3d")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("直接调整")
                    .font(.system(size: 12, weight: .semibold))
                Text("拖动角色改变位置")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            previewValueBadge(
                title: "横向",
                value: horizontalPercentage,
                systemImage: "arrow.left.and.right"
            )

            previewValueBadge(
                title: "纵向",
                value: percentage,
                systemImage: "arrow.up.and.down"
            )

            Button(action: restoreDefaultLayout) {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(isDefaultLayout)
            .help("恢复默认布局")
            .accessibilityLabel("恢复默认布局")
        }
        .padding(.horizontal, DesignSpacing.lg)
        .frame(height: 52)
    }

    private func previewValueBadge(title: String, value: Int, systemImage: String) -> some View {
        Label {
            Text("\(title) \(value)%")
                .monospacedDigit()
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .lineLimit(1)
    }

    private func previewScene(size: CGSize) -> some View {
        let stageWidth = min(
            PetLayoutPreviewGeometry.defaultPanelWidth,
            max(size.width - 48, 1)
        )
        let geometry = PetLayoutPreviewGeometry(
            contentScale: CGFloat(contentScale),
            panelWidth: stageWidth
        )
        let horizontalTravel = max(stageWidth - characterLayoutWidth, 1)
        let overlapSpacing = PetLayoutMetrics.live
            .scaled(by: geometry.normalizationScale)
            .petStackSpacing(for: overlapRatio)

        return ZStack(alignment: .top) {
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
                .offset(x: -size.width * 0.33, y: 54)

            Capsule()
                .fill(.primary.opacity(0.08))
                .frame(width: min(size.width * 0.68, 380), height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)

            VStack(spacing: overlapSpacing) {
                VStack(spacing: geometry.scaledPanelMetric(PetPanelLayoutMetrics.spacing)) {
                    speechBubble(scale: geometry.normalizationScale)
                    inputCapsule(scale: geometry.normalizationScale)
                }
                .zIndex(2)

                PetHorizontalPositionLayout(position: horizontalPosition) {
                    interactiveCharacter(
                        horizontalTravel: horizontalTravel,
                        geometry: geometry
                    )
                }
                .frame(maxWidth: .infinity)
                .zIndex(1)
            }
            .frame(width: stageWidth)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .coordinateSpace(.named("layoutPreviewScene"))
        .clipped()
    }

    private var previewToolbar: some View {
        HStack(spacing: DesignSpacing.md) {
            Label("拖动定位 · 双指捏合缩放", systemImage: "hand.draw")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: DesignSpacing.sm)

            HStack(spacing: 2) {
                Button { adjustSize(by: -0.05) } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                }
                .disabled(contentScale <= minimumScale + 0.001)
                .accessibilityLabel("缩小桌宠")

                Text("\(sizePercentage)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                    .accessibilityLabel("桌宠大小 \(sizePercentage)%")

                Button { adjustSize(by: 0.05) } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .disabled(contentScale >= maximumScale - 0.001)
                .accessibilityLabel("放大桌宠")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, DesignSpacing.lg)
        .frame(height: 48)
    }

    private func speechBubble(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            HStack(spacing: 8 * scale) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("回答中")
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Image(systemName: "xmark")
            }
            .font(.system(size: 11 * scale, weight: .medium))

            Text("指挥官，你好。布局变化会在这里即时呈现。")
                .font(.system(size: 13 * scale))
                .lineSpacing(3 * scale)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13 * scale)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.23), lineWidth: max(scale, 0.5))
        }
        .shadow(color: .black.opacity(0.1), radius: 16 * scale, y: 7 * scale)
    }

    private func inputCapsule(scale: CGFloat) -> some View {
        HStack(spacing: 9 * scale) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text("问问 \(character.name)…")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 13 * scale))
        .padding(.horizontal, 13 * scale)
        .frame(height: PetPanelLayoutMetrics.inputHeight * scale)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: max(0.8 * scale, 0.5)))
        .shadow(color: .black.opacity(0.09), radius: 12 * scale, y: 5 * scale)
    }

    private var minimumScale: Double {
        Double(PetWindowSizing.minimumContentScale)
    }

    private var maximumScale: Double {
        Double(PetWindowSizing.maximumContentScale)
    }

    private func interactiveCharacter(
        horizontalTravel: CGFloat,
        geometry: PetLayoutPreviewGeometry
    ) -> some View {
        characterArtwork(geometry: geometry)
            .contentShape(Rectangle())
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CharacterLayoutWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
            .onPreferenceChange(CharacterLayoutWidthKey.self) { width in
                characterLayoutWidth = width
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(
                            isDraggingCharacter ? 0.8 : (isCharacterHovered ? 0.35 : 0)
                        ),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .padding(-5)
                    .allowsHitTesting(false)
            }
            .scaleEffect(isDraggingCharacter ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 1),
                value: isDraggingCharacter
            )
            .onHover { hovering in
                isCharacterHovered = hovering
            }
            .gesture(
                layoutDragGesture(
                    horizontalTravel: horizontalTravel,
                    overlapTravel: PetLayoutMetrics.live.overlapTravel
                        * geometry.normalizationScale
                )
            )
            .simultaneousGesture(magnificationGesture)
            .help("拖动调整横向和纵向位置，双指捏合调整大小")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("桌宠位置")
            .accessibilityValue("横向 \(horizontalPercentage)%，纵向 \(percentage)%，大小 \(sizePercentage)%")
            .accessibilityHint("拖动调整位置，双指捏合调整大小")
    }

    private func layoutDragGesture(
        horizontalTravel: CGFloat,
        overlapTravel: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("layoutPreviewScene"))
            .onChanged { value in
                let previousDragTranslation = previousDragTranslation ?? .zero
                if self.previousDragTranslation == nil {
                    isDraggingCharacter = true
                }

                let deltaWidth = value.translation.width - previousDragTranslation.width
                let deltaHeight = value.translation.height - previousDragTranslation.height
                self.previousDragTranslation = value.translation

                horizontalPosition = PetHorizontalPosition.clamped(
                    horizontalPosition + Double(deltaWidth / horizontalTravel)
                )

                overlapRatio = clampedOverlap(
                    overlapRatio - Double(deltaHeight / max(overlapTravel, 1))
                )
            }
            .onEnded { _ in
                previousDragTranslation = nil
                isDraggingCharacter = false
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                if magnificationOrigin == nil {
                    magnificationOrigin = contentScale
                }
                guard let magnificationOrigin else { return }
                contentScale = clampedScale(
                    magnificationOrigin * Double(value.magnification)
                )
            }
            .onEnded { _ in
                magnificationOrigin = nil
            }
    }

    private func adjustSize(by delta: Double) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
            contentScale = clampedScale(contentScale + delta)
        }
    }

    private func restoreDefaultLayout() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)) {
            overlapRatio = 0.3
            horizontalPosition = PetHorizontalPosition.defaultValue
            contentScale = 1
        }
    }

    private func clampedOverlap(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func clampedScale(_ value: Double) -> Double {
        min(max(value, minimumScale), maximumScale)
    }

    @ViewBuilder
    private func characterArtwork(geometry: PetLayoutPreviewGeometry) -> some View {
        let artworkScale = CGFloat(contentScale) * geometry.normalizationScale

        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(character.displayOptions.scale)
                .offset(
                    x: character.displayOptions.horizontalOffset * artworkScale,
                    y: character.displayOptions.verticalOffset * artworkScale
                )
                .frame(height: geometry.characterHeight)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 5)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: geometry.characterHeight * 4 / 7, weight: .light))
                .foregroundStyle(.secondary.opacity(0.65))
                .frame(height: geometry.characterHeight)
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
