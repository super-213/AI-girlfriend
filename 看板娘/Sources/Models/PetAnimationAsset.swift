//
//  PetAnimationAsset.swift
//  看板娘
//

import Foundation

enum PetAssetType: String, Codable, CaseIterable {
    case gif
    case png
    case jpeg

    static func infer(from location: String) -> PetAssetType? {
        switch URL(fileURLWithPath: location).pathExtension.lowercased() {
        case "gif": return .gif
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        default: return nil
        }
    }
}

struct PetAnimationAsset: Codable, Equatable, Identifiable {
    let id: String
    var location: String
    var type: PetAssetType
    var loop: Bool
    var weight: Int
    var preferredDuration: TimeInterval?

    init(
        id: String = UUID().uuidString,
        location: String,
        type: PetAssetType? = nil,
        loop: Bool = true,
        weight: Int = 1,
        preferredDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.location = location
        self.type = type ?? PetAssetType.infer(from: location) ?? .gif
        self.loop = loop
        self.weight = max(weight, 1)
        self.preferredDuration = preferredDuration
    }
}

struct PetDisplayOptions: Codable, Equatable {
    var scale: Double
    var horizontalOffset: Double
    var verticalOffset: Double

    static let `default` = PetDisplayOptions(scale: 1, horizontalOffset: 0, verticalOffset: 0)
}

struct PetCharacter: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 2

    let id: String
    let schemaVersion: Int
    var name: String
    var assetsByState: [PetActivityState: [PetAnimationAsset]]
    var interactionAssets: [PetAnimationAsset]
    var autoMessages: [String]
    var displayOptions: PetDisplayOptions

    init(
        id: String = UUID().uuidString,
        schemaVersion: Int = PetCharacter.currentSchemaVersion,
        name: String,
        assetsByState: [PetActivityState: [PetAnimationAsset]],
        interactionAssets: [PetAnimationAsset] = [],
        autoMessages: [String],
        displayOptions: PetDisplayOptions = .default
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.assetsByState = assetsByState
        self.interactionAssets = interactionAssets
        self.autoMessages = autoMessages
        self.displayOptions = displayOptions
    }

    /// 兼容现有控制接口的只读别名；持久化只使用新结构。
    var normalGif: String {
        assetsByState[.idle]?.first?.location ?? ""
    }

    var clickGif: String {
        interactionAssets.first?.location ?? normalGif
    }
}

struct PetResolvedAsset: Equatable {
    let asset: PetAnimationAsset
    let requestedState: PetActivityState
    let resolvedState: PetActivityState?
    let isInteractionAsset: Bool

    var summary: String {
        let resolved = resolvedState?.rawValue ?? "interaction"
        return "\(requestedState.rawValue)→\(resolved):\(asset.location)"
    }
}
