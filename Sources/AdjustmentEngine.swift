import AppKit
import CoreImage
import Foundation

actor AdjustmentEngine {
    static let shared = AdjustmentEngine()

    private let context = CIContext(options: nil)
    private static let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private static let epsilon = 0.0001
    private static let tonalKernel: CIColorKernel? = {
        CIColorKernel(source: """
        kernel vec4 tonalLiftRecover(__sample s, float highlightsRecover, float shadowsLift) {
            vec3 rgb = clamp(s.rgb, 0.0, 1.0);
            float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
            float shadowMask = 1.0 - smoothstep(0.08, 0.62, luma);
            float highlightMask = smoothstep(0.42, 0.96, luma);
            float midMask = exp(-pow((luma - 0.5) / 0.22, 2.0));
            float liftDelta = shadowsLift * shadowMask * (1.0 - luma) * 0.72;
            float recoverDelta = highlightsRecover * highlightMask * luma * 0.72;
            float delta = (liftDelta - recoverDelta) * (1.0 - (midMask * 0.55));
            vec3 outRGB = clamp(rgb + vec3(delta), 0.0, 1.0);
            return vec4(outRGB, s.a);
        }
        """)
    }()
    private static let splitToneKernel: CIColorKernel? = {
        CIColorKernel(source: """
        kernel vec4 splitTone(__sample s, float warmHighlights, float coolShadows) {
            vec3 rgb = clamp(s.rgb, 0.0, 1.0);
            float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
            float hMask = smoothstep(0.50, 1.0, luma);
            float sMask = 1.0 - smoothstep(0.0, 0.48, luma);
            vec3 warm = vec3(1.0, 0.55, -0.32) * warmHighlights * hMask * 0.10;
            vec3 cool = vec3(-0.26, -0.07, 1.0) * coolShadows * sMask * 0.10;
            vec3 outRGB = clamp(rgb + warm + cool, 0.0, 1.0);
            return vec4(outRGB, s.a);
        }
        """)
    }()

    func apply(_ settings: AdjustmentSettings, to image: NSImage) async -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              var workingImage = CIImage(data: tiff) else {
            return image
        }

        let originalExtent = workingImage.extent
        guard !originalExtent.isEmpty else { return image }
        var needsOutputTransform = false

        if settings.pipelineVersion <= 1 {
            workingImage = applyLegacyPipeline(settings: settings, image: workingImage)
        } else {
            workingImage = applyLinearize(workingImage)
            workingImage = applyExposure(settings.exposureEV, to: workingImage)
            workingImage = applyBaseTone(settings: settings, image: workingImage)
            workingImage = applyHighlightsShadowsV2(settings: settings, image: workingImage)
            workingImage = applyWhiteBalanceV2(settings: settings, image: workingImage)
            workingImage = applyVibranceSaturation(settings: settings, image: workingImage)
            workingImage = applyVintage(settings: settings, image: workingImage)
            workingImage = await applyLUT(settings: settings, image: workingImage)
            needsOutputTransform = true
        }

        var transformed = applyGeometry(settings: settings, image: workingImage, originalExtent: originalExtent)
        if needsOutputTransform {
            transformed = applyDelinearize(transformed)
        }
        let finalExtent = transformed.extent.integral
        guard let cgImage = context.createCGImage(transformed, from: finalExtent) else {
            return image
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: finalExtent.width, height: finalExtent.height))
    }

    func applyExposure(to image: NSImage, exposureEV: Double) async -> NSImage? {
        var settings = AdjustmentSettings.default
        settings.exposureEV = exposureEV
        return await apply(settings, to: image)
    }

    private func applyLegacyPipeline(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        var output = image
        output = applyExposure(settings.exposureEV, to: output)
        output = applyColorControls(settings: settings, image: output)
        output = applyHighlightsShadowsLegacy(settings: settings, image: output)
        output = applyWhiteBalanceLegacy(settings: settings, image: output)
        return output
    }

    private func applyLinearize(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISRGBToneCurveToLinear") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private func applyDelinearize(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CILinearToSRGBToneCurve") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private func applyExposure(_ value: Double, to image: CIImage) -> CIImage {
        guard abs(value) > Self.epsilon,
              let filter = CIFilter(name: "CIExposureAdjust") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(value, forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    private func applyBaseTone(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        let softenedContrast = settings.contrast * (1 - (min(max(settings.contrastSoftening, 0), 1) * 0.22))
        guard abs(softenedContrast - 1) > Self.epsilon,
              let filter = CIFilter(name: "CIColorControls") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(softenedContrast, forKey: kCIInputContrastKey)
        filter.setValue(1.0, forKey: kCIInputSaturationKey)
        filter.setValue(0.0, forKey: kCIInputBrightnessKey)
        return filter.outputImage ?? image
    }

    private func applyColorControls(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        guard abs(settings.contrast - 1) > Self.epsilon || abs(settings.saturation - 1) > Self.epsilon,
              let filter = CIFilter(name: "CIColorControls") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
        filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
        filter.setValue(0.0, forKey: kCIInputBrightnessKey)
        return filter.outputImage ?? image
    }

    private func applyHighlightsShadowsLegacy(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        let legacyHighlights = max(-1.0, min(1.0, -settings.highlightsRecover))
        let legacyShadows = max(-1.0, min(1.0, settings.shadowsLift))
        guard abs(legacyHighlights) > Self.epsilon || abs(legacyShadows) > Self.epsilon,
              let filter = CIFilter(name: "CIHighlightShadowAdjust") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(legacyHighlights, forKey: "inputHighlightAmount")
        filter.setValue(legacyShadows, forKey: "inputShadowAmount")
        return filter.outputImage ?? image
    }

    private func applyHighlightsShadowsV2(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        let highlightsRecover = min(max(settings.highlightsRecover, 0), 1)
        let shadowsLift = min(max(settings.shadowsLift, 0), 1)
        guard abs(highlightsRecover) > Self.epsilon || abs(shadowsLift) > Self.epsilon,
              let kernel = Self.tonalKernel else {
            return image
        }
        return kernel.apply(extent: image.extent, arguments: [image, highlightsRecover, shadowsLift]) ?? image
    }

    private func applyWhiteBalanceLegacy(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        var output = image

        if abs(settings.vibrance) > Self.epsilon,
           let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(output, forKey: kCIInputImageKey)
            vibrance.setValue(settings.vibrance, forKey: "inputAmount")
            output = vibrance.outputImage ?? output
        }

        let temperatureDelta = max(-1.0, min(1.0, settings.temperatureMired / 100))
        let tintDelta = max(-1.0, min(1.0, settings.tintShift / 100))
        guard abs(temperatureDelta) > Self.epsilon || abs(tintDelta) > Self.epsilon,
              let filter = CIFilter(name: "CITemperatureAndTint") else {
            return output
        }

        let neutral = CIVector(x: 6500, y: 0)
        let target = CIVector(
            x: 6500 + (temperatureDelta * 1700),
            y: tintDelta * 170
        )
        filter.setValue(output, forKey: kCIInputImageKey)
        filter.setValue(neutral, forKey: "inputNeutral")
        filter.setValue(target, forKey: "inputTargetNeutral")
        return filter.outputImage ?? output
    }

    private func applyWhiteBalanceV2(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        let (r, g, b) = Self.whiteBalanceChannelGains(
            temperatureMired: settings.temperatureMired,
            tintShift: settings.tintShift
        )
        guard abs(Double(r - 1)) > Self.epsilon || abs(Double(g - 1)) > Self.epsilon || abs(Double(b - 1)) > Self.epsilon,
              let filter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: CGFloat(r), y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: CGFloat(g), z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: CGFloat(b), w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return filter.outputImage ?? image
    }

    private func applyVibranceSaturation(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        var output = image
        if abs(settings.vibrance) > Self.epsilon,
           let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(output, forKey: kCIInputImageKey)
            vibrance.setValue(settings.vibrance, forKey: "inputAmount")
            output = vibrance.outputImage ?? output
        }
        guard abs(settings.saturation - 1) > Self.epsilon,
              let controls = CIFilter(name: "CIColorControls") else {
            return output
        }
        controls.setValue(output, forKey: kCIInputImageKey)
        controls.setValue(settings.saturation, forKey: kCIInputSaturationKey)
        controls.setValue(1.0, forKey: kCIInputContrastKey)
        controls.setValue(0.0, forKey: kCIInputBrightnessKey)
        return controls.outputImage ?? output
    }

    private func applyVintage(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        let amount = min(max(settings.vintageAmount, 0), 1)
        guard amount > Self.epsilon else { return image }
        var output = image

        let fade = min(max(settings.fade, 0), 1) * amount
        if fade > Self.epsilon,
           let toneCurve = CIFilter(name: "CIToneCurve") {
            toneCurve.setValue(output, forKey: kCIInputImageKey)
            toneCurve.setValue(CIVector(x: 0, y: fade * 0.12), forKey: "inputPoint0")
            toneCurve.setValue(CIVector(x: 0.25, y: 0.25 + (fade * 0.03)), forKey: "inputPoint1")
            toneCurve.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            toneCurve.setValue(CIVector(x: 0.75, y: 0.74), forKey: "inputPoint3")
            toneCurve.setValue(CIVector(x: 1, y: 1 - (fade * 0.03)), forKey: "inputPoint4")
            output = toneCurve.outputImage ?? output
        }

        let warmHighlights = min(max(settings.splitToneWarmHighlights, 0), 1) * amount
        let coolShadows = min(max(settings.splitToneCoolShadows, 0), 1) * amount
        if (warmHighlights > Self.epsilon || coolShadows > Self.epsilon),
           let kernel = Self.splitToneKernel {
            output = kernel.apply(extent: output.extent, arguments: [output, warmHighlights, coolShadows]) ?? output
        }

        let vignetteAmount = min(max(settings.vignetteAmount, 0), 1) * amount
        if vignetteAmount > Self.epsilon,
           let vignette = CIFilter(name: "CIVignette") {
            vignette.setValue(output, forKey: kCIInputImageKey)
            vignette.setValue(vignetteAmount * 1.6, forKey: kCIInputIntensityKey)
            vignette.setValue(1.1, forKey: kCIInputRadiusKey)
            output = vignette.outputImage ?? output
        }

        let grainAmount = min(max(settings.grainAmount, 0), 1) * amount
        if grainAmount > Self.epsilon {
            output = applyFilmGrain(output, amount: grainAmount, grainSize: settings.grainSize)
        }
        return output
    }

    private func applyFilmGrain(_ image: CIImage, amount: Double, grainSize: Double) -> CIImage {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let scale = max(0.2, 1.4 - (min(max(grainSize, 0), 1) * 1.1))
        guard let scaler = CIFilter(name: "CILanczosScaleTransform") else { return image }
        scaler.setValue(random, forKey: kCIInputImageKey)
        scaler.setValue(scale, forKey: kCIInputScaleKey)
        scaler.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let scaledNoise = scaler.outputImage?.cropped(to: image.extent) else { return image }

        guard let noiseMatrix = CIFilter(name: "CIColorMatrix") else { return image }
        let intensity = CGFloat(amount * 0.07)
        noiseMatrix.setValue(scaledNoise, forKey: kCIInputImageKey)
        noiseMatrix.setValue(CIVector(x: intensity, y: 0, z: 0, w: 0), forKey: "inputRVector")
        noiseMatrix.setValue(CIVector(x: 0, y: intensity, z: 0, w: 0), forKey: "inputGVector")
        noiseMatrix.setValue(CIVector(x: 0, y: 0, z: intensity, w: 0), forKey: "inputBVector")
        noiseMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        noiseMatrix.setValue(CIVector(x: -intensity * 0.5, y: -intensity * 0.5, z: -intensity * 0.5, w: 0), forKey: "inputBiasVector")
        let tintedNoise = noiseMatrix.outputImage ?? scaledNoise

        guard let add = CIFilter(name: "CIAdditionCompositing") else { return image }
        add.setValue(tintedNoise, forKey: kCIInputImageKey)
        add.setValue(image, forKey: kCIInputBackgroundImageKey)
        return add.outputImage?.cropped(to: image.extent) ?? image
    }

    private func applyLUT(settings: AdjustmentSettings, image: CIImage) async -> CIImage {
        let intensity = min(max(settings.lutIntensity, 0), 1)
        guard intensity > Self.epsilon,
              let lutID = settings.lutID,
              let payload = await LUTLibrary.shared.lutPayload(for: lutID),
              let lutFilter = CIFilter(name: "CIColorCubeWithColorSpace") else {
            return image
        }

        let domainMapped = applyLUTInputDomain(image: image, domainMin: payload.domainMin, domainMax: payload.domainMax)
        lutFilter.setValue(domainMapped, forKey: kCIInputImageKey)
        lutFilter.setValue(payload.data, forKey: "inputCubeData")
        lutFilter.setValue(payload.dimension, forKey: "inputCubeDimension")
        lutFilter.setValue(Self.outputColorSpace, forKey: "inputColorSpace")
        let lutResult = (lutFilter.outputImage ?? domainMapped).cropped(to: image.extent)
        guard intensity < 0.999,
              let blend = CIFilter(name: "CIBlendWithAlphaMask"),
              let maskGenerator = CIFilter(name: "CIConstantColorGenerator") else {
            return lutResult
        }

        let alpha = CGFloat(intensity)
        maskGenerator.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: alpha), forKey: kCIInputColorKey)
        let mask = (maskGenerator.outputImage ?? lutResult).cropped(to: image.extent)
        blend.setValue(lutResult, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage?.cropped(to: image.extent) ?? lutResult
    }

    private func applyLUTInputDomain(image: CIImage, domainMin: SIMD3<Float>, domainMax: SIMD3<Float>) -> CIImage {
        let safeRange = SIMD3<Float>(
            max(domainMax.x - domainMin.x, 0.0001),
            max(domainMax.y - domainMin.y, 0.0001),
            max(domainMax.z - domainMin.z, 0.0001)
        )
        let scales = SIMD3<Float>(1 / safeRange.x, 1 / safeRange.y, 1 / safeRange.z)
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: CGFloat(scales.x), y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: CGFloat(scales.y), z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: CGFloat(scales.z), w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(
            CIVector(
                x: CGFloat(-(domainMin.x * scales.x)),
                y: CGFloat(-(domainMin.y * scales.y)),
                z: CGFloat(-(domainMin.z * scales.z)),
                w: 0
            ),
            forKey: "inputBiasVector"
        )
        return matrix.outputImage?.cropped(to: image.extent) ?? image
    }

    static func whiteBalanceChannelGains(temperatureMired: Double, tintShift: Double) -> (Float, Float, Float) {
        let clampedTemp = Float(min(max(temperatureMired, -150), 150) / 150.0)
        let clampedTint = Float(min(max(tintShift, -150), 150) / 150.0)
        let tempWeight: Float = 0.16
        let tintWeight: Float = 0.12
        let r = 1 + (clampedTemp * tempWeight) + (clampedTint * tintWeight * 0.5)
        let g = 1 - (clampedTint * tintWeight)
        let b = 1 - (clampedTemp * tempWeight) + (clampedTint * tintWeight * 0.5)
        return (max(0.72, r), max(0.72, g), max(0.72, b))
    }

    private func applyGeometry(settings: AdjustmentSettings, image: CIImage, originalExtent: CGRect) -> CIImage {
        var output = image
        let totalRotation = settings.rotateDegrees + settings.straightenDegrees
        if abs(totalRotation) > Self.epsilon {
            let radians = CGFloat(totalRotation) * .pi / 180
            let center = CGPoint(x: originalExtent.midX, y: originalExtent.midY)
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: center.x, y: center.y)
            transform = transform.rotated(by: radians)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            output = output.transformed(by: transform)
        }

        let scale = max(0.4, min(1.0, settings.cropScale))
        let offsetX = max(-1.0, min(1.0, settings.cropOffsetX))
        let offsetY = max(-1.0, min(1.0, settings.cropOffsetY))
        guard scale < 0.999 || abs(offsetX) > Self.epsilon || abs(offsetY) > Self.epsilon else {
            return output.cropped(to: output.extent)
        }

        let sourceExtent = output.extent
        let cropWidth = sourceExtent.width * scale
        let cropHeight = sourceExtent.height * scale
        let maxShiftX = (sourceExtent.width - cropWidth) / 2
        let maxShiftY = (sourceExtent.height - cropHeight) / 2
        let centerX = sourceExtent.midX + maxShiftX * offsetX
        let centerY = sourceExtent.midY + maxShiftY * offsetY
        let cropRect = CGRect(
            x: centerX - cropWidth / 2,
            y: centerY - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        ).integral
        return output.cropped(to: cropRect)
    }
}
