# AGENTS.md

## Purpose

This repository provides a single-file Swift CLI for analyzing Xcode build bottlenecks.
The CLI runs `xcodebuild clean build -showBuildTimingSummary` and outputs only the parsed `Build Timing Summary` as JSON.

## Current Implementation

- Main entrypoint: `xcode-build-analysis.swift`
- Execution style: standalone Swift script, not Swift Package Manager
- Output format: JSON array of timing entries
- Each timing entry has:
  - `name`
  - `durationSeconds`

## CLI Contract

- `--project` / `-p` or `--workspace` / `-w` is required
- `--scheme` / `-s` is required
- Supported optional flags:
  - `--destination` / `-d`
  - `--derived-data-path` / `-D`
  - `--output` / `-o`
  - `--help` / `-h`
- Do not add broad pass-through argument support unless explicitly requested

## xcodebuild Behavior

- Use `/usr/bin/xcodebuild` directly
- Do not use `xcrun`
- Always run:
  - `clean`
  - `build`
  - `-showBuildTimingSummary`
- When `-d` is given as a plain simulator name such as `iPhone 17`, convert it to:
  - `platform=iOS Simulator,name=<value>`
- If `-d` already contains `=` or `,`, treat it as a full destination string and pass it through unchanged

## Output Rules

- Output only the parsed `Build Timing Summary`
- Do not include wrapper metadata such as:
  - full command
  - exit code
  - timestamps
  - raw log excerpts
  - extra summary fields
- If the timing summary is unavailable, output `[]`

## Parsing Rules

- Parse the actual Xcode summary format:
  - `SwiftCompile (4 tasks) | 8.188 seconds`
- Preserve all summary lines that can be parsed
- Keep the JSON entries in the same order as the summary output

## Repo Conventions

- `DummyApp/` is for local testing only and must stay ignored
- Keep the tool as a single Swift file unless explicitly asked to restructure
- Keep README usage examples aligned with the real CLI behavior
- Use Conventional Commits format for commit messages
