# CLAUDE.md

このファイルは Claude Code（claude.ai/code）がこのリポジトリで作業するときの指針です。
**この指示は既定の挙動より優先されます。正確に従ってください。**

> **設計の「なぜ」は [docs/design.md](docs/design.md) にあります。**
> このファイルは**規則と手順**に絞ってあり、根拠はそちらに集めてあります
> （Claude 以外の AI も人間も読むため）。設計に関わる変更をしたら
> **design.md も同時に更新してください** — 規則だけ書き換えて理由が古いまま、
> という状態を作らないこと。迷ったときは design.md を読んでから決めてください。

## このリポジトリについて

Apple の **MLX**（mlx-swift / mlx-swift-lm）で、iPhone と Mac の上でローカルに LLM を
動かすチャットアプリです。目的は「MLX の実力を実機で確かめること」なので、
**速度の数字（tok/s・TTFT・ピークメモリ）は会話と同じ重みで扱う** — 画面にも出すし、
会話ごと保存するし、ベンチマークは独立した機能として GUI・CLI の両方から実行できます。

入口は 4 つ（Swift ライブラリ / CLI / URL スキーム / GUI）で、対象は iOS と macOS。
使用言語は Swift。ビルドは SwiftPM（純ロジック）と XcodeGen + xcodebuild（アプリ）の
2 本立てです。

CI・リリース・自動アップデート・CI デバッグの構成は、姉妹リポジトリ
`min-nano/photogrammetry` の仕組みを移植したものです。迷ったらそちらの実装と
README も参照してください。

## アーキテクチャ: ロジックと GUI と MLX の三分割

**GUI はロジックを持たない薄いシェル**にし、**MLX に触ってよい層は 1 つだけ**にする。
これがこのリポジトリの設計の核です。

```
Sources/                    ← SwiftPM パッケージ（外部依存ゼロ・テストがある）
  MLXChatCore/              ロジック本体。MLX / SwiftUI / UIKit / AppKit を import しない
    ChatMessage             発言 1 つ（値型・Codable）
    Conversation            会話 1 本 + 履歴の切り詰め規則
    ModelCatalog            提示するモデルの唯一の定義（id・サイズ・必要メモリ）
    DeviceProfile           搭載メモリ → 使える予算・動くモデル・警告（純ロジック）
    GenerationParameters    生成のつまみ + validate
    ChatRequest             生成 1 回分の指示 + validate
    Benchmark               ベンチの指示・集計（BenchmarkRequest / BenchmarkSummary）
    APICommand              URL スキーム / CLI 引数 → Request（外部連携 API の唯一の定義）
    GenerationEvent         エンジン → 画面のイベントと段階（文言もここ）
    GenerationStats         1 回の生成の実測値と tok/s の計算
    ConversationStore       会話の保存（1 会話 = 1 JSON）
    ModelStorage            重みの置き場所・サイズ・削除
    Reasoning               推論モデルの思考（<think>）と答えの切り分け
    Transcript              会話の書き出し（Markdown / テキスト）
    ErrorDetails            失敗の見分けと「次に何をすればいいか」
  MLXChatUpdater/           自動アップデート（macOS 用）
    UpdateFeed              Releases JSON → チャンネル一覧・更新判定（純ロジック・I/O なし）
    UpdaterService          ネットワーク・展開・差し替え起動（Foundation のみ）

Apps/                       ← Xcode プロジェクトだけがビルドする（MLX を引く）
  MLXChatEngine/            MLX の唯一のラッパー  ← ここだけが MLXLLM を import する
    MLXChatEngine           モデルの読み込みと生成、MLX 型 ⇄ Core 値型の変換表
    BenchmarkRunner         繰り返しの段取り（判断は Core が持つ）
  MLXChatUI/                SwiftUI。iOS と macOS で完全に共通
  iOS/                      iOS アプリのエントリポイント
  macOS/                    macOS アプリのエントリポイント + 自動アップデート画面
  cli/                      mlxchat-cli（整形だけ）

Tests/                      ← swift test。Sources/ の純ロジックだけを見る

docs/design.md              ← 設計の「なぜ」。人間と Claude 以外の AI 向け
```

**依存の向きは厳守する:**

- `MLXChatCore` / `MLXChatUpdater` は **MLX を import しない**。これは規約ではなく
  構造で守られている — ルートの `Package.swift` に MLX の依存が無いので、Core が
  MLX に触れた瞬間 `swift build` が落ちる。
