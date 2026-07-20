//
//  PetAssetResolver.swift
//  看板娘
//

import Foundation

struct PetAssetResolver {
    static let rotationInterval: TimeInterval = 60

    func resolve(
        character: PetCharacter,
        state: PetActivityState,
        transientEffect: PetTransientEffect? = nil,
        at date: Date = Date()
    ) -> PetResolvedAsset? {
        if transientEffect == .clicked || transientEffect == .greet,
           let asset = choose(character.interactionAssets, at: date) {
            return PetResolvedAsset(
                asset: asset,
                requestedState: state,
                resolvedState: nil,
                isInteractionAsset: true
            )
        }

        for fallbackState in fallbackChain(for: state) {
            if let asset = choose(character.assetsByState[fallbackState] ?? [], at: date) {
                return PetResolvedAsset(
                    asset: asset,
                    requestedState: state,
                    resolvedState: fallbackState,
                    isInteractionAsset: false
                )
            }
        }
        return nil
    }

    func fallbackChain(for state: PetActivityState) -> [PetActivityState] {
        switch state {
        case .waitingForConfirmation:
            return [.waitingForConfirmation, .thinking, .idle]
        case .working:
            return [.working, .thinking, .idle]
        case .talking:
            return [.talking, .thinking, .idle]
        case .success:
            return [.success, .idle]
        case .error:
            return [.error, .waitingForConfirmation, .idle]
        case .sleeping:
            return [.sleeping, .idle]
        case .needsInput:
            return [.needsInput, .waitingForConfirmation, .thinking, .idle]
        case .listening:
            return [.listening, .idle]
        case .playingAudio:
            return [.playingAudio, .working, .idle]
        case .automation:
            return [.automation, .working, .thinking, .idle]
        case .triggered:
            return [.triggered, .working, .idle]
        case .thinking:
            return [.thinking, .idle]
        case .idle:
            return [.idle]
        }
    }

    private func choose(_ assets: [PetAnimationAsset], at date: Date) -> PetAnimationAsset? {
        guard !assets.isEmpty else { return nil }
        let slot = max(Int(date.timeIntervalSince1970 / Self.rotationInterval), 0)
        let weighted = assets.flatMap { asset in
            Array(repeating: asset, count: max(asset.weight, 1))
        }
        return weighted[slot % weighted.count]
    }
}
