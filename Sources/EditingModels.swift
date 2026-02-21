import Foundation

struct AdjustmentSettings: Codable, Hashable {
    var exposureEV: Double
    var contrast: Double
    var highlightsRecover: Double
    var shadowsLift: Double
    var temperatureMired: Double
    var tintShift: Double
    var vibrance: Double
    var saturation: Double
    var vintageAmount: Double
    var fade: Double
    var splitToneWarmHighlights: Double
    var splitToneCoolShadows: Double
    var grainAmount: Double
    var grainSize: Double
    var vignetteAmount: Double
    var contrastSoftening: Double
    var lutID: String?
    var lutIntensity: Double
    var pipelineVersion: Int
    var rotateDegrees: Double
    var straightenDegrees: Double
    var cropScale: Double
    var cropOffsetX: Double
    var cropOffsetY: Double

    static let `default` = AdjustmentSettings(
        exposureEV: 0,
        contrast: 1,
        highlightsRecover: 0,
        shadowsLift: 0,
        temperatureMired: 0,
        tintShift: 0,
        vibrance: 0,
        saturation: 1,
        vintageAmount: 0,
        fade: 0,
        splitToneWarmHighlights: 0,
        splitToneCoolShadows: 0,
        grainAmount: 0,
        grainSize: 0.5,
        vignetteAmount: 0,
        contrastSoftening: 0,
        lutID: nil,
        lutIntensity: 1,
        pipelineVersion: 2,
        rotateDegrees: 0,
        straightenDegrees: 0,
        cropScale: 1,
        cropOffsetX: 0,
        cropOffsetY: 0
    )

    private enum CodingKeys: String, CodingKey {
        case exposureEV
        case contrast
        case highlightsRecover
        case shadowsLift
        case temperatureMired
        case tintShift
        case vibrance
        case saturation
        case vintageAmount
        case fade
        case splitToneWarmHighlights
        case splitToneCoolShadows
        case grainAmount
        case grainSize
        case vignetteAmount
        case contrastSoftening
        case lutID
        case lutIntensity
        case pipelineVersion
        case rotateDegrees
        case straightenDegrees
        case cropScale
        case cropOffsetX
        case cropOffsetY
        // Legacy keys for migration.
        case highlights
        case shadows
        case temperature
        case tint
    }