- `MLXChatCore` は SwiftUI / UIKit / AppKit も import しない（こちらは規約）。
- **MLX の型（`ModelContainer` / `ChatSession` / `GenerateParameters` /
  `Generation`）は `Apps/MLXChatEngine/MLXChatEngine.swift` の外に漏らさない。**
  API 表現は Core の自前の型で、変換表はエンジン内に 1 つだけ。
- **エンジンには判断を置かない。** そこにあってよいのは「MLX の型への写し替え」と
  「MLX の呼び出し」だけ。GPU が要るのでテストが書けない層だから。判断（履歴の
  切り詰め・つまみの範囲・端末で動くか・速度の集計・エラーの文言）は必ず Core へ下ろす。
- 外部連携のパラメータ語彙（`model` / `prompt` / `system` / `temperature` /
  `topP` / `maxTokens` / `kvBits` / `history` / `runs` / `warmup` / …）は
  `APICommand` に **1 か所だけ**定義する。入口（URL / CLI）やコマンド
  （`chat` / `bench` / `models`）を増やす・変えるときは `APICommand` とその
  テストを同時に更新する。CLI はサブコマンド名が無ければ `chat` として解釈する。
- **Core に機能を足したら GUI の入口も同時に足す。** ライブラリ / CLI / URL
  スキームが GUI と同じ機能に届くことを保証する設計なので、逆に GUI だけ届かない
  機能があってもいけない（ベンチマークは GUI のタブ／サイドバーから実行できる）。
- **アプリ 1 つ = 1 モジュール**にしてある（Core / Engine / UI を framework に
  分けていない）。分けると iOS の埋め込みと署名の手間が増えるわりに、依存の向きの
  強制は結局 `Package.swift` 側で効くため。したがって `Apps/` のソースに
  `import MLXChatCore` は**書かない**（同じモジュールなので不要かつコンパイルエラー）。
- リリースの機械可読形式（アセット名 `MLXChat.app.zip` / `MLXChat.ipa`、notes の
  `channel=` / `branch=` / `commit=` / `built=` 行、タグ `stable` / `dev-<slug>`）は
  `UpdateFeed` と `build.yml` の**対**で定義されている。片方を変えるときは必ず
  両方＋テストを更新する。
- **エンジンはプロセスに 1 つ（`MLXChatEngine.shared`）**。チャット画面とベンチ
  マーク画面が別々に持つと同じ重みを二重に読み込む（数 GB × 2）。節約ではなく必須。
- **文字入力のある画面には `.dismissibleKeyboard()` を必ず付ける。** iOS は
  キーボードが出ている間 TabView の下タブを隠すので、畳む手段が無いと
  **一度入力欄に触れたら他の画面へ移れなくなる**（実機で踏んだ）。実装は
  `Apps/MLXChatUI/KeyboardDismiss.swift` に 1 つだけ置いてある。
- **別プロセス化はしない。** 姉妹リポジトリ photogrammetry は RealityKit が
  `abort()` しうるため生成をヘルパープロセスに追い出しているが、MLX は
  `abort()` しない。危険なのはメモリ不足による OS 側の強制終了で、これは
  プロセス境界では防げない（`DeviceProfile` で事前に避ける・`kvBits` で減らす、
  が対処）。構成を単純に保つ。

## メモリの扱い（このアプリ固有の最重要事項）

