import Testing
@testable import 看板娘

struct MatchaDandanCharacterTests {
    @Test
    func providesAnAnimationForEveryActivityState() {
        #expect(Set(matchaDandan.assetsByState.keys) == Set(PetActivityState.allCases))
        #expect(matchaDandan.assetsByState.values.allSatisfy { $0.count == 1 })
        #expect(matchaDandan.interactionAssets.count == 1)
        #expect(matchaDandan.interactionAssets.first?.loop == false)
    }

    @Test
    func usesUniqueBundledGifAssets() {
        let assets = matchaDandan.assetsByState.values.flatMap { $0 }
            + matchaDandan.interactionAssets

        #expect(Set(assets.map(\.id)).count == assets.count)
        #expect(Set(assets.map(\.location)).count == assets.count)
        #expect(assets.allSatisfy { $0.type == .gif })
        #expect(assets.allSatisfy { !$0.location.hasPrefix("/") })
    }
}
