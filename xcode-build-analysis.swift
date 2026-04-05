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
            if error.showsUsage {
                FileHandle.standardError.write(Data("error: \(error.message)\n\n\(usageText)".utf8))
            } else {
                FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
            }
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
      --skip-warm-up                     Skip the unmeasured warm-up build
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
    let skipWarmUp: Bool
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
        var skipWarmUp = false
        var compileCacheMode = CompileCacheMode.inherit
        var destination: String?
        var derivedDataPath: String?
        var outputPath: String?
        var helpRequested = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            if argument == "--" {
                throw CLIError.usage("pass-through arguments are not supported")
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
                    throw CLIError.usage("invalid format: \(rawValue)")
                }
                outputFormat = parsedFormat
            case "--mode", "-m":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedMode = BuildMode(rawValue: rawValue) else {
                    throw CLIError.usage("invalid mode: \(rawValue)")
                }
                mode = parsedMode
            case "--runs", "-n":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedRuns = Int(rawValue), parsedRuns >= 1 else {
                    throw CLIError.usage("--runs must be an integer greater than or equal to 1")
                }
                runs = parsedRuns
            case "--skip-warm-up":
                skipWarmUp = true
            case "--compile-cache", "-C":
                let rawValue = try value(after: &index, in: arguments, for: argument)
                guard let parsedCacheMode = CompileCacheMode(rawValue: rawValue) else {
                    throw CLIError.usage("invalid compile cache mode: \(rawValue)")
                }
                compileCacheMode = parsedCacheMode
            case "--destination", "-d":
                destination = try value(after: &index, in: arguments, for: argument)
            case "--derived-data-path", "-D":
                derivedDataPath = try value(after: &index, in: arguments, for: argument)
            case "--output", "-o":
                outputPath = try value(after: &index, in: arguments, for: argument)
            default:
                throw CLIError.usage("unknown argument: \(argument)")
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
                skipWarmUp: skipWarmUp,
                compileCacheMode: compileCacheMode,
                destination: destination,
                derivedDataPath: derivedDataPath,
                outputPath: outputPath,
                helpRequested: true
            )
        }

        if project == nil && workspace == nil {
            throw CLIError.usage("either --project or --workspace is required")
        }
        if project != nil && workspace != nil {
            throw CLIError.usage("use only one of --project or --workspace")
        }
        if scheme == nil {
            throw CLIError.usage("--scheme is required")
        }

        return CLIConfiguration(
            project: project,
            workspace: workspace,
            scheme: scheme,
            outputFormat: outputFormat,
            mode: mode,
            runs: runs,
            skipWarmUp: skipWarmUp,
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
            throw CLIError.usage("missing value for \(option)")
        }
        index = nextIndex
        return arguments[nextIndex]
    }
}

// MARK: - Build Execution

private struct XcodeBuildAnalyzer {
    let configuration: CLIConfiguration

    func run() throws -> AnalysisReport {
        let xcodeVersion = try fetchXcodeVersion()
        var results: [RunResult] = []

        for mode in configuration.selectedModes {
            let warmUpArguments = configuration.baseXcodebuildArguments(includeClean: true)
            let measuredArguments = configuration.baseXcodebuildArguments(includeClean: mode == .clean)

            if mode == .clean && !configuration.skipWarmUp {
                _ = try runXcodebuild(arguments: warmUpArguments)
            }

            if mode == .integration {
                _ = try runXcodebuild(arguments: warmUpArguments)
            }

            for runIndex in 1...configuration.runs {
                let output = try runXcodebuild(arguments: measuredArguments)
                let entries = BuildTimingSummaryParser.parse(from: output)

                results.append(
                    RunResult(
                        mode: mode,
                        runIndex: runIndex,
                        compileCache: configuration.compileCacheMode,
                        timingSummary: entries
                    )
                )
            }
        }

        return AnalysisReport(
            project: configuration.project ?? configuration.workspace ?? "",
            executedAt: Date(),
            xcodeVersion: xcodeVersion,
            scheme: configuration.scheme ?? "",
            stabilitySummaries: StabilityAnalyzer.summaries(for: results),
            runs: results
        )
    }

    private func runXcodebuild(arguments: [String]) throws -> String {
        let result = try ProcessRunner.run(executablePath: "/usr/bin/xcodebuild", arguments: arguments)
        guard result.exitCode == 0 else {
            throw CLIError(processFailureMessage(for: result, command: "xcodebuild"))
        }
        return result.output
    }

