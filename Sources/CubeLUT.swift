import CryptoKit
import Foundation
import simd

enum CubeLUTParseError: Error, LocalizedError {
    case invalidHeader(String)
    case missingSize
    case invalidDomain
    case invalidEntryCount(expected: Int, actual: Int)
    case invalidEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidHeader(let line):
            return "Invalid .cube header line: \(line)"
        case .missingSize:
            return "Missing LUT_3D_SIZE declaration."
        case .invalidDomain:
            return "Invalid DOMAIN_MIN/DOMAIN_MAX declaration."
        case .invalidEntryCount(let expected, let actual):
            return "Invalid LUT entry count. Expected \(expected), got \(actual)."
        case .invalidEntry(let line):
            return "Invalid LUT entry: \(line)"
        }
    }
}

struct CubeLUT {
    let title: String?
    let dimension: Int
    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>
    let data: Data
}

enum CubeLUTParser {
    static func parse(_ content: String) throws -> CubeLUT {
        var title: String?
        var dimension: Int?
        var domainMin = SIMD3<Float>(repeating: 0)
        var domainMax = SIMD3<Float>(repeating: 1)
        var entries: [SIMD3<Float>] = []

        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("TITLE") {
                title = parseTitle(trimmed)
                continue
            }
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let tokens = tokensWithoutComments(trimmed)
                guard tokens.count == 2, let value = Int(tokens[1]), value > 1 else {
                    throw CubeLUTParseError.invalidHeader(trimmed)
                }
                dimension = value
                continue
            }
            if trimmed.hasPrefix("DOMAIN_MIN") {
                let tokens = tokensWithoutComments(trimmed)
                guard tokens.count == 4,
                      let x = Float(tokens[1]),
                      let y = Float(tokens[2]),
                      let z = Float(tokens[3]) else {
                    throw CubeLUTParseError.invalidDomain
                }
                domainMin = SIMD3<Float>(x, y, z)
                continue
            }
            if trimmed.hasPrefix("DOMAIN_MAX") {
                let tokens = tokensWithoutComments(trimmed)
                guard tokens.count == 4,
                      let x = Float(tokens[1]),
                      let y = Float(tokens[2]),
                      let z = Float(tokens[3]) else {
                    throw CubeLUTParseError.invalidDomain
                }
                domainMax = SIMD3<Float>(x, y, z)
                continue
            }

            let tokens = tokensWithoutComments(trimmed)
            guard tokens.count >= 3,
                  let r = Float(tokens[0]),
                  let g = Float(tokens[1]),
                  let b = Float(tokens[2]) else {
                throw CubeLUTParseError.invalidEntry(trimmed)
            }
            entries.append(SIMD3<Float>(r, g, b))
        }

        guard let dimension else { throw CubeLUTParseError.missingSize }
        guard domainMax.x > domainMin.x, domainMax.y > domainMin.y, domainMax.z > domainMin.z else {
            throw CubeLUTParseError.invalidDomain
        }

        let expectedCount = dimension * dimension * dimension
        guard entries.count == expectedCount else {
            throw CubeLUTParseError.invalidEntryCount(expected: expectedCount, actual: entries.count)
        }

        var rgbaFloats: [Float] = []
        rgbaFloats.reserveCapacity(expectedCount * 4)
        for entry in entries {
            rgbaFloats.append(entry.x)
            rgbaFloats.append(entry.y)
            rgbaFloats.append(entry.z)
            rgbaFloats.append(1.0)
        }
        let data = rgbaFloats.withUnsafeBufferPointer { buffer in
            Data(buffer: UnsafeBufferPointer(start: buffer.baseAddress, count: buffer.count))
        }
        return CubeLUT(
            title: title,
            dimension: dimension,
            domainMin: domainMin,
            domainMax: domainMax,
            data: data
        )
    }

    static func checksumSHA256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func parseTitle(_ line: String) -> String? {
        let parts = line.split(separator: "\"")
        guard parts.count >= 2 else { return nil }
        return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokensWithoutComments(_ line: String) -> [String] {
        let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring(line)
        return content.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