    init(
        exposureEV: Double,
        contrast: Double,
        highlightsRecover: Double,
        shadowsLift: Double,
        temperatureMired: Double,
        tintShift: Double,
        vibrance: Double,
        saturation: Double,
        vintageAmount: Double,
        fade: Double,
        splitToneWarmHighlights: Double,
        splitToneCoolShadows: Double,
        grainAmount: Double,
        grainSize: Double,
        vignetteAmount: Double,
        contrastSoftening: Double,
        lutID: String?,
        lutIntensity: Double,
        pipelineVersion: Int,
        rotateDegrees: Double,
        straightenDegrees: Double,
        cropScale: Double,
        cropOffsetX: Double,
        cropOffsetY: Double
    ) {
        self.exposureEV = exposureEV
        self.contrast = contrast
        self.highlightsRecover = highlightsRecover
        self.shadowsLift = shadowsLift
        self.temperatureMired = temperatureMired
        self.tintShift = tintShift
        self.vibrance = vibrance
        self.saturation = saturation
        self.vintageAmount = vintageAmount
        self.fade = fade
        self.splitToneWarmHighlights = splitToneWarmHighlights
        self.splitToneCoolShadows = splitToneCoolShadows
        self.grainAmount = grainAmount
        self.grainSize = grainSize
        self.vignetteAmount = vignetteAmount
        self.contrastSoftening = contrastSoftening
        self.lutID = lutID
        self.lutIntensity = lutIntensity
        self.pipelineVersion = pipelineVersion
        self.rotateDegrees = rotateDegrees
        self.straightenDegrees = straightenDegrees
        self.cropScale = cropScale
        self.cropOffsetX = cropOffsetX
        self.cropOffsetY = cropOffsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyHighlights = try container.decodeIfPresent(Double.self, forKey: .highlights)
        let legacyShadows = try container.decodeIfPresent(Double.self, forKey: .shadows)
        let legacyTemperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        let legacyTint = try container.decodeIfPresent(Double.self, forKey: .tint)
        let containsLegacyKeys = legacyHighlights != nil || legacyShadows != nil || legacyTemperature != nil || legacyTint != nil

        exposureEV = try container.decodeIfPresent(Double.self, forKey: .exposureEV) ?? Self.default.exposureEV
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? Self.default.contrast
        highlightsRecover = try container.decodeIfPresent(Double.self, forKey: .highlightsRecover)
            ?? max(0, -(legacyHighlights ?? 0))
        shadowsLift = try container.decodeIfPresent(Double.self, forKey: .shadowsLift)
            ?? max(0, legacyShadows ?? 0)
        temperatureMired = try container.decodeIfPresent(Double.self, forKey: .temperatureMired)
            ?? Self.legacyTemperatureToMired(legacyTemperature ?? 0)
        tintShift = try container.decodeIfPresent(Double.self, forKey: .tintShift)
            ?? Self.legacyTintToShift(legacyTint ?? 0)
        vibrance = try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? Self.default.vibrance
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? Self.default.saturation
        vintageAmount = try container.decodeIfPresent(Double.self, forKey: .vintageAmount) ?? Self.default.vintageAmount
        fade = try container.decodeIfPresent(Double.self, forKey: .fade) ?? Self.default.fade
        splitToneWarmHighlights = try container.decodeIfPresent(Double.self, forKey: .splitToneWarmHighlights) ?? Self.default.splitToneWarmHighlights
        splitToneCoolShadows = try container.decodeIfPresent(Double.self, forKey: .splitToneCoolShadows) ?? Self.default.splitToneCoolShadows
        grainAmount = try container.decodeIfPresent(Double.self, forKey: .grainAmount) ?? Self.default.grainAmount
        grainSize = try container.decodeIfPresent(Double.self, forKey: .grainSize) ?? Self.default.grainSize
        vignetteAmount = try container.decodeIfPresent(Double.self, forKey: .vignetteAmount) ?? Self.default.vignetteAmount
        contrastSoftening = try container.decodeIfPresent(Double.self, forKey: .contrastSoftening) ?? Self.default.contrastSoftening
        lutID = try container.decodeIfPresent(String.self, forKey: .lutID)
        lutIntensity = try container.decodeIfPresent(Double.self, forKey: .lutIntensity) ?? Self.default.lutIntensity
        pipelineVersion = try container.decodeIfPresent(Int.self, forKey: .pipelineVersion)
            ?? (containsLegacyKeys ? 1 : Self.default.pipelineVersion)
        rotateDegrees = try container.decodeIfPresent(Double.self, forKey: .rotateDegrees) ?? Self.default.rotateDegrees
        straightenDegrees = try container.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? Self.default.straightenDegrees
        cropScale = try container.decodeIfPresent(Double.self, forKey: .cropScale) ?? Self.default.cropScale
        cropOffsetX = try container.decodeIfPresent(Double.self, forKey: .cropOffsetX) ?? Self.default.cropOffsetX
        cropOffsetY = try container.decodeIfPresent(Double.self, forKey: .cropOffsetY) ?? Self.default.cropOffsetY
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exposureEV, forKey: .exposureEV)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(highlightsRecover, forKey: .highlightsRecover)
        try container.encode(shadowsLift, forKey: .shadowsLift)
        try container.encode(temperatureMired, forKey: .temperatureMired)
        try container.encode(tintShift, forKey: .tintShift)
        try container.encode(vibrance, forKey: .vibrance)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(vintageAmount, forKey: .vintageAmount)
        try container.encode(fade, forKey: .fade)
        try container.encode(splitToneWarmHighlights, forKey: .splitToneWarmHighlights)
        try container.encode(splitToneCoolShadows, forKey: .splitToneCoolShadows)
        try container.encode(grainAmount, forKey: .grainAmount)
        try container.encode(grainSize, forKey: .grainSize)
        try container.encode(vignetteAmount, forKey: .vignetteAmount)
        try container.encode(contrastSoftening, forKey: .contrastSoftening)
        try container.encodeIfPresent(lutID, forKey: .lutID)
        try container.encode(lutIntensity, forKey: .lutIntensity)
        try container.encode(pipelineVersion, forKey: .pipelineVersion)
        try container.encode(rotateDegrees, forKey: .rotateDegrees)
        try container.encode(straightenDegrees, forKey: .straightenDegrees)
        try container.encode(cropScale, forKey: .cropScale)
        try container.encode(cropOffsetX, forKey: .cropOffsetX)
        try container.encode(cropOffsetY, forKey: .cropOffsetY)
    }

    static func legacyTemperatureToMired(_ legacy: Double) -> Double {
        let clamped = min(max(legacy, -1), 1)
        return clamped * 100
    }

    static func legacyTintToShift(_ legacy: Double) -> Double {
        let clamped = min(max(legacy, -1), 1)
        return clamped * 100
    }
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
                highlightsRecover: 0.2,
                shadowsLift: 0.2,
                temperatureMired: 5,
                tintShift: 3,
                vibrance: 0.45,
                saturation: 1.05,
                vintageAmount: 0,
                fade: 0,
                splitToneWarmHighlights: 0,
                splitToneCoolShadows: 0,
                grainAmount: 0,
                grainSize: 0.5,
                vignetteAmount: 0,
                contrastSoftening: 0,
                lutID: nil,
                lutIntensity: 1,
                pipelineVersion: 2,
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
                highlightsRecover: 0.1,
                shadowsLift: 0.15,
                temperatureMired: 0,
                tintShift: 0,
                vibrance: 0,
                saturation: 0,
                vintageAmount: 0,
                fade: 0,
                splitToneWarmHighlights: 0,
                splitToneCoolShadows: 0,
                grainAmount: 0,
                grainSize: 0.5,
                vignetteAmount: 0,
                contrastSoftening: 0,
                lutID: nil,
                lutIntensity: 1,
                pipelineVersion: 2,
                rotateDegrees: 0,
                straightenDegrees: 0,
                cropScale: 1,
                cropOffsetX: 0,
                cropOffsetY: 0
            ),
            isBuiltIn: true
        ),
        AdjustmentPreset(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            name: "Vintage Soft",
            settings: AdjustmentSettings(
                exposureEV: 0,
                contrast: 0.96,
                highlightsRecover: 0.15,
                shadowsLift: 0.18,
                temperatureMired: 12,
                tintShift: 4,
                vibrance: 0.08,
                saturation: 0.94,
                vintageAmount: 0.55,
                fade: 0.45,
                splitToneWarmHighlights: 0.2,
                splitToneCoolShadows: 0.12,
                grainAmount: 0.18,
                grainSize: 0.55,
                vignetteAmount: 0.2,
                contrastSoftening: 0.22,
                lutID: nil,
                lutIntensity: 1,
                pipelineVersion: 2,
                rotateDegrees: 0,
                straightenDegrees: 0,
                cropScale: 1,
                cropOffsetX: 0,
                cropOffsetY: 0
            ),
            isBuiltIn: true
        ),
        AdjustmentPreset(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            name: "Vintage Warm",
            settings: AdjustmentSettings(
                exposureEV: 0.05,
                contrast: 0.98,
                highlightsRecover: 0.18,
                shadowsLift: 0.16,
                temperatureMired: 20,
                tintShift: 10,
                vibrance: 0.1,
                saturation: 0.98,
                vintageAmount: 0.7,
                fade: 0.34,
                splitToneWarmHighlights: 0.35,
                splitToneCoolShadows: 0.08,
                grainAmount: 0.16,
                grainSize: 0.48,
                vignetteAmount: 0.24,
                contrastSoftening: 0.18,
                lutID: nil,
                lutIntensity: 1,
                pipelineVersion: 2,
                rotateDegrees: 0,
                straightenDegrees: 0,
                cropScale: 1,
                cropOffsetX: 0,
                cropOffsetY: 0
            ),
            isBuiltIn: true
        ),
        AdjustmentPreset(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            name: "Vintage Matte",
            settings: AdjustmentSettings(
                exposureEV: -0.02,
                contrast: 0.9,
                highlightsRecover: 0.2,
                shadowsLift: 0.24,
                temperatureMired: 6,
                tintShift: -6,
                vibrance: -0.04,
                saturation: 0.88,
                vintageAmount: 0.78,
                fade: 0.62,
                splitToneWarmHighlights: 0.16,
                splitToneCoolShadows: 0.26,
                grainAmount: 0.24,
                grainSize: 0.62,
                vignetteAmount: 0.32,
                contrastSoftening: 0.34,
                lutID: nil,
                lutIntensity: 1,
                pipelineVersion: 2,
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
