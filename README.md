# XcodeBuildAnalysis

`xcodebuild` の clean build と integration build を複数回計測し、`Build Timing Summary` を JSON で出力する単一ファイルの Swift CLI です。

## Run

```bash
swift xcode-build-analysis.swift --help
```

## Usage

```bash
swift xcode-build-analysis.swift \
  -w YourApp.xcworkspace \
  -s YourApp \
  -m both \
  -n 3 \
  -C inherit \
  -d 'iPhone 17' \
  -D /tmp/DerivedData \
  -o build-report.json
```

### 主な引数

- `--project`, `-p`: `.xcodeproj`を指定
- `--workspace`, `-w`: `.xcworkspace`を指定
- `--scheme`, `-s`: ビルド対象scheme
- `--mode`, `-m`: `both` / `clean` / `integration`。デフォルトは `both`
- `--runs`, `-n`: 計測回数。デフォルトは `3`
- `--compile-cache`, `-C`: `inherit` / `on` / `off`。デフォルトは `inherit`
- `--destination`, `-d`: Simulator名。`iPhone 17` のように渡すと `platform=iOS Simulator,name=iPhone 17` に展開。`platform=...` の完全指定も可
- `--derived-data-path`, `-D`: `DerivedData`の出力先
- `--output`, `-o`: JSONの出力先。未指定時は標準出力

### mode の挙動

- `clean`: 毎回 `xcodebuild clean build -showBuildTimingSummary` を実行
- `integration`: 最初に一度だけ warm-up の `clean build` を実行し、その後は同じ `DerivedData` で `build -showBuildTimingSummary` を繰り返し計測
- `both`: `clean` を指定回数実行した後、`integration` を指定回数実行

## Compile

必要なら単体バイナリにもできます。

```bash
swiftc xcode-build-analysis.swift -o xcode-build-analysis
./xcode-build-analysis --help
```

## Output

出力JSONはトップレベルに実行 metadata を持ち、その中に run ごとの配列を持ちます。metadata には `project`、`executedAt`、`xcodeVersion`、`sdkVersion`、`scheme` を含みます。ビルド失敗時や要約が出なかった場合は、その run の `timingSummary` が空配列になります。

### JSON例

```json
{
  "executedAt": "2026-04-01T12:00:00Z",
  "project": "YourApp.xcworkspace",
  "runs": [
    {
      "compileCache": "inherit",
      "mode": "clean",
      "runIndex": 1,
      "timingSummary": [
        {
          "durationSeconds": 32.5,
          "name": "SwiftCompile (4 tasks)"
        }
      ]
    }
  ],
  "scheme": "YourApp",
  "sdkVersion": "26.4",
  "xcodeVersion": "Xcode 26.4 (Build version 17E192)"
}
```
