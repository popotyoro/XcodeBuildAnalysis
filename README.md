# XcodeBuildAnalysis

`xcodebuild clean build -showBuildTimingSummary` の結果だけをJSONで出力する単一ファイルのSwift CLIです。

## Run

```bash
swift xcode-build-analysis.swift --help
```

## Usage

```bash
swift xcode-build-analysis.swift \
  -w YourApp.xcworkspace \
  -s YourApp \
  -d 'iPhone 17' \
  -D /tmp/DerivedData \
  -o build-report.json \
```

### 主な引数

- `--project`, `-p`: `.xcodeproj`を指定
- `--workspace`, `-w`: `.xcworkspace`を指定
- `--scheme`, `-s`: ビルド対象scheme
- `--destination`, `-d`: Simulator名。`iPhone 17` のように渡すと `platform=iOS Simulator,name=iPhone 17` に展開。`platform=...` の完全指定も可
- `--derived-data-path`, `-D`: `DerivedData`の出力先
- `--output`, `-o`: JSONの出力先。未指定時は標準出力

## Compile

必要なら単体バイナリにもできます。

```bash
swiftc xcode-build-analysis.swift -o xcode-build-analysis
./xcode-build-analysis --help
```

## Output

出力JSONは `Build Timing Summary` から抽出した配列だけです。ビルド失敗時や要約が出なかった場合は空配列になります。

### JSON例

```json
[
  {
    "durationSeconds": 32.5,
    "name": "SwiftCompile normal arm64 /YourApp/Sources/FeatureA/View.swift"
  }
]
```
