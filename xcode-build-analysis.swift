#!/usr/bin/env swift

import Foundation

struct XcodeBuildAnalysisCLI {
    static func main() {
        do {
            let configuration = try CLIConfiguration.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            if configuration.helpRequested {
                FileHandle.standardOutput.write(Data(usageText.utf8))
                return
            }

            let analyzer = XcodeBuildAnalyzer(configuration: configuration)
            let report = try analyzer.run()
            try write(report: report, to: configuration.outputPath)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n\n\(usageText)".utf8))
            Foundation.exit(EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func write(report: AnalysisReport, to outputPath: String?) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if #available(macOS 10.15, *) {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        let data = try encoder.encode(report)
        if let outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try data.write(to: url)
            FileHandle.standardError.write(Data("JSON report written to \(url.path)\n".utf8))
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static let usageText = """
    Usage:
      swift xcode-build-analysis.swift --project App.xcodeproj --scheme App [options]
      swift xcode-build-analysis.swift --workspace App.xcworkspace --scheme App [options]
      swift xcode-build-analysis.swift -p App.xcodeproj -s App [options]
      swift xcode-build-analysis.swift -w App.xcworkspace -s App [options]

    Required:
      --project, -p VALUE or --workspace, -w VALUE
      --scheme, -s VALUE                 Scheme to build

    Options:
      --project, -p VALUE                Path to .xcodeproj
      --workspace, -w VALUE              Path to .xcworkspace
      --scheme, -s VALUE                 Scheme to build
      --mode, -m VALUE                   both | clean | integration, default: both
      --runs, -n VALUE                   Number of measured runs, default: 3
      --compile-cache, -C VALUE          inherit | on | off, default: inherit
      --destination, -d VALUE            Simulator name or full xcodebuild destination
      --derived-data-path, -D VALUE      DerivedData output path
      --output, -o VALUE                 JSON output path, default: stdout
      --help, -h                         Show this help
    """
}

private struct CLIConfiguration {
    let project: String?
    let workspace: String?
    let scheme: String?
    let mode: BuildMode
    let runs: Int
    let compileCacheMode: CompileCacheMode
    let destination: String?
    let derivedDataPath: String?
    let outputPath: String?
    let helpRequested: Bool

    static func parse(arguments: [String]) throws -> CLIConfiguration {
        var project: String?
        var workspace: String?
        var scheme: String?
        var mode = BuildMode.both
        var runs = 3
        var compileCacheMode = CompileCacheMode.inherit
        var destination: String?
        var derivedDataPath: String?
        var outputPath: String?
        var helpRequested = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            if argument == "--" {
                throw CLIError("pass-through arguments are not supported")
            }

            switch argument {
            case "--help", "-h":
                helpRequested = true
            case "--project", "-p":
                project = try value(after: &index, in: arguments, for: argument)
            case "--workspace", "-w":
                workspace = try value(after: &index, in: arguments, for: argument)
            case "--scheme", "-s":
                scheme = try value(after: &index, in: arguments, for: argument)
            case "--mode", "-m":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedMode = BuildMode(rawValue: rawValue) else {
                    throw CLIError("invalid mode: \(rawValue)")
                }
                mode = parsedMode
            case "--runs", "-n":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedRuns = Int(rawValue), parsedRuns >= 1 else {
                    throw CLIError("--runs must be an integer greater than or equal to 1")
                }
                runs = parsedRuns
            case "--compile-cache", "-C":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedCacheMode = CompileCacheMode(rawValue: rawValue) else {
                    throw CLIError("invalid compile cache mode: \(rawValue)")
                }
                compileCacheMode = parsedCacheMode
            case "--destination", "-d":
                destination = try value(after: &index, in: arguments, for: argument)
            case "--derived-data-path", "-D":
                derivedDataPath = try value(after: &index, in: arguments, for: argument)
            case "--output", "-o":
                outputPath = try value(after: &index, in: arguments, for: argument)
            default:
                throw CLIError("unknown argument: \(argument)")
            }

            index += 1
        }

        if helpRequested {
            return CLIConfiguration(
                project: project,
                workspace: workspace,
                scheme: scheme,
                mode: mode,
                runs: runs,
                compileCacheMode: compileCacheMode,
                destination: destination,
                derivedDataPath: derivedDataPath,
                outputPath: outputPath,
                helpRequested: true
            )
        }

        if project == nil && workspace == nil {
            throw CLIError("either --project or --workspace is required")
        }
        if project != nil && workspace != nil {
            throw CLIError("use only one of --project or --workspace")
        }
        if scheme == nil {
            throw CLIError("--scheme is required")
        }

        return CLIConfiguration(
            project: project,
            workspace: workspace,
            scheme: scheme,
            mode: mode,
            runs: runs,
            compileCacheMode: compileCacheMode,
            destination: destination,
            derivedDataPath: derivedDataPath,
            outputPath: outputPath,
            helpRequested: false
        )
    }

    func baseXcodebuildArguments(includeClean: Bool) -> [String] {
        var arguments: [String] = []
        if let project {
            arguments.append(contentsOf: ["-project", project])
        }
        if let workspace {
            arguments.append(contentsOf: ["-workspace", workspace])
        }
        if let scheme {
            arguments.append(contentsOf: ["-scheme", scheme])
        }
        if let destination {
            arguments.append(contentsOf: ["-destination", normalizedDestination(destination)])
        }
        if let derivedDataPath {
            arguments.append(contentsOf: ["-derivedDataPath", derivedDataPath])
        }
        if let cacheOverride = compileCacheMode.buildSettingOverride {
            arguments.append(cacheOverride)
        }
        if includeClean {
            arguments.append("clean")
        }
        arguments.append("build")
        arguments.append("-showBuildTimingSummary")
        return arguments
    }

    var buildSettingsArguments: [String] {
        var arguments: [String] = []
        if let project {
            arguments.append(contentsOf: ["-project", project])
        }
        if let workspace {
            arguments.append(contentsOf: ["-workspace", workspace])
        }
        if let scheme {
            arguments.append(contentsOf: ["-scheme", scheme])
        }
        if let destination {
            arguments.append(contentsOf: ["-destination", normalizedDestination(destination)])
        }
        arguments.append("-showBuildSettings")
        return arguments
    }

    var selectedModes: [BuildMode] {
        switch mode {
        case .both:
            return [.clean, .integration]
        case .clean:
            return [.clean]
        case .integration:
            return [.integration]
        }
    }

    private func normalizedDestination(_ value: String) -> String {
        if value.contains("=") || value.contains(",") {
            return value
        }
        return "platform=iOS Simulator,name=\(value)"
    }

    private static func value(after index: inout Int, in arguments: [String], for option: String) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw CLIError("missing value for \(option)")
        }
        index = nextIndex
        return arguments[nextIndex]
    }
}

