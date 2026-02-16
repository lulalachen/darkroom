import AppKit
import CoreImage
import Foundation

actor AdjustmentEngine {
    static let shared = AdjustmentEngine()

    private let context = CIContext(options: nil)

    func apply(_ settings: AdjustmentSettings, to image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              var workingImage = CIImage(data: tiff) else {
            return image
        }

        let originalExtent = workingImage.extent
        guard !originalExtent.isEmpty else { return image }

        workingImage = applyExposure(settings.exposureEV, to: workingImage)
        workingImage = applyColorControls(settings: settings, image: workingImage)
        workingImage = applyHighlightsShadows(settings: settings, image: workingImage)
        workingImage = applyWhiteBalance(settings: settings, image: workingImage)

        let transformed = applyGeometry(settings: settings, image: workingImage, originalExtent: originalExtent)
        let finalExtent = transformed.extent.integral
        guard let cgImage = context.createCGImage(transformed, from: finalExtent) else {
            return image
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: finalExtent.width, height: finalExtent.height))
    }

    func applyExposure(to image: NSImage, exposureEV: Double) -> NSImage? {
        let settings = AdjustmentSettings(
            exposureEV: exposureEV,
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
        return apply(settings, to: image)
    }

    private func applyExposure(_ value: Double, to image: CIImage) -> CIImage {
        guard abs(value) > 0.0001,
              let filter = CIFilter(name: "CIExposureAdjust") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(value, forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    private func applyColorControls(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        guard abs(settings.contrast - 1) > 0.0001 || abs(settings.saturation - 1) > 0.0001,
              let filter = CIFilter(name: "CIColorControls") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
        filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
        filter.setValue(0.0, forKey: kCIInputBrightnessKey)
        return filter.outputImage ?? image
    }

    private func applyHighlightsShadows(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        guard abs(settings.highlights) > 0.0001 || abs(settings.shadows) > 0.0001,
              let filter = CIFilter(name: "CIHighlightShadowAdjust") else {
            return image
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(max(-1.0, min(1.0, settings.highlights)), forKey: "inputHighlightAmount")
        filter.setValue(max(-1.0, min(1.0, settings.shadows)), forKey: "inputShadowAmount")
        return filter.outputImage ?? image
    }

    private func applyWhiteBalance(settings: AdjustmentSettings, image: CIImage) -> CIImage {
        var output = image

        if abs(settings.vibrance) > 0.0001,
           let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(output, forKey: kCIInputImageKey)
            vibrance.setValue(settings.vibrance, forKey: "inputAmount")
            output = vibrance.outputImage ?? output
        }

        let temperatureDelta = max(-1.0, min(1.0, settings.temperature))
        let tintDelta = max(-1.0, min(1.0, settings.tint))
        guard abs(temperatureDelta) > 0.0001 || abs(tintDelta) > 0.0001,
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

    private func applyGeometry(settings: AdjustmentSettings, image: CIImage, originalExtent: CGRect) -> CIImage {
        var output = image
        let totalRotation = settings.rotateDegrees + settings.straightenDegrees
        if abs(totalRotation) > 0.0001 {
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
        guard scale < 0.999 || abs(offsetX) > 0.0001 || abs(offsetY) > 0.0001 else {
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
