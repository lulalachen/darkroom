import Foundation

actor FinderTagManager {
    private let greenTagName = "Green"
    private let grayTagName = "Gray"
    private let redTagName = "Red"
    private let colorTagNames: Set<String> = ["Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange"]

    func applyTag(for appTag: PhotoTag, to fileURL: URL) throws {
        let keys: Set<URLResourceKey> = [.tagNamesKey]
        let values = try fileURL.resourceValues(forKeys: keys)

        var tagNames = (values.tagNames ?? []).filter { tagName in
            !colorTagNames.contains(where: { $0.caseInsensitiveCompare(tagName) == .orderedSame })
        }
        let finderTagName = finderTagName(for: appTag)
        if !tagNames.contains(where: { $0.caseInsensitiveCompare(finderTagName) == .orderedSame }) {
            tagNames.append(finderTagName)
        }

        let nsURL = fileURL as NSURL
        try nsURL.setResourceValue(tagNames, forKey: .tagNamesKey)
    }

    func clearColorTags(for fileURL: URL) throws {
        let keys: Set<URLResourceKey> = [.tagNamesKey]
        let values = try fileURL.resourceValues(forKeys: keys)
        let cleaned = (values.tagNames ?? []).filter { tagName in
            !colorTagNames.contains(where: { $0.caseInsensitiveCompare(tagName) == .orderedSame })
        }

        let nsURL = fileURL as NSURL
        try nsURL.setResourceValue(cleaned, forKey: .tagNamesKey)
    }

    func tagMap(for assets: [PhotoAsset]) -> [PhotoAsset.ID: PhotoTag] {
        var result: [PhotoAsset.ID: PhotoTag] = [:]
        for asset in assets {
            if let tag = appTag(for: asset.url) {
                result[asset.id] = tag
            }
        }
        return result
    }

    private func appTag(for fileURL: URL) -> PhotoTag? {
        let keys: Set<URLResourceKey> = [.tagNamesKey]
        guard let values = try? fileURL.resourceValues(forKeys: keys) else {
            return nil
        }

        let tagNames = values.tagNames ?? []
        if tagNames.contains(where: { $0.caseInsensitiveCompare(greenTagName) == .orderedSame }) {
            return .keep
        }
        if tagNames.contains(where: { $0.caseInsensitiveCompare(grayTagName) == .orderedSame }) {
            return .keep
        }
        if tagNames.contains(where: { $0.caseInsensitiveCompare(redTagName) == .orderedSame }) {
            return .reject
        }
        return nil
    }

    private func finderTagName(for appTag: PhotoTag) -> String {
        switch appTag {
        case .keep:
            return greenTagName
        case .reject:
            return redTagName
        }
    }
}
