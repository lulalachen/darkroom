import Foundation

struct AdjustmentSettings: Codable, Hashable {
    var exposureEV: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var temperature: Double
    var tint: Double
    var vibrance: Double
    var saturation: Double
    var rotateDegrees: Double
    var straightenDegrees: Double
    var cropScale: Double
    var cropOffsetX: Double
    var cropOffsetY: Double

    static let `default` = AdjustmentSettings(
        exposureEV: 0,
        contrast: 1,
        highlights: 0,
        shadows: 0,
        temperature: 0,
        tint: 0,
        vibrance: 0,
        saturation: 1,
        rotateDegrees: 0,
        straightenDegrees: 0,
        cropScale: 1,
        cropOffsetX: 0,
        cropOffsetY: 0
    )
}

struct AdjustmentPreset: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let settings: AdjustmentSettings
    let isBuiltIn: Bool
}

struct AdjustmentBookmark: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let settings: AdjustmentSettings
    let updatedAt: Date
}

struct DerivedAdjustmentMetadata: Codable, Hashable {
    let assetPath: String
    let updatedAt: Date
    let hasAdjustments: Bool
    let rotationDegrees: Double
    let cropScale: Double
    let estimatedOutputWidth: Int
    let estimatedOutputHeight: Int
}

extension AdjustmentPreset {
    static let builtIns: [AdjustmentPreset] = [
        AdjustmentPreset(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, name: "Clean", settings: .default, isBuiltIn: true),
        AdjustmentPreset(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Vibrant",
            settings: AdjustmentSettings(
                exposureEV: 0.15,
                contrast: 1.12,
                highlights: -0.2,
                shadows: 0.2,
                temperature: 0.05,
                tint: 0.03,
                vibrance: 0.45,
                saturation: 1.05,
                rotateDegrees: 0,
                straightenDegrees: 0,
                cropScale: 1,
                cropOffsetX: 0,
                cropOffsetY: 0
            ),
            isBuiltIn: true
        ),
        AdjustmentPreset(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            name: "B&W",
            settings: AdjustmentSettings(
                exposureEV: 0.05,
                contrast: 1.18,
                highlights: -0.1,
                shadows: 0.15,
                temperature: 0,
                tint: 0,
                vibrance: 0,
                saturation: 0,
                rotateDegrees: 0,
                straightenDegrees: 0,
                cropScale: 1,
                cropOffsetX: 0,
                cropOffsetY: 0
            ),
            isBuiltIn: true
        )
    ]
}
