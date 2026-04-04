#!/usr/bin/env swift

import Foundation

// MARK: - CLI Entry Point

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
            try write(report: report, configuration: configuration)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n\n\(usageText)".utf8))
            Foundation.exit(EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func write(report: AnalysisReport, configuration: CLIConfiguration) throws {
        let data: Data
        let message: String

        switch configuration.outputFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if #available(macOS 10.15, *) {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            } else {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            }
            data = try encoder.encode(report)
            message = "JSON report written to"
        case .html:
            let html = HTMLReportRenderer.render(report: report)
            data = Data(html.utf8)
            message = "HTML report written to"
        }

        if let outputPath = configuration.outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try data.write(to: url)
            FileHandle.standardError.write(Data("\(message) \(url.path)\n".utf8))
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
      --format, -f VALUE                 json | html, default: json
      --mode, -m VALUE                   both | clean | integration, default: both
      --runs, -n VALUE                   Number of measured runs, default: 3
      --compile-cache, -C VALUE          inherit | on | off, default: inherit
      --destination, -d VALUE            Simulator name or full xcodebuild destination
      --derived-data-path, -D VALUE      DerivedData output path
      --output, -o VALUE                 Output path, default: stdout
      --help, -h                         Show this help
    """
}

// MARK: - CLI Configuration

private struct CLIConfiguration {
    let project: String?
    let workspace: String?
    let scheme: String?
    let outputFormat: OutputFormat
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
        var outputFormat = OutputFormat.json
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
            case "--format", "-f":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedFormat = OutputFormat(rawValue: rawValue) else {
                    throw CLIError("invalid format: \(rawValue)")
                }
                outputFormat = parsedFormat
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
                outputFormat: outputFormat,
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
            outputFormat: outputFormat,
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

// MARK: - Build Execution

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
        return BuildMetadata(
            xcodeVersion: parseXcodeVersion(from: xcodeVersionOutput)
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

}

// MARK: - HTML Rendering

private enum HTMLReportRenderer {
    static func render(report: AnalysisReport) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let totals = report.runs.map { RunMetric(run: $0, totalDuration: $0.totalDurationSeconds) }
        let groupedRuns = Dictionary(grouping: totals, by: { $0.run.mode })
        let orderedGroups = BuildMode.displayOrder.compactMap { mode in
            groupedRuns[mode].map { (mode: mode, runs: $0.sorted(by: { $0.run.runIndex < $1.run.runIndex })) }
        }

        let sections = orderedGroups.map { group in
            let maxDuration = max(group.runs.map(\.totalDuration).max() ?? 0, 0.001)
            let average = group.runs.isEmpty ? 0.0 : group.runs.map(\.totalDuration).reduce(0, +) / Double(group.runs.count)
            let fastest = group.runs.min(by: { $0.totalDuration < $1.totalDuration })
            let slowest = group.runs.max(by: { $0.totalDuration < $1.totalDuration })

            let summaryCards = [
                """
                <div class="card">
                  <div class="eyebrow">AVERAGE</div>
                  <div class="metric">\(formatSeconds(average))</div>
                  <div class="caption">\(group.runs.count)回の平均合計時間</div>
                </div>
                """,
                fastest.map {
                    """
                    <div class="card">
                      <div class="eyebrow">BEST</div>
                      <div class="metric">\(formatSeconds($0.totalDuration))</div>
                      <div class="caption">\($0.run.runIndex)回目</div>
                    </div>
                    """
                } ?? "",
                slowest.map {
                    """
                    <div class="card">
                      <div class="eyebrow">WORST</div>
                      <div class="metric">\(formatSeconds($0.totalDuration))</div>
                      <div class="caption">\($0.run.runIndex)回目</div>
                    </div>
                    """
                } ?? ""
            ].joined(separator: "\n")

            let runCards = group.runs.map { metric in
                let topEntries = Array(metric.run.timingSummary.prefix(8))
                let topMax = max(topEntries.map(\.durationSeconds).max() ?? 0, 0.001)
                let chartBars = topEntries.isEmpty
                    ? "<p class=\"empty\">このrunでは timing summary を取得できませんでした。</p>"
                    : topEntries.map { entry in
                        let width = (entry.durationSeconds / topMax) * 100
                        return """
                        <div class="bar-row">
                          <div class="bar-label">\(escapeHTML(entry.name))</div>
                          <div class="bar-track"><div class="bar-fill" style="width: \(formatNumber(width))%;"></div></div>
                          <div class="bar-value">\(formatSeconds(entry.durationSeconds))</div>
                        </div>
                        """
                    }.joined(separator: "\n")

                let tableRows = metric.run.timingSummary.isEmpty
                    ? "<tr><td colspan=\"2\" class=\"empty-cell\">timing summary を取得できませんでした</td></tr>"
                    : metric.run.timingSummary.map { entry in
                        """
                        <tr>
                          <td>\(escapeHTML(entry.name))</td>
                          <td class="numeric">\(formatSeconds(entry.durationSeconds))</td>
                        </tr>
                        """
                    }.joined(separator: "\n")

                return """
                <article class="run-card" id="\(escapeHTML(metric.anchor))">
                  <div class="run-header">
                    <div>
                      <h3>\(escapeHTML(metric.title))</h3>
                      <p class="caption">Compile cache: \(escapeHTML(metric.run.compileCache.rawValue))</p>
                    </div>
                    <div class="total-pill">合計 \(formatSeconds(metric.totalDuration))</div>
                  </div>
                  <div class="chart-block">
                    <h4>主要タスク</h4>
                    \(chartBars)
                  </div>
                  <div class="table-block">
                    <h4>Timing Summary</h4>
                    <table>
                      <thead>
                        <tr>
                          <th>タスク</th>
                          <th class="numeric">秒</th>
                        </tr>
                      </thead>
                      <tbody>
                        \(tableRows)
                      </tbody>
                    </table>
                  </div>
                </article>
                """
            }.joined(separator: "\n")

            let comparisonRows = group.runs.map { metric in
                let width = (metric.totalDuration / maxDuration) * 100
                return """
                <div class="run-compare-row">
                  <a href="#\(escapeHTML(metric.anchor))" class="run-link">\(escapeHTML(metric.title))</a>
                  <div class="compare-track"><div class="compare-fill" style="width: \(formatNumber(width))%;"></div></div>
                  <div class="compare-value">\(formatSeconds(metric.totalDuration))</div>
                </div>
                """
            }.joined(separator: "\n")

            return """
            <section class="mode-section">
              <div class="section-heading">
                <h2>\(escapeHTML(group.mode.displayName))</h2>
                <p>\(group.runs.count)回計測</p>
              </div>
              <div class="mode-summary-grid">
                \(summaryCards)
              </div>
              <div class="comparison-card">
                <h3>Run比較</h3>
                \(comparisonRows)
              </div>
              <div class="runs-grid">
                \(runCards)
              </div>
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Xcode Build Analysis</title>
          <style>
            :root {
              --ink: #10212b;
              --muted: #5c6c76;
              --line: #d3dde3;
              --paper: #f4efe7;
              --panel: rgba(255,255,255,0.82);
              --brand: #d55d3f;
              --brand-soft: #f4c7b8;
              --accent: #1f7a8c;
              --shadow: 0 18px 45px rgba(16, 33, 43, 0.12);
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: "Avenir Next", "Helvetica Neue", sans-serif;
              color: var(--ink);
              background:
                radial-gradient(circle at top left, rgba(213, 93, 63, 0.18), transparent 30%),
                radial-gradient(circle at top right, rgba(31, 122, 140, 0.16), transparent 28%),
                linear-gradient(180deg, #fbf7f2, var(--paper));
            }
            .page {
              max-width: 1280px;
              margin: 0 auto;
              padding: 40px 20px 64px;
            }
            .hero, .comparison-card, .run-card, .card {
              background: var(--panel);
              backdrop-filter: blur(12px);
              border: 1px solid rgba(255,255,255,0.55);
              box-shadow: var(--shadow);
            }
            .hero {
              border-radius: 28px;
              padding: 28px;
              margin-bottom: 24px;
            }
            .hero h1 {
              margin: 0 0 8px;
              font-size: clamp(32px, 5vw, 54px);
              letter-spacing: -0.03em;
            }
            .hero p {
              margin: 0;
              color: var(--muted);
              font-size: 15px;
              line-height: 1.6;
            }
            .meta-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
              gap: 16px;
              margin-top: 22px;
            }
            .mode-summary-grid {
              display: grid;
              grid-template-columns: repeat(3, minmax(0, 1fr));
              gap: 16px;
              margin: 0 0 16px;
            }
            .card {
              border-radius: 22px;
              padding: 18px;
              min-width: 0;
            }
            .eyebrow {
              text-transform: uppercase;
              letter-spacing: 0.1em;
              font-size: 11px;
              color: var(--muted);
              margin-bottom: 10px;
            }
            .metric {
              font-size: 28px;
              font-weight: 700;
              letter-spacing: -0.03em;
            }
            .caption {
              margin: 6px 0 0;
              color: var(--muted);
              font-size: 13px;
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            .mode-section {
              margin-top: 36px;
            }
            .hero-copy {
              display: none;
            }
            .section-heading {
              display: flex;
              justify-content: space-between;
              gap: 12px;
              align-items: baseline;
              margin-bottom: 14px;
            }
            .section-heading h2 {
              margin: 0;
              font-size: 28px;
            }
            .section-heading p {
              margin: 0;
              color: var(--muted);
            }
            .comparison-card {
              border-radius: 22px;
              padding: 20px;
              margin-bottom: 16px;
            }
            .comparison-card h3, .chart-block h4, .table-block h4 {
              margin: 0 0 14px;
              font-size: 16px;
            }
            .run-compare-row, .bar-row {
              display: grid;
              grid-template-columns: minmax(120px, 220px) 1fr 80px;
              gap: 12px;
              align-items: center;
              margin-bottom: 10px;
            }
            .run-link {
              color: var(--ink);
              text-decoration: none;
              font-weight: 600;
            }
            .compare-track, .bar-track {
              background: rgba(16, 33, 43, 0.08);
              border-radius: 999px;
              overflow: hidden;
              min-height: 12px;
            }
            .compare-fill {
              min-height: 12px;
              border-radius: 999px;
              background: linear-gradient(90deg, var(--brand), #f08f74);
            }
            .bar-fill {
              min-height: 10px;
              border-radius: 999px;
              background: linear-gradient(90deg, var(--accent), #58b6b3);
            }
            .compare-value, .bar-value, .numeric {
              text-align: right;
              font-variant-numeric: tabular-nums;
            }
            .runs-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
              gap: 18px;
            }
            .run-card {
              border-radius: 24px;
              padding: 20px;
            }
            .run-header {
              display: flex;
              justify-content: space-between;
              align-items: start;
              gap: 12px;
              margin-bottom: 18px;
            }
            .run-header h3 {
              margin: 0 0 4px;
              font-size: 22px;
            }
            .total-pill {
              padding: 10px 14px;
              border-radius: 999px;
              background: rgba(213, 93, 63, 0.12);
              color: var(--brand);
              font-weight: 700;
              white-space: nowrap;
            }
            .chart-block {
              margin-bottom: 20px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 14px;
            }
            th, td {
              padding: 10px 8px;
              border-bottom: 1px solid var(--line);
              vertical-align: top;
            }
            th {
              text-align: left;
              font-size: 12px;
              color: var(--muted);
              text-transform: uppercase;
              letter-spacing: 0.06em;
            }
            .empty, .empty-cell {
              color: var(--muted);
            }
            @media (max-width: 720px) {
              .page { padding: 24px 14px 48px; }
              .mode-summary-grid {
                grid-template-columns: 1fr;
              }
              .run-compare-row, .bar-row {
                grid-template-columns: 1fr;
              }
              .compare-value, .bar-value, .numeric {
                text-align: left;
              }
              .run-header {
                flex-direction: column;
              }
            }
          </style>
        </head>
        <body>
          <main class="page">
            <section class="hero">
              <div class="eyebrow">Xcode Build Analysis</div>
              <h1>\(escapeHTML(report.scheme))</h1>
              <p class="hero-copy"></p>
              <div class="meta-grid">
                <div class="card">
                  <div class="eyebrow">プロジェクト</div>
                  <div class="metric">\(escapeHTML(lastPathComponent(report.project)))</div>
                  <div class="caption">\(escapeHTML(report.project))</div>
                </div>
                <div class="card">
                  <div class="eyebrow">実行日時</div>
                  <div class="metric">\(escapeHTML(dateFormatter.string(from: report.executedAt)))</div>
                </div>
                <div class="card">
                  <div class="eyebrow">Xcode</div>
                  <div class="metric">\(escapeHTML(report.xcodeVersion))</div>
                </div>
              </div>
            </section>
            \(sections)
          </main>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func formatSeconds(_ value: Double) -> String {
        "\(formatNumber(value))s"
    }

    private static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.3f", value)
    }

    private static func lastPathComponent(_ value: String) -> String {
        URL(fileURLWithPath: value).lastPathComponent
    }
}

// MARK: - Build Timing Summary Parsing

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

// MARK: - Supporting Types

private enum OutputFormat: String {
    case json
    case html
}

private enum BuildMode: String, Encodable {
    case both
    case clean
    case integration

    static let displayOrder: [BuildMode] = [.clean, .integration]

    var displayName: String {
        switch self {
        case .both:
            return "両方"
        case .clean:
            return "Clean Build"
        case .integration:
            return "Integration Build"
        }
    }
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

    var totalDurationSeconds: Double {
        timingSummary.map(\.durationSeconds).reduce(0, +)
    }
}

private struct AnalysisReport: Encodable {
    let project: String
    let executedAt: Date
    let xcodeVersion: String
    let scheme: String
    let runs: [RunResult]
}

private struct RunMetric {
    let run: RunResult
    let totalDuration: Double

    var title: String {
        "\(run.mode.displayName) \(run.runIndex)回目"
    }

    var anchor: String {
        "\(run.mode.rawValue)-run-\(run.runIndex)"
    }
}

private struct BuildMetadata {
    let xcodeVersion: String
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
