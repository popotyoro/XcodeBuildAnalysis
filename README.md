# XcodeBuildAnalysis

`xcodebuild` の clean build と integration build を複数回計測し、`Build Timing Summary` を JSON または HTML で出力する単一ファイルの Swift CLI です。

## Run

```bash
swift xcode-build-analysis.swift --help
```

## Usage

```bash
swift xcode-build-analysis.swift \
  -w YourApp.xcworkspace \
  -s YourApp \
  -f html \
  -m both \
  -n 3 \
  -C inherit \
  -d 'iPhone 17' \
  -D /tmp/DerivedData \
  -o build-report.html
```

### 主な引数

- `--project`, `-p`: `.xcodeproj`を指定
- `--workspace`, `-w`: `.xcworkspace`を指定
- `--scheme`, `-s`: ビルド対象scheme
- `--format`, `-f`: `json` / `html`。デフォルトは `json`
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

`--format json` ではトップレベルに実行 metadata を持つ JSON を出力します。metadata には `project`、`executedAt`、`xcodeVersion`、`scheme` を含みます。ビルド失敗時や要約が出なかった場合は、その run の `timingSummary` が空配列になります。

`--format html` では同じ `AnalysisReport` を人向けに可視化した HTML レポートを出力します。HTML には以下を含みます。

- 実行 metadata のサマリ
- clean / integration ごとの集計カード
- run ごとの合計時間比較
- 各 run の上位タスク棒グラフ
- 各 run の full timing summary テーブル

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
  "xcodeVersion": "Xcode 26.4 (Build version 17E192)"
}
```

### HTML例

```bash
swift xcode-build-analysis.swift \
  -w YourApp.xcworkspace \
  -s YourApp \
  -f html \
  -o build-report.html
```

JSON は機械処理向け、HTML は比較・閲覧向けです。元になる分析データは同じです。
