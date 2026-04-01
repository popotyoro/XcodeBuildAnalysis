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
            let timingSummary = try analyzer.run()
            try write(timingSummary: timingSummary, to: configuration.outputPath)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n\n\(usageText)".utf8))
            Foundation.exit(EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func write(timingSummary: [TimingEntry], to outputPath: String?) throws {
        let encoder = JSONEncoder()
        if #available(macOS 10.15, *) {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        let data = try encoder.encode(timingSummary)
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
    let destination: String?
    let derivedDataPath: String?
    let outputPath: String?
    let helpRequested: Bool

    static func parse(arguments: [String]) throws -> CLIConfiguration {
        var project: String?
        var workspace: String?
        var scheme: String?
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
            destination: destination,
            derivedDataPath: derivedDataPath,
            outputPath: outputPath,
            helpRequested: false
        )
    }

    var xcodebuildArguments: [String] {
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

        arguments.append("clean")
        arguments.append("build")
        arguments.append("-showBuildTimingSummary")
        return arguments
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

    func run() throws -> [TimingEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = configuration.xcodebuildArguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let combinedOutput = String(decoding: outputData, as: UTF8.self)
        let parsedSummary = BuildTimingSummaryParser.parse(from: combinedOutput)
        return parsedSummary.entries
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