private struct XcodeBuildAnalyzer {
    let configuration: CLIConfiguration

    func run() throws -> AnalysisReport {
        let metadata = try fetchMetadata()
        var results: [RunResult] = []

        for mode in configuration.selectedModes {
            if mode == .integration {
                _ = try runXcodebuild(arguments: configuration.baseXcodebuildArguments(includeClean: true))
            }

            for runIndex in 1...configuration.runs {
                let includeClean = mode == .clean
                let output = try runXcodebuild(arguments: configuration.baseXcodebuildArguments(includeClean: includeClean))
                let parsedSummary = BuildTimingSummaryParser.parse(from: output)

                results.append(
                    RunResult(
                        mode: mode,
                        runIndex: runIndex,
                        compileCache: configuration.compileCacheMode,
                        timingSummary: parsedSummary.entries
                    )
                )
            }
        }

        return AnalysisReport(
            project: configuration.project ?? configuration.workspace ?? "",
            executedAt: Date(),
            xcodeVersion: metadata.xcodeVersion,
            sdkVersion: metadata.sdkVersion,
            scheme: configuration.scheme ?? "",
            runs: results
        )
    }

    private func runXcodebuild(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: outputData, as: UTF8.self)
    }

    private func fetchMetadata() throws -> BuildMetadata {
        let xcodeVersionOutput = try runProcess(arguments: ["-version"])
        let buildSettingsOutput = try runXcodebuild(arguments: configuration.buildSettingsArguments)

        return BuildMetadata(
            xcodeVersion: parseXcodeVersion(from: xcodeVersionOutput),
            sdkVersion: parseBuildSetting(named: "SDK_VERSION", from: buildSettingsOutput) ?? "unknown"
        )
    }

    private func runProcess(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: outputData, as: UTF8.self)
    }

    private func parseXcodeVersion(from output: String) -> String {
        let lines = output.split(separator: "\n").map(String.init)
        let versionLine = lines.first ?? ""
        let buildLine = lines.dropFirst().first ?? ""
        return buildLine.isEmpty ? versionLine : "\(versionLine) (\(buildLine))"
    }

    private func parseBuildSetting(named name: String, from output: String) -> String? {
        let prefix = "\(name) = "
        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return nil
    }
}

private enum BuildTimingSummaryParser {
    static func parse(from output: String) -> (entries: [TimingEntry], rawLines: [String]) {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard let headerIndex = lines.lastIndex(where: { $0.contains("Build Timing Summary") }) else {
            return ([], [])
        }

        let candidateLines = Array(lines[(headerIndex + 1)...]).drop(while: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || Set(trimmed).isSubset(of: ["="])
        })

        var entries: [TimingEntry] = []
        var rawLines: [String] = []

        for line in candidateLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            rawLines.append(trimmed)

            if let entry = parseLine(trimmed) {
                entries.append(entry)
            }
        }

        return (entries, rawLines)
    }

    private static func parseLine(_ line: String) -> TimingEntry? {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("|") {
            let parts = normalized.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if parts.count == 2,
               let duration = parseSeconds(parts[1]) {
                return TimingEntry(name: parts[0], durationSeconds: duration)
            }
        }

        let parts = normalized.split(separator: " ").map(String.init)
        if let first = parts.first,
           let duration = Double(first),
           normalized.contains("seconds") {
            let name = normalized
                .replacingOccurrences(of: first, with: "", options: [], range: normalized.range(of: first))
                .replacingOccurrences(of: "seconds", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return TimingEntry(name: name, durationSeconds: duration)
            }
        }

        return nil
    }

    private static func parseSeconds(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: "seconds", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }
}

private enum BuildMode: String, Encodable {
    case both
    case clean
    case integration
}

private enum CompileCacheMode: String, Encodable {
    case inherit
    case on
    case off

    var buildSettingOverride: String? {
        switch self {
        case .inherit:
            return nil
        case .on:
            return "COMPILATION_CACHE_ENABLE_CACHING=YES"
        case .off:
            return "COMPILATION_CACHE_ENABLE_CACHING=NO"
        }
    }
}

private struct RunResult: Encodable {
    let mode: BuildMode
    let runIndex: Int
    let compileCache: CompileCacheMode
    let timingSummary: [TimingEntry]
}

private struct AnalysisReport: Encodable {
    let project: String
    let executedAt: Date
    let xcodeVersion: String
    let sdkVersion: String
    let scheme: String
    let runs: [RunResult]
}

private struct BuildMetadata {
    let xcodeVersion: String
    let sdkVersion: String
}

private struct TimingEntry: Encodable {
    let name: String
    let durationSeconds: Double
}

private struct CLIError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

XcodeBuildAnalysisCLI.main()
