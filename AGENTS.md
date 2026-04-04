# AGENTS.md

## Purpose

This repository provides a single-file Swift CLI for analyzing Xcode build bottlenecks.
The CLI measures clean and integration builds with `xcodebuild` and outputs the parsed `Build Timing Summary` as JSON or HTML.

## Current Implementation

- Main entrypoint: `xcode-build-analysis.swift`
- Execution style: standalone Swift script, not Swift Package Manager
- Shared data model: `AnalysisReport`
- Supported output formats:
  - `json`
  - `html`

## CLI Contract

- `--project` / `-p` or `--workspace` / `-w` is required
- `--scheme` / `-s` is required
- `--format` / `-f` defaults to `json`
- `--mode` / `-m` defaults to `both`
- `--runs` / `-n` defaults to `3`
- `--compile-cache` / `-C` defaults to `inherit`
- Supported optional flags:
  - `--format` / `-f`
  - `--mode` / `-m`
  - `--runs` / `-n`
  - `--compile-cache` / `-C`
  - `--destination` / `-d`
  - `--derived-data-path` / `-D`
  - `--output` / `-o`
  - `--help` / `-h`
- Do not add broad pass-through argument support unless explicitly requested

## xcodebuild Behavior

- Use `/usr/bin/xcodebuild` directly
- Do not use `xcrun`
- `clean` mode runs `clean build -showBuildTimingSummary` for every measured run
- `integration` mode runs one warm-up `clean build`, then measured `build -showBuildTimingSummary` runs against the same DerivedData
- `both` runs all clean iterations first, then all integration iterations
- When `-d` is given as a plain simulator name such as `iPhone 17`, convert it to:
  - `platform=iOS Simulator,name=<value>`
- If `-d` already contains `=` or `,`, treat it as a full destination string and pass it through unchanged
- Compile cache control uses `COMPILATION_CACHE_ENABLE_CACHING`
  - `inherit`: no override
  - `on`: `COMPILATION_CACHE_ENABLE_CACHING=YES`
  - `off`: `COMPILATION_CACHE_ENABLE_CACHING=NO`

## Output Rules

- JSON output uses the `AnalysisReport` structure directly
- HTML output renders the same `AnalysisReport` for human viewing
- Do not include full command, raw logs, or exit code wrappers
- If the timing summary is unavailable for a run, emit that run with `timingSummary: []` and render it as empty in HTML
- HTML must remain self-contained with inline CSS/JS and no external dependencies

## Parsing Rules

- Parse the actual Xcode summary format:
  - `SwiftCompile (4 tasks) | 8.188 seconds`
- Preserve all summary lines that can be parsed
- Keep the JSON entries in the same order as the summary output

## Repo Conventions

- `DummyApp/` is for local testing only and must stay ignored
- `DummyApp/` is the repository's measurement-only dummy app; do not inspect, analyze, or observe files under it unless the user explicitly asks you to
- Keep the tool as a single Swift file unless explicitly asked to restructure
- Keep README usage examples aligned with the real CLI behavior
- Use Conventional Commits format for commit messages
