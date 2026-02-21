import Foundation
import AppKit
import XCTest
@testable import darkroom

final class AdjustmentPipelineTests: XCTestCase {
    func testLegacyAdjustmentDecodingMigratesToV2Fields() throws {
        let legacyJSON = """
        {
          "exposureEV": 0.1,
          "contrast": 1.1,
          "highlights": -0.35,
          "shadows": 0.4,
          "temperature": 0.5,
          "tint": -0.25,
          "vibrance": 0.2,
          "saturation": 1.05,
          "rotateDegrees": 0,
          "straightenDegrees": 0,
          "cropScale": 1,
          "cropOffsetX": 0,
          "cropOffsetY": 0
        }
        """
        let settings = try JSONDecoder().decode(AdjustmentSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(settings.highlightsRecover, 0.35, accuracy: 0.0001)
        XCTAssertEqual(settings.shadowsLift, 0.4, accuracy: 0.0001)
        XCTAssertEqual(settings.temperatureMired, 50, accuracy: 0.0001)
        XCTAssertEqual(settings.tintShift, -25, accuracy: 0.0001)
        XCTAssertEqual(settings.pipelineVersion, 1)
    }

    func testWhiteBalanceChannelGainsAreMonotonicAcrossTemperature() {
        let cool = AdjustmentEngine.whiteBalanceChannelGains(temperatureMired: -150, tintShift: 0)
        let neutral = AdjustmentEngine.whiteBalanceChannelGains(temperatureMired: 0, tintShift: 0)
        let warm = AdjustmentEngine.whiteBalanceChannelGains(temperatureMired: 150, tintShift: 0)
        XCTAssertLessThan(cool.0, neutral.0)
        XCTAssertGreaterThan(warm.0, neutral.0)
        XCTAssertGreaterThan(cool.2, neutral.2)
        XCTAssertLessThan(warm.2, neutral.2)
    }

    func testCubeLUTParserParsesValidCubeAndRejectsInvalidEntryCount() throws {
        let validCube = """
        TITLE "Test LUT"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        let parsed = try CubeLUTParser.parse(validCube)
        XCTAssertEqual(parsed.dimension, 2)
        XCTAssertEqual(parsed.domainMin.x, 0)
        XCTAssertEqual(parsed.domainMax.z, 1)
        XCTAssertEqual(parsed.data.count, 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)

        let invalidCube = """
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        """
        XCTAssertThrowsError(try CubeLUTParser.parse(invalidCube))
    }

    func testBWPresetProducesNearGrayscaleOutput() async throws {
        let input = try makeColorfulTestImage(width: 180, height: 120)
        guard let bwPreset = AdjustmentPreset.builtIns.first(where: { $0.name == "B&W" }) else {
            XCTFail("B&W preset missing")
            return
        }

        let output = await AdjustmentEngine.shared.apply(bwPreset.settings, to: input)
        guard let output,
              let cg = output.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let providerData = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else {
            XCTFail("Failed to render B&W output")
            return
        }

        let width = cg.width
        let height = cg.height
        let bitsPerPixel = cg.bitsPerPixel
        let bytesPerRow = cg.bytesPerRow
        guard bitsPerPixel >= 24 else {
            XCTFail("Unexpected pixel format")
            return
        }

        var sampled = 0
        var accumulatedChannelSpread: Double = 0
        let step = Swift.max(1, Swift.min(width, height) / 20)
        for y in Swift.stride(from: 0, to: height, by: step) {
            for x in Swift.stride(from: 0, to: width, by: step) {
                let offset = y * bytesPerRow + x * (bitsPerPixel / 8)
                let r = Double(bytes[offset])
                let g = Double(bytes[offset + 1])
                let b = Double(bytes[offset + 2])
                let maxRGB = Swift.max(r, Swift.max(g, b))
                let minRGB = Swift.min(r, Swift.min(g, b))
                accumulatedChannelSpread += Double(maxRGB - minRGB)
                sampled += 1
            }
        }

        XCTAssertGreaterThan(sampled, 10)
        let meanSpread = accumulatedChannelSpread / Double(sampled)
        XCTAssertLessThanOrEqual(meanSpread, 6.0, "B&W output still has high chroma; mean channel spread: \(meanSpread)")
    }

    private func makeColorfulTestImage(width: Int, height: Int) throws -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor(red: 0.96, green: 0.24, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width / 3, height: height)).fill()
        NSColor(red: 0.15, green: 0.84, blue: 0.31, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: width / 3, y: 0, width: width / 3, height: height)).fill()
        NSColor(red: 0.12, green: 0.38, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: (width / 3) * 2, y: 0, width: width - (width / 3) * 2, height: height)).fill()

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2)).fill()
        return image
    }
}
