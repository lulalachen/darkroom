import Foundation
import PackagePlugin

@main
struct BundleAppPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let configuration = Self.parseConfiguration(arguments)
        let scriptPath = context.package.directory.appending("build-app.sh").string

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            throw BundleAppPluginError.message("Missing executable script at \(scriptPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, configuration]
        process.currentDirectoryURL = URL(fileURLWithPath: context.package.directory.string)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BundleAppPluginError.message("build-app.sh failed with status \(process.terminationStatus)")
        }
    }

    private static func parseConfiguration(_ arguments: [String]) -> String {
        if arguments.contains("release") {
            return "release"
        }
        if arguments.contains("debug") {
            return "debug"
        }
        if let index = arguments.firstIndex(of: "--configuration"), arguments.indices.contains(index + 1) {
            let value = arguments[index + 1]
            if value == "debug" || value == "release" {
                return value
            }
        }
        return "debug"
    }
}

enum BundleAppPluginError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}