    private func fetchXcodeVersion() throws -> String {
        let xcodeVersionOutput = try runProcess(arguments: ["-version"])
        return parseXcodeVersion(from: xcodeVersionOutput)
    }

    private func runProcess(arguments: [String]) throws -> String {
        let result = try ProcessRunner.run(executablePath: "/usr/bin/xcodebuild", arguments: arguments)
        guard result.exitCode == 0 else {
            throw CLIError(processFailureMessage(for: result, command: "xcodebuild"))
        }
        return result.output
    }

    private func parseXcodeVersion(from output: String) -> String {
        let lines = output.split(separator: "\n").map(String.init)
        let versionLine = lines.first ?? ""
        let buildLine = lines.dropFirst().first ?? ""
        return buildLine.isEmpty ? versionLine : "\(versionLine) (\(buildLine))"
    }

    private func processFailureMessage(for result: ProcessRunner.Result, command: String) -> String {
        let excerpt = result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(8)
            .joined(separator: "\n")

        if excerpt.isEmpty {
            return "\(command) failed with exit code \(result.exitCode)"
        }

        return "\(command) failed with exit code \(result.exitCode)\n\(excerpt)"
    }

}

// MARK: - HTML Rendering

private enum HTMLReportRenderer {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.minimumIntegerDigits = 1
        return formatter
    }()

    static func render(report: AnalysisReport) -> String {
        let totals = report.runs.map { RunMetric(run: $0, totalDuration: $0.totalDurationSeconds) }
        let groupedRuns = Dictionary(grouping: totals, by: { $0.run.mode })
        let groupedStability = Dictionary(uniqueKeysWithValues: report.stabilitySummaries.map { ($0.mode, $0) })
        let orderedGroups = BuildMode.displayOrder.compactMap { mode in
            groupedRuns[mode].map { (mode: mode, runs: $0.sorted(by: { $0.run.runIndex < $1.run.runIndex })) }
        }

        let sections = orderedGroups.map { group in
            let maxDuration = max(group.runs.map(\.totalDuration).max() ?? 0, 0.001)
            let totalDurations = group.runs.map(\.totalDuration)
            let average = totalDurations.isEmpty ? 0.0 : totalDurations.reduce(0, +) / Double(totalDurations.count)
            let fastest = group.runs.min(by: { $0.totalDuration < $1.totalDuration })
            let slowest = group.runs.max(by: { $0.totalDuration < $1.totalDuration })
            let stability = groupedStability[group.mode]

            let summaryCards = [
                """
                <div class="card">
                  <div class="eyebrow">AVERAGE</div>
                  <div class="metric">\(formatSeconds(average))</div>
                </div>
                """,
                fastest.map {
                    """
                    <div class="card">
                      <div class="eyebrow">BEST | \($0.run.runIndex)回目の計測結果</div>
                      <div class="metric">\(formatSeconds($0.totalDuration))</div>
                    </div>
                    """
                } ?? "",
                slowest.map {
                    """
                    <div class="card">
                      <div class="eyebrow">WORST | \($0.run.runIndex)回目の計測結果</div>
                      <div class="metric">\(formatSeconds($0.totalDuration))</div>
                    </div>
                    """
                } ?? ""
            ].joined(separator: "\n")

            let stabilityCard = stability.map {
                """
                <div class="stability-card stability-\($0.status.rawValue)">
                  <div class="stability-head">
                    <div class="eyebrow">STABILITY</div>
                    <div class="stability-badge">\($0.status.displayName)</div>
                  </div>
                  <div class="stability-grid">
                    <div>
                      <div class="stability-label">CV</div>
                      <div class="stability-value">\(formatPercent($0.coefficientOfVariation))</div>
                    </div>
                    <div>
                      <div class="stability-label">標準偏差</div>
                      <div class="stability-value">\(formatSeconds($0.standardDeviationSeconds))</div>
                    </div>
                    <div>
                      <div class="stability-label">平均</div>
                      <div class="stability-value">\(formatSeconds($0.meanSeconds))</div>
                    </div>
                    <div>
                      <div class="stability-label">サンプル数</div>
                      <div class="stability-value">\($0.sampleCount)</div>
                    </div>
                  </div>
                  <p class="stability-message">\(escapeHTML($0.message))</p>
                </div>
                """
            } ?? ""

            let runCards = group.runs.map { metric in
                let topEntries = Array(metric.run.timingSummary.prefix(8))
                let topMax = max(topEntries.map(\.durationSeconds).max() ?? 0, 0.001)
                let chartBars = topEntries.isEmpty
                    ? "<p class=\"empty\">このrunでは timing summary を取得できませんでした。</p>"
                    : topEntries.map { entry in
                        let width = (entry.durationSeconds / topMax) * 100
                        return """
                        <div class="bar-row">
                          <div class="bar-label">\(renderTaskName(entry.name))</div>
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
                          <td>\(renderTaskName(entry.name))</td>
                          <td class="numeric">\(formatSeconds(entry.durationSeconds))</td>
                        </tr>
                        """
                    }.joined(separator: "\n")

                return """
                <article class="run-card" id="\(escapeHTML(metric.anchor))">
                  <div class="run-header">
                    <div>
                      <h3>\(metric.run.runIndex)回目</h3>
                      <p class="caption">Compile cache: \(escapeHTML(metric.run.compileCache.rawValue))</p>
                    </div>
                    <div class="total-pill">合計 \(formatSeconds(metric.totalDuration))</div>
                  </div>
                  <div class="run-content-stack">
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
                  </div>
                </article>
                """
            }.joined(separator: "\n")

            let comparisonRows = group.runs.map { metric in
                let width = (metric.totalDuration / maxDuration) * 100
                return """
                <div class="run-compare-row">
                  <a href="#\(escapeHTML(metric.anchor))" class="run-link">\(metric.run.runIndex)回目</a>
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
              \(stabilityCard)
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
            .stability-card {
              border-radius: 22px;
              padding: 20px;
              margin-bottom: 16px;
              background: var(--panel);
              backdrop-filter: blur(12px);
              border: 1px solid rgba(255,255,255,0.55);
              box-shadow: var(--shadow);
            }
            .stability-stable {
              border-color: rgba(44, 138, 94, 0.28);
            }
            .stability-warning {
              border-color: rgba(201, 139, 36, 0.28);
            }
            .stability-unstable {
              border-color: rgba(176, 62, 62, 0.28);
            }
            .comparison-card h3, .chart-block h4, .table-block h4 {
              margin: 0 0 14px;
              font-size: 16px;
            }
            .stability-head {
              display: flex;
              justify-content: space-between;
              align-items: center;
              gap: 12px;
              margin-bottom: 14px;
            }
            .stability-badge {
              border-radius: 999px;
              padding: 8px 12px;
              font-size: 12px;
              font-weight: 700;
              letter-spacing: 0.05em;
              background: rgba(16, 33, 43, 0.08);
            }
            .stability-grid {
              display: grid;
              grid-template-columns: repeat(4, minmax(0, 1fr));
              gap: 12px;
              margin-bottom: 12px;
            }
            .stability-label {
              color: var(--muted);
              font-size: 12px;
              margin-bottom: 6px;
            }
            .stability-value {
              font-size: 20px;
              font-weight: 700;
              letter-spacing: -0.02em;
            }
            .stability-message {
              margin: 0;
              color: var(--muted);
              font-size: 14px;
              line-height: 1.6;
            }
            .run-compare-row {
              display: grid;
              grid-template-columns: minmax(120px, 220px) 1fr 80px;
              gap: 12px;
              align-items: center;
              margin-bottom: 10px;
            }
            .bar-row {
              display: grid;
              grid-template-columns: minmax(280px, 420px) 1fr 80px;
              gap: 12px;
              align-items: center;
              margin-bottom: 10px;
            }
            .bar-label {
              min-width: 0;
            }
            .task-name.has-tooltip {
              position: relative;
              display: inline-flex;
              align-items: center;
              max-width: 100%;
              cursor: help;
              text-decoration: underline dotted rgba(16, 33, 43, 0.35);
              text-underline-offset: 0.18em;
            }
            .task-name-label {
              display: inline-block;
              max-width: 100%;
              white-space: nowrap;
              overflow: hidden;
              text-overflow: ellipsis;
            }
            .task-name.has-tooltip::after {
              content: attr(data-tooltip);
              position: absolute;
              left: 0;
              bottom: calc(100% + 10px);
              width: min(360px, 72vw);
              padding: 10px 12px;
              border-radius: 12px;
              background: rgba(16, 33, 43, 0.96);
              color: #fff;
              font-size: 12px;
              line-height: 1.6;
              letter-spacing: 0;
              text-transform: none;
              box-shadow: 0 16px 32px rgba(16, 33, 43, 0.22);
              opacity: 0;
              pointer-events: none;
              transform: translateY(4px);
              transition: opacity 140ms ease, transform 140ms ease;
              white-space: normal;
              z-index: 20;
            }
            .task-name.has-tooltip::before {
              content: "";
              position: absolute;
              left: 14px;
              bottom: calc(100% + 4px);
              border-width: 6px;
              border-style: solid;
              border-color: rgba(16, 33, 43, 0.96) transparent transparent transparent;
              opacity: 0;
              pointer-events: none;
              transform: translateY(4px);
              transition: opacity 140ms ease, transform 140ms ease;
              z-index: 20;
            }
            .task-name.has-tooltip:hover::after,
            .task-name.has-tooltip:hover::before,
            .task-name.has-tooltip:focus-visible::after,
            .task-name.has-tooltip:focus-visible::before {
              opacity: 1;
              transform: translateY(0);
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
              grid-template-columns: 1fr;
              gap: 18px;
            }
            .run-card {
              border-radius: 24px;
              padding: 20px;
            }
            .run-content-stack {
              display: grid;
              grid-template-columns: 1fr;
              gap: 20px;
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
              min-width: 0;
            }
            .table-block {
              min-width: 0;
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
              .stability-grid {
                grid-template-columns: repeat(2, minmax(0, 1fr));
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

    private static func renderTaskName(_ value: String) -> String {
        let escapedName = escapeHTML(value)
        guard let description = TaskDescriptionProvider.description(for: value) else {
            return escapedName
        }
        return "<span class=\"task-name has-tooltip\" tabindex=\"0\" data-tooltip=\"\(escapeHTML(description))\"><span class=\"task-name-label\">\(escapedName)</span></span>"
    }

    private static func formatSeconds(_ value: Double) -> String {
        "\(formatNumber(value))s"
    }

    private static func formatNumber(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.3f", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        "\(formatNumber(value * 100))%"
    }

    private static func lastPathComponent(_ value: String) -> String {
        URL(fileURLWithPath: value).lastPathComponent
    }
}

// MARK: - Build Timing Summary Parsing

private enum BuildTimingSummaryParser {
    static func parse(from output: String) -> [TimingEntry] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard let headerIndex = lines.lastIndex(where: { $0.contains("Build Timing Summary") }) else {
            return []
        }

        let candidateLines = Array(lines[(headerIndex + 1)...]).drop(while: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || Set(trimmed).isSubset(of: ["="])
        })

        var entries: [TimingEntry] = []

        for line in candidateLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            if let entry = parseLine(trimmed) {
                entries.append(entry)
            }
        }

        return entries
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
    let stabilitySummaries: [StabilitySummary]
    let runs: [RunResult]
}

private struct RunMetric {
    let run: RunResult
    let totalDuration: Double

    var anchor: String {
        "\(run.mode.rawValue)-run-\(run.runIndex)"
    }
}

private struct TimingEntry: Encodable {
    let name: String
    let durationSeconds: Double
}

private struct StabilitySummary: Encodable {
    let mode: BuildMode
    let sampleCount: Int
    let meanSeconds: Double
    let standardDeviationSeconds: Double
    let coefficientOfVariation: Double
    let status: StabilityStatus
    let message: String
}

private enum TaskDescriptionProvider {
    static func description(for taskName: String) -> String? {
        switch normalizedName(for: taskName) {
        case "SwiftDriver Compilation Requirements":
            return "Swift compiler driver がコンパイル前に依存関係や実行条件を整理する前段処理です。"
        case "SwiftDriver Compilation":
            return "Swift compiler driver が compile job 群を起動・管理する処理です。"
        case "SwiftDriver":
            return "Swift compiler driver 自体の処理です。Swift の各コンパイル job やモジュール生成の段取りを調整します。"
        case "SwiftCompile":
            return "Swift ソースコードを実際にコンパイルする処理です。"
        case "SwiftEmitModule":
            return "Swift module を生成する処理です。モジュール情報や関連成果物を書き出します。"
        case "Ld":
            return "linker によるリンク処理です。object file やライブラリを最終バイナリにまとめます。"
        case "CodeSign":
            return "codesign による署名処理です。アプリや生成物に署名を付与します。"
        case "AppIntentsSSUTraining":
            return "App Intents を system experiences で利用するための追加生成処理です。"
        case "CompileAssetCatalogVariant":
            return "Asset Catalog を対象環境向けにコンパイルする処理です。画像や色、シンボルなどをビルド成果物に変換します。"
        case "Copy":
            return "生成物や依存ファイルをアプリ bundle などにコピーする処理です。"
        case "CopySwiftLibs":
            return "必要な Swift runtime ライブラリを生成物へコピーする処理です。"
        case "ProcessInfoPlistFile":
            return "Info.plist を最終生成物向けに処理する工程です。"
        case "GenerateAssetSymbols":
            return "Asset Catalog から参照用のシンボルやコード生成を行う処理です。"
        case "WriteAuxiliaryFile":
            return "ビルド中に必要な補助ファイルを書き出す処理です。"
        case "ProcessProductPackagingDER":
            return "署名や packaging に関連する DER 形式データを処理する工程です。"
        case "Touch":
            return "生成物のタイムスタンプ更新など、最終化の軽量処理です。"
        case "LinkAssetCatalog":
            return "コンパイル済み Asset Catalog を生成物へリンクする処理です。"
        case "ConstructStubExecutorLinkFileList":
            return "リンク用の stub executor ファイル一覧を構築する処理です。"
        case "SwiftMergeGeneratedHeaders":
            return "Swift 由来の生成ヘッダを統合する処理です。"
        case "Validate":
            return "生成物が配布・実行条件を満たすか検証する処理です。"
        case "ProcessProductPackaging":
            return "生成物の packaging 情報を処理する工程です。"
        case "ExtractAppIntentsMetadata":
            return "App Intents の metadata を抽出する処理です。"
        case "RegisterExecutionPolicyException":
            return "実行ポリシーに関する例外情報を登録する処理です。"
        default:
            return nil
        }
    }

    private static func normalizedName(for taskName: String) -> String {
        guard let range = taskName.range(of: " (") else {
            return taskName
        }
        return String(taskName[..<range.lowerBound])
    }
}

private enum StabilityStatus: String, Encodable {
    case stable
    case warning
    case unstable

    var displayName: String {
        switch self {
        case .stable:
            return "安定"
        case .warning:
            return "注意"
        case .unstable:
            return "不安定"
        }
    }
}

private enum StabilityAnalyzer {
    static func summaries(for runs: [RunResult]) -> [StabilitySummary] {
        let groupedRuns = Dictionary(grouping: runs, by: \.mode)
        return BuildMode.displayOrder.compactMap { mode in
            guard let modeRuns = groupedRuns[mode], !modeRuns.isEmpty else {
                return nil
            }

            let samples = modeRuns.map(\.totalDurationSeconds)
            let mean = samples.reduce(0, +) / Double(samples.count)
            let variance = samples.reduce(0.0) { partialResult, sample in
                partialResult + pow(sample - mean, 2)
            } / Double(samples.count)
            let standardDeviation = sqrt(variance)
            let coefficientOfVariation = mean > 0 ? standardDeviation / mean : 0

            let status: StabilityStatus
            if samples.count < 3 {
                status = .warning
            } else if coefficientOfVariation <= 0.05 {
                status = .stable
            } else if coefficientOfVariation <= 0.10 {
                status = .warning
            } else {
                status = .unstable
            }

            return StabilitySummary(
                mode: mode,
                sampleCount: samples.count,
                meanSeconds: mean,
                standardDeviationSeconds: standardDeviation,
                coefficientOfVariation: coefficientOfVariation,
                status: status,
                message: message(for: status, sampleCount: samples.count)
            )
        }
    }

    private static func message(for status: StabilityStatus, sampleCount: Int) -> String {
        if sampleCount < 3 {
            return "サンプル数が3未満のため参考値です。3回以上で再計測してください。"
        }

        switch status {
        case .stable:
            return "ばらつきは小さく、実務上は安定した計測結果とみなせます。"
        case .warning:
            return "ばらつきがやや大きい状態です。必要なら5回以上に増やして再評価してください。"
        case .unstable:
            return "ばらつきが大きいため、実行環境または計測手段を見直して再計測してください。"
        }
    }
}

private struct CLIError: Error {
    let message: String
    let showsUsage: Bool

    init(_ message: String, showsUsage: Bool = false) {
        self.message = message
        self.showsUsage = showsUsage
    }

    static func usage(_ message: String) -> CLIError {
        CLIError(message, showsUsage: true)
    }
}

private enum ProcessRunner {
    struct Result {
        let output: String
        let exitCode: Int32
    }

    static func run(executablePath: String, arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            output: String(decoding: outputData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

XcodeBuildAnalysisCLI.main()