iPhone はアプリごとのメモリ上限を超えると**警告なしに終了させられる**（jetsam）。
MLX の重みはユニファイドメモリに載るのでその上限にそのまま数えられる。
背景と係数の根拠は [docs/design.md 第 5 節](docs/design.md#5-メモリ--iphone-で落ちないための設計)。
守ること:

- 「この端末でどのモデルまで動くか」は `DeviceProfile`（純ロジック）が決める。
  係数は iOS 0.50 / macOS 0.70。**この判断を GUI やエンジンに複製しない。**
- `ModelCatalog` の `requiredMemoryBytes` は**やや多めに**見積もる。落ちるより
  「出さない」ほうがましだから。
- 動かない見込みのモデルも**選べる**ようにしてある。ただし警告は出す。
- `kvBits`（4/8）と `historyMessageLimit` は利用者に見せる逃げ道。設定画面から
  外さないこと。

## 推論モデルの思考（`<think>`）

- 切り分けは `ReasoningSplitter`（Core・純ロジック）が唯一の実装。**入口ごとに
  タグを剥がす処理を書かない。**
- 思考は `ChatMessage.reasoning` へ、答えは `text` へ入れる。この分け方のおかげで
  「履歴に思考を混ぜない」「書き出しは答えだけ」が自動的に成立する。**この分担を
  崩さないこと。**
- ストリーミングでタグが割れて届く（`<th` + `ink>`）ため、逐次処理版
  （`consume` / `flush`）が本体で、全文版（`split`）はそれを内部で回している。
  **2 つ目の実装を作らないこと**（画面と保存済みの本文が食い違う）。

## テスト方針

- **純ロジック（`APICommand` / `UpdateFeed` / `validate` / `BenchmarkSummary` /
  `DeviceProfile` …）を `swift test` でテスト**する。GPU もネットワークも
  要らず、**MLX をビルドしない**ので数十秒で終わる。この速さは
  「Sources/ が外部依存ゼロの SwiftPM パッケージである」ことで成り立っている
  — MLX をルートの `Package.swift` に足してはならない。
- **実際の生成は自動テストしない**。CI ランナーの GPU 要件が保証されず、モデルの
  ダウンロードに数 GB かかる。品質・速度は Apple Silicon の実機で目視確認する。
  CI 上で挙動を見たいときは ci-debug の `run-cli` モードを使う（`models` の
  ように GPU が要らないサブコマンドは普通に動く）。
- GUI（ViewModel）はロジックを持たないので専用テストは置かない。テストしたい
  判断が ViewModel に生えてきたら、それは Core へ下ろすサイン。
- **カバレッジ**は `test.yml` の `test` ジョブ（macOS）が `swift test
  --enable-code-coverage` を 1 回だけ実行して測る。`llvm-cov` で lcov / JSON
  summary / diff カバレッジをアーティファクトにし、`coverage` ジョブ
  （ubuntu-latest、Swift 不要）がそれを読んで PR に表（🟢/🟡/🔴、全体 + この
  PR が変更した行だけの diff カバレッジ）を sticky コメントとして投稿し、
  しきい値未満なら `coverage` ジョブだけを失敗させる（ゲート）。計測とレポート
  を分けているのは「テストが壊れた」のか「しきい値を下回った」のかを一目で
  区別するため。`UpdaterService.swift`（ネットワーク I/O + 別プロセス起動）は
  集計から除外している。**フレームワークを叩くラッパーを新しく足したら、除外にも
  同時に足す**（除外を足すということは「その層に判断を置かない」という約束
  でもある）。しきい値は初期のベースラインなので、実測が安定したら上げること。

## ビルド・リリース

- ローカル（純ロジック）: `swift build` / `swift test`。MLX を引かないので速い。
- ローカル（アプリ）: `scripts/generate-xcodeproj.sh` → Xcode で開く。
  `.xcodeproj` はリポジトリに入れない（原本は `project.yml`）。
- **macOS 版は Apple Silicon 専用**（`ARCHS: arm64`）。MLX は Metal の GPU
  family を要求するので Intel Mac では動かない。ユニバーサルにしない。
- **iOS 版はシミュレータで動かない**（同じ理由）。`SUPPORTED_PLATFORMS:
  iphoneos` にしてあり、CI も `generic/platform=iOS` だけをビルドする。
- **Xcode 26 以降、Metal のコンパイラは別ダウンロード**。mlx-swift は `.metal`
  を丸ごとコンパイルするので、CI では `xcodebuild -downloadComponent
  MetalToolchain` を先に走らせている（`build.yml` と `ci-debug-job.sh` の両方）。
- CI はテストとビルドで完全に独立した 2 本のワークフローに分かれている。
  同じ push（main）/ pull_request イベントで起動するが、`needs` などでは
  互いに繋がず**並列に走る**。合否は branch protection の required checks 側で見る。
  - `test.yml`: 2 ジョブ。`test`（macos-26、カバレッジ計測つきで `swift test`）
    → `coverage`（ubuntu-latest、PR にコメント・しきい値でゲート）。
  - `build.yml`: `ctx` で commit/ref/チャンネルを解決 →
    `build-macos` と `build-ios` を**並列**に → `release`。
    mlx-swift を丸ごとビルドするので**片側 30 分以上かかる**。
  - main への push → タグ `stable` のローリングリリース（削除して作り直し）。
  - PR への push → タグ `dev-<slug>` のプレリリース（同上）。fork PR は公開不可。
  - ブランチ削除 → `cleanup-dev-release.yml` がプレリリースを掃除。
- 自動アップデートは Info.plist のスタンプ（`GitCommit` / `GitBranch` /
  `BuildChannel`）とリリースを突き合わせる。スタンプは `scripts/stamp-app.sh` が書く。
- **iOS 版の .ipa は未署名**。証明書を CI に置かない方針なので、そのままでは
  iPhone に入らない（README の導入手順を参照）。**iOS には自動アップデートが無い**
  — アプリが自分自身を差し替えられないため。更新の判定（`UpdateFeed`）だけは共通。
- **アプリアイコンは `scripts/make-app-icon.py` が唯一の原典**（寸法・色はすべて
  スクリプト内）。生成物 `packaging/AppIcon.svg` と
  `packaging/Assets.xcassets/AppIcon.appiconset/` はリポジトリに入れてあるので、
  デザインを変えるときはスクリプトを直して再生成し、両方を commit する。
  依存は `cairosvg` と `pillow` だけで macOS 専用ツールに頼らないので、Linux の
  リモートセッションでも再生成・確認できる（`pip install cairosvg pillow`）。

## CI デバッグ（macOS が必要な調査は `ci-debug` を使う）

リモートセッション（クラウド上のコンテナ）は Linux で、**macOS / Xcode / Metal が
無い**。したがって Swift のビルドエラーの再現・テスト実行・MLX の API がコンパイル
できるかの確認は、**CI 上でしか答えが出ない**。そのための専用ワークフローが
`.github/workflows/ci-debug.yml` で、`workflow_dispatch` でしか起動しない
（push / PR では**決して**走らない）。

**`build.yml` に一時的な調査ステップを挿してはならない。** 戻し忘れる・その
commit が dev プレリリースとして公開される、と副作用が大きい。調査は必ず下記の
経路で行う。

### 使い方（リモートセッションの AI はこの 2 手順）

リモートセッションのコンテナに入っている `GITHUB_TOKEN` は**読み取り専用**で
`actions: write` を持たない（REST でのディスパッチは 403 になる）。したがって
**起動は GitHub MCP、待機はスクリプト**という 2 手順になる。

```
1. mcp__github__actions_run_trigger
     method: run_workflow, workflow_id: "ci-debug.yml", ref: <調査したいブランチ>,
     inputs: {mode, label, args, script, notify_pr}
     ※ label は一意な文字列にする（これで run を特定する）

2. Bash(run_in_background: true):
     scripts/ci-debug.sh wait --label <label>
```

**手順 2 は必ず `run_in_background: true` で投げる。** このスクリプトは「run の
特定 → 完了待ち → ペイロード抽出」を行って**完了した瞬間に exit する**ので、
待機時間ゼロ・タイマー不要で結果を受け取れる。投げたら別作業を続け、終了通知が
来たら出力ファイルを `Read` するだけでよい。**`sleep` で待ってはいけない。**

| mode | 用途 | 所要 | `--args` |
| --- | --- | --- | --- |
| `build` | swift build（Sources/ の純ロジックだけ） | 1 分 | 追加フラグ |
| `test` | swift test | 2 分 | 例 `--filter UpdateFeedTests` |
| `xcode-mac` | macOS アプリのビルド（MLX 込み） | 30 分〜 | xcodebuild への追加フラグ |
| `xcode-ios` | iOS アプリのビルド（実機向け・未署名） | 30 分〜 | 同上 |
| `xcode-cli` | mlxchat-cli のビルド | 30 分〜 | 同上 |
| `run-cli` | mlxchat-cli をビルドして実行 | 30 分〜 | CLI の引数 |
| `shell` | 任意の bash（`--script`）。逃げ道 | — | — |

**まず `build` / `test` で確かめられないかを考えること。** `xcode-*` は MLX を
丸ごとビルドするので 1 回 30 分以上かかる。Core のコンパイルエラーは `build` で
出るし、判断のバグは `test` で出る。`xcode-*` が本当に要るのは「MLX の API の
使い方が合っているか」を確かめるときだけ。

### 結果の読み方

出力は必ず次のマーカーで挟まれている。`truncated=yes` のときは**全部は見えて
いない**ので、`--args` を絞るか `mode=shell` で件数を数える。

```
===== BEGIN PAYLOAD (mode=...) =====
...
===== END PAYLOAD (exit=N lines_total=N truncated=yes|no) =====
```

失敗して調査コマンドに到達しなかった場合はマーカーが無く、代わりに理由が出る。
ペイロードの取得経路は 2 つあり、`ci-debug.sh` はこの順に試す。

1. **チェックラン注釈**（`GET /repos/{owner}/{repo}/check-runs/{id}/annotations`）。
   `ci-debug-job.sh` がペイロードを `::notice::` としても出しているので、ここから
   読める。`api.github.com` だけで完結する。**通常はこちらで取れる。**
2. **ジョブログ**。ログ API は署名付きの Azure Blob Storage へ 302 で飛ぶが、
   **そのホストは組織の egress ポリシーで拒否されている**ため、リモートセッションの
   コンテナからは取得できない。これは迂回してはならない制約なので、必要なときは
   GitHub MCP の `get_job_logs`（`job_id` 指定・`return_content: true`）を使う。

### 制約

- `workflow_dispatch` は**デフォルトブランチに存在するワークフロー**しか起動
  できない。`ci-debug.yml` が main に入って初めて、作業ブランチを `--ref` に
  指定して使える（実行される定義はその ref 側のもの）。
- **モードの追加・修正は `scripts/ci-debug-job.sh`（ランナー側）で行う。**
  ワークフロー本体は薄く保ってあるので、作業ブランチに push するだけで新しい
  モードを試せる。ワークフロー本体を変えると main へのマージが要る。

## CI の完了待ち（`scripts/wait-pr-checks.sh`）

PR やブランチの CI の完了を待つときは、待ち方を自作せず
**`scripts/wait-pr-checks.sh` を使う**。完了した瞬間に exit するので、
`ci-debug.sh wait` と同じく `run_in_background: true` で投げて別作業を続け、
終了通知が来たら出力を `Read` すればよい。**`sleep` で待ってはいけない。**

```
Bash(run_in_background: true):
  scripts/wait-pr-checks.sh --pr <番号> --timeout 5400 > /tmp/pr.log 2>&1
```

（アプリのビルドは片側 30 分以上かかるので、既定の 45 分では足りないことがある。
`--timeout` を長めに取ること。）

出力の最後は必ず 1 行の機械可読サマリで、終了ステータスと対になっている。

```
result=<success|failure|no-checks|timeout|pr-merged|pr-closed> sha=... total=N failed=N pending=N
  0 = 完了・失敗なし / 1 = 失敗あり / 2 = 使い方・API エラー / 3 = 不明（timeout・no-checks）
```

**待ち方を自作してはならない理由**（姉妹リポジトリで実際に踏んだ）: 素朴に
`GET /commits/{sha}/status`（combined status）の `.state` が `pending` の間ループ
すると**永久に終わらない**。combined status は commit status API のステータスの
集約で、GitHub Actions は commit status ではなく **check run** を作るため、
`total_count: 0` / `state: "pending"` を返し続ける。

`wait-pr-checks.sh` は check runs・workflow runs・commit statuses の 3 経路を見る
（`build.yml` の `release` のように**後から現れるジョブ**があるので workflow runs が
要る）。そのうえで「全部完了」「チェックが現れない」「タイムアウト」の 3 つの出口を
持ち、**どの経路でも必ず exit する**。パイプ（`| tail`）でつながず、ファイルへ
リダイレクトして `Read` すること。

## Swift コード規約

- インデントはタブ。ブレースは Allman（既存ソースに合わせる）。
- コメントは**日本語**で、「なぜ（意図・制約の根拠）」を書く。
- 公開 API（Core / Updater の public）にはドキュメントコメントを付ける。
- 並行処理: ViewModel は `@MainActor`。エンジンのイベントはスレッドを跨ぐので
  受け側で MainActor へ持ち上げる。言語モードは Swift 5（`project.yml` の
  `SWIFT_VERSION`）— mlx-swift-lm の型（`Chat.Message` など）が Sendable でなく、
  Swift 6 の厳格な並行性チェックを通らないため。
- 外部依存は増やさない方針。MLX（mlx-swift / mlx-swift-lm）と、その推移依存
  （swift-transformers）だけにとどめる。バージョンは `project.yml` で固定する。
