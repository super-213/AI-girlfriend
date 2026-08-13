import CoreGraphics
import Testing
@testable import 看板娘

struct InteractionPerformanceRegressionTests {
    @Test
    func listeningStatusResizesBeforeIdleFocusTransition() {
        let delta = PetListeningLayoutSynchronization.statusHeightDelta(
            focused: true,
            activityState: .idle,
            renderedState: .idle,
            rowHeight: 36
        )

        #expect(delta == 36)
    }

    @Test
    func endingListeningPreflightsStatusRowRemoval() {
        let delta = PetListeningLayoutSynchronization.statusHeightDelta(
            focused: false,
            activityState: .listening,
            renderedState: .listening,
            rowHeight: 36
        )

        #expect(delta == -36)
    }

    @Test
    func replacingAnExistingStatusDoesNotResizeTheWindow() {
        let delta = PetListeningLayoutSynchronization.statusHeightDelta(
            focused: true,
            activityState: .sleeping,
            renderedState: .sleeping,
            rowHeight: 36
        )

        #expect(delta == 0)
    }

    @Test
    func alphaMaskMapsAspectFitCoordinatesWithoutRenderingAViewTree() {
        // Bitmap rows are bottom-up. Make only the source image's top-left
        // pixel opaque and verify point mapping in a 20 x 20 fitted container.
        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        pixels[2 * 4 + 3] = 255
        let mask = PetImageAlphaMask(
            sourceSize: CGSize(width: 2, height: 2),
            pixelWidth: 2,
            pixelHeight: 2,
            bytesPerRow: 8,
            pixels: pixels
        )
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)

        #expect(mask.isOpaque(
            at: CGPoint(x: 5, y: 5),
            in: bounds,
            displayScale: 1,
            displayOffset: .zero,
            artworkAlignmentOffset: 0
        ))
        #expect(!mask.isOpaque(
            at: CGPoint(x: 15, y: 5),
            in: bounds,
            displayScale: 1,
            displayOffset: .zero,
            artworkAlignmentOffset: 0
        ))
    }

    @Test
    func alphaMaskAccountsForCharacterOffsets() {
        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        pixels[2 * 4 + 3] = 255
        let mask = PetImageAlphaMask(
            sourceSize: CGSize(width: 2, height: 2),
            pixelWidth: 2,
            pixelHeight: 2,
            bytesPerRow: 8,
            pixels: pixels
        )
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 20)

        #expect(mask.isOpaque(
            at: CGPoint(x: 15, y: 5),
            in: bounds,
            displayScale: 1,
            displayOffset: CGSize(width: 5, height: 0),
            artworkAlignmentOffset: 0
        ))
        #expect(!mask.isOpaque(
            at: CGPoint(x: 5, y: 5),
            in: bounds,
            displayScale: 1,
            displayOffset: CGSize(width: 5, height: 0),
            artworkAlignmentOffset: 0
        ))
    }

    @Test
    func calculatedGifDurationIsReusedFromMemory() throws {
        let location = try #require(matchaDandan.interactionAssets.first?.location)
        let duration = GIFDurationCalculator.getDuration(for: location)

        #expect(duration >= 0.5)
        #expect(GIFDurationCalculator.cachedDuration(for: location) == duration)
    }
}
