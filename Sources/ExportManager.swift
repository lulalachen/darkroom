import AppKit
import Foundation

actor ExportManager {
    private let fileManager = FileManager.default
    private var isCancelled = false
    private let maxConcurrentWorkers = 2
    private let auditLogger = ExportAuditLogger()
    private let adjustmentStore: AdjustmentStore

    init(adjustmentStore: AdjustmentStore = .shared) {
        self.adjustmentStore = adjustmentStore
    }

    func runQueue(
        items: [ExportQueueItem],
        preset: ExportPreset,
        destination: ExportDestinationOptions,
        progress: (@Sendable (ExportProgressSnapshot) -> Void)? = nil
    ) async throws -> ExportRunSummary {
        let queued = items.filter { !$0.state.isTerminal }
        guard !queued.isEmpty else {
            return ExportRunSummary(queuedCount: 0, exportedCount: 0, failedCount: 0, cancelledCount: 0)
        }

        isCancelled = false
        let workerCount = min(maxConcurrentWorkers, queued.count)
        let workState = ExportWorkState(items: queued)
        let summary = ExportSummaryState()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask { [weak self] in
                    guard let self else { return }
                    while let workItem = await workState.next() {
                        if await self.cancelled() {
                            await summary.incrementCancelled()
                            progress?(
                                ExportProgressSnapshot(
                                    sourcePath: workItem.item.asset.url.path,
                                    state: .cancelled,
                                    destinationPath: nil,
                                    errorMessage: nil,
                                    warningMessage: nil,
                                    bytesWritten: nil
                                )
                            )
                            continue
                        }

                        await self.processItem(
                            workItem.item,
                            sequenceIndex: workItem.sequenceIndex,
                            preset: preset,
                            destination: destination,
                            summary: summary,
                            progress: progress
                        )
                    }
                }
            }
            await group.waitForAll()
        }

        return await summary.snapshot(queuedCount: queued.count)
    }

    func cancel() {
        isCancelled = true
    }

    private func cancelled() -> Bool {
        isCancelled
    }

    private func processItem(
        _ item: ExportQueueItem,
        sequenceIndex: Int,
        preset: ExportPreset,
        destination: ExportDestinationOptions,
        summary: ExportSummaryState,
        progress: (@Sendable (ExportProgressSnapshot) -> Void)?
    ) async {
        do {
            progress?(
                ExportProgressSnapshot(
                    sourcePath: item.asset.url.path,
                    state: .rendering,
                    destinationPath: nil,
                    errorMessage: nil,
                    warningMessage: nil,
                    bytesWritten: nil
                )
            )

            let destinationRoot = try resolveDestinationRoot(destination: destination, sequenceIndex: sequenceIndex)
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

            progress?(
                ExportProgressSnapshot(
                    sourcePath: item.asset.url.path,
                    state: .writing,
                    destinationPath: nil,
                    errorMessage: nil,
                    warningMessage: nil,
                    bytesWritten: nil
                )
            )
            let output = try await renderAndWrite(asset: item.asset, preset: preset, destinationRoot: destinationRoot)
            await summary.incrementExported()
            await auditLogger.record(
                ExportAuditEntry(
                    createdAt: Date(),
                    sourcePath: item.asset.url.path,
                    destinationPath: output.url.path,
                    presetName: preset.name,
                    state: .done,
                    bytesWritten: output.bytesWritten,
                    warningMessage: output.warningMessage,
                    errorMessage: nil
                )
            )
            progress?(
                ExportProgressSnapshot(
                    sourcePath: item.asset.url.path,
                    state: .done,
                    destinationPath: output.url.path,
                    errorMessage: nil,
                    warningMessage: output.warningMessage,
                    bytesWritten: output.bytesWritten
                )
            )
        } catch {
            await summary.incrementFailed()
            let message = friendlyErrorMessage(error)
            await auditLogger.record(
                ExportAuditEntry(
                    createdAt: Date(),
                    sourcePath: item.asset.url.path,
                    destinationPath: nil,
                    presetName: preset.name,
                    state: .failed,
                    bytesWritten: nil,
                    warningMessage: nil,
                    errorMessage: message
                )
            )
            progress?(
                ExportProgressSnapshot(
                    sourcePath: item.asset.url.path,
                    state: .failed,
                    destinationPath: nil,
                    errorMessage: message,
                    warningMessage: nil,
                    bytesWritten: nil
                )
            )
        }
    }

    private func renderAndWrite(asset: PhotoAsset, preset: ExportPreset, destinationRoot: URL) async throws -> ExportRenderResult {
        let outputURL = uniqueDestinationURL(for: asset, preset: preset, in: destinationRoot)

        if preset.fileFormat == .original {
            try fileManager.copyItem(at: asset.url, to: outputURL)
            let bytes = (try? fileManager.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value
            return ExportRenderResult(url: outputURL, bytesWritten: bytes, warningMessage: nil)
        }

        guard let sourceImage = NSImage(contentsOf: asset.url) else {
            throw ExportFailure(message: "Could not decode source image for export.")
        }
        let settings = await adjustmentStore.adjustment(for: asset.url.path)
        let adjusted = await AdjustmentEngine.shared.apply(settings, to: sourceImage) ?? sourceImage
        let rendered = resizedImageIfNeeded(adjusted, longEdge: preset.longEdgePixels)
        await adjustmentStore.syncDerivedMetadataFromRendered(
            for: asset.url.path,
            renderedSize: rendered.size,
            settings: settings
        )
        let watermarked = preset.watermarkEnabled ? applyWatermark(rendered, text: preset.watermarkText) : rendered

        let encoded = try encodeImage(watermarked, preset: preset)
        try encoded.data.write(to: outputURL, options: [.atomic])
        return ExportRenderResult(url: outputURL, bytesWritten: Int64(encoded.data.count), warningMessage: encoded.warningMessage)
    }

    private func encodeImage(_ image: NSImage, preset: ExportPreset) throws -> (data: Data, warningMessage: String?) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExportFailure(message: "Could not create bitmap for export.")
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        let fileType: NSBitmapImageRep.FileType
        let canHonorTargetSize: Bool
        var warningMessage: String?
        switch preset.fileFormat {
        case .jpeg:
            fileType = .jpeg
            canHonorTargetSize = true
        case .heif:
            fileType = .jpeg
            canHonorTargetSize = true
            warningMessage = "HEIF encoding unavailable in current renderer; exported JPEG instead."
        case .tiff:
            fileType = .tiff
            canHonorTargetSize = false
        case .original:
            throw ExportFailure(message: "Unsupported original encode path.")
        }

        let targetBytes = preset.maxFileSizeKB > 0 ? preset.maxFileSizeKB * 1024 : 0
        if targetBytes > 0, canHonorTargetSize {
            var quality = max(0.35, min(1.0, preset.quality))
            var best: Data?
            while quality >= 0.35 {
                guard let encoded = bitmap.representation(
                    using: fileType,
                    properties: [
                        .compressionFactor: quality
                    ]
                ) else {
                    throw ExportFailure(message: "Failed to encode image data.")
                }
                best = encoded
                if encoded.count <= targetBytes {
                    return (encoded, warningMessage)
                }
                quality -= 0.08
            }
            guard let best else {
                throw ExportFailure(message: "Failed to encode image data.")
            }
            var warning = "Target size \(preset.maxFileSizeKB)KB not met; wrote \(best.count / 1024)KB."
            if let warningMessage {
                warning = "\(warningMessage) \(warning)"
            }
            return (best, warning)
        }

        let properties: [NSBitmapImageRep.PropertyKey: Any]
        if fileType == .jpeg {
            properties = [.compressionFactor: max(0.35, min(1.0, preset.quality))]
        } else {
            properties = [:]
        }
        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            throw ExportFailure(message: "Failed to encode image data.")
        }
        return (data, warningMessage)
    }

    private func resizedImageIfNeeded(_ image: NSImage, longEdge: Int) -> NSImage {
        guard longEdge > 0 else { return image }
        let sourceSize = image.size
        let maxDimension = max(sourceSize.width, sourceSize.height)
        guard maxDimension > CGFloat(longEdge) else { return image }

        let scale = CGFloat(longEdge) / maxDimension
        let targetSize = NSSize(width: floor(sourceSize.width * scale), height: floor(sourceSize.height * scale))
        let output = NSImage(size: targetSize)
        output.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1.0
        )
        output.unlockFocus()
        return output
    }

    private func applyWatermark(_ image: NSImage, text: String) -> NSImage {
        let watermark = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Darkroom" : text
        let output = NSImage(size: image.size)
        output.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)

        let fontSize = max(14, image.size.width * 0.025)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let attributed = NSAttributedString(string: watermark, attributes: attrs)
        let textSize = attributed.size()
        let padding: CGFloat = max(16, image.size.width * 0.02)
        let rect = NSRect(
            x: image.size.width - textSize.width - padding,
            y: padding,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: rect)
        output.unlockFocus()
        return output
    }

    private func resolveDestinationRoot(destination: ExportDestinationOptions, sequenceIndex: Int) throws -> URL {
        let basePath = destination.basePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !basePath.isEmpty else {
            throw ExportFailure(message: "Export base path is required.")
        }

        let template = destination.subfolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderTemplate = template.isEmpty ? "{date}-{shoot}" : template
        let dateString = Self.dateFormatter.string(from: Date())
        let sequenceString = String(format: "%04d", sequenceIndex)
        let shoot = sanitizedPathComponent(destination.shootName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Session" : destination.shootName)

        var resolved = folderTemplate
        resolved = resolved.replacingOccurrences(of: "{date}", with: dateString)
        resolved = resolved.replacingOccurrences(of: "{shoot}", with: shoot)
        resolved = resolved.replacingOccurrences(of: "{sequence}", with: sequenceString)

        return URL(fileURLWithPath: basePath, isDirectory: true)
            .appending(path: sanitizedPathComponent(resolved), directoryHint: .isDirectory)
    }

    private func uniqueDestinationURL(for asset: PhotoAsset, preset: ExportPreset, in directory: URL) -> URL {
        let sourceName = asset.filename
        let base = (sourceName as NSString).deletingPathExtension
        let sourceExt = (sourceName as NSString).pathExtension
        let ext = preset.fileFormat.fileExtension ?? sourceExt
        let normalizedExt = ext.isEmpty ? sourceExt : ext

        var suffix = 0
        while true {
            let filename: String
            if suffix == 0 {
                filename = normalizedExt.isEmpty ? base : "\(base).\(normalizedExt)"
            } else {
                filename = normalizedExt.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(normalizedExt)"
            }

            let candidate = directory.appending(path: filename, directoryHint: .notDirectory)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let exportError = error as? ExportFailure {
            return exportError.message
        }
        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteOutOfSpaceError:
            return "Disk is full. Free space at destination and retry."
        case NSFileWriteNoPermissionError, NSFileNoSuchFileError:
            return "Destination is unavailable or permission was denied."
        default:
            return nsError.localizedDescription
        }
    }

    private func sanitizedPathComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = raw.components(separatedBy: invalid).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        return joined.isEmpty ? "Untitled" : joined
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ExportRenderResult {
    let url: URL
    let bytesWritten: Int64?
    let warningMessage: String?
}

private actor ExportWorkState {
    private var items: [ExportQueueItem]
    private var currentIndex = 0

    init(items: [ExportQueueItem]) {
        self.items = items
    }

    func next() -> (item: ExportQueueItem, sequenceIndex: Int)? {
        guard currentIndex < items.count else { return nil }
        let sequence = currentIndex + 1
        defer { currentIndex += 1 }
        return (items[currentIndex], sequence)
    }
}

private actor ExportSummaryState {
    private var exported = 0
    private var failed = 0
    private var cancelled = 0

    func incrementExported() { exported += 1 }
    func incrementFailed() { failed += 1 }
    func incrementCancelled() { cancelled += 1 }

    func snapshot(queuedCount: Int) -> ExportRunSummary {
        ExportRunSummary(
            queuedCount: queuedCount,
            exportedCount: exported,
            failedCount: failed,
            cancelledCount: cancelled
        )
    }
}

private struct ExportAuditEntry: Codable {
    let createdAt: Date
    let sourcePath: String
    let destinationPath: String?
    let presetName: String
    let state: ExportItemState
    let bytesWritten: Int64?
    let warningMessage: String?
    let errorMessage: String?
}

private actor ExportAuditLogger {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func record(_ entry: ExportAuditEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        let logURL = auditLogURL()
        let parent = logURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logURL.path) {
            var line = data
            line.append(0x0a)
            try? line.write(to: logURL, options: [.atomic])
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0a]))
        } catch {
            return
        }
    }

    private func auditLogURL() -> URL {
        let logsDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: "Darkroom", directoryHint: .isDirectory)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Logs/Darkroom", directoryHint: .isDirectory)
        return logsDirectory.appending(path: "export-audit.jsonl", directoryHint: .notDirectory)
    }
}

struct ExportFailure: Error {
    let message: String
}
