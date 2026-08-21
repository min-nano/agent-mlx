# MLX Chat

iPhone と Mac の上で、**ローカルに**大規模言語モデルを動かすチャットアプリです。
Apple の [MLX](https://github.com/ml-explore/mlx-swift)（Apple Silicon 向けの
機械学習フレームワーク）を使い、モデルの重みを端末へダウンロードして、
そこで推論します。**サーバーへは一切送りません**（初回のモデルダウンロードだけが
ネットワークを使い、以降はオフラインで動きます）。

作った動機は「MLX が実機でどれくらい動くのかを確かめたい」でした。なので
このアプリは答えを出すだけでなく、**そのときの速度を必ず一緒に出します**。

| | |
| --- | --- |
| 生成速度 | tok/s（応答ごとに吹き出しの下へ） |
| 最初の 1 文字まで | TTFT（体感速度はほぼこれで決まる） |
| プロンプト処理速度 | 長い会話履歴を食わせたときの待たされ具合 |
| GPU メモリのピーク | iPhone で「動くかどうか」を決める数字 |

さらに **ベンチマーク画面**があり、同じプロンプトを N 回まわして中央値・最小・
最大・ウォームアップとの差を出します（`mlxchat-cli bench` でも同じことができます）。

推論モデル（Qwen3 / SmolLM3 など）の **`<think>` は答えと分けて折りたたみ表示**
します。考えている間は自動で開き、答えが出たら畳まれます（手で開閉したらそちらが
優先）。思考はモデルへの履歴には渡しません — コンテキストを浪費して品質も落ちる
ためです。

---

## 対応環境

| | 要件 |
| --- | --- |
| macOS | **Apple Silicon**（M シリーズ）の macOS 14 以降 |
| iOS | **iPhone / iPad**（A シリーズ）の iOS 17 以降 |

- **Intel Mac では動きません。** MLX は Metal の GPU family を要求します。
- **iOS シミュレータでも動きません**（同じ理由）。実機だけです。
- メモリが実質的な上限になります。詳しくは下の「どのモデルが動くか」。

## 入手する

CI が push のたびにビルドして、GitHub Releases に置いています。

| タグ | 中身 |
| --- | --- |
| `stable` | `main` の最新（安定版） |
| `dev-<ブランチ名>` | PR ごとの開発版（プレリリース） |

アセットは 3 つです。

| ファイル | 何 |
| --- | --- |
| `MLXChat.app.zip` | macOS アプリ（ad-hoc 署名済み） |
| `MLXChat.ipa` | iOS アプリ（**未署名**） |
| `mlxchat-cli.zip` | macOS の CLI 単体 |

### macOS

1. `MLXChat.app.zip` を展開して `MLXChat.app` を「アプリケーション」へ移動。
2. 初回起動は Gatekeeper に止められます（Apple Developer ID 署名も公証もして
   いないため）。**右クリック →「開く」**、または一度だけ次を実行してください。

   ```sh
   xattr -dr com.apple.quarantine /Applications/MLXChat.app
   ```

3. 2 回目以降は自動アップデートが使えます（設定 → アップデート）。

CLI はアプリの中に同梱されています。PATH に通すなら:

```sh
sudo ln -sf /Applications/MLXChat.app/Contents/MacOS/mlxchat-cli /usr/local/bin/mlxchat-cli
```

### iOS

`MLXChat.ipa` は**未署名**です。Apple Developer 証明書を CI に置かない方針なので、
そのままでは iPhone に入りません。次のどちらかで導入してください。

- **自分の Apple ID で署名する**（無料。7 日ごとに再署名が必要）
  [Sideloadly](https://sideloadly.io/) や [AltStore](https://altstore.io/) に
  `.ipa` を渡すと、無料の開発者アカウントで署名して転送してくれます。
- **自分で Xcode からビルドする**（下の「自分でビルドする」）。手元に Apple ID を
  設定した Xcode があるなら、こちらが一番手早いです。

> **iOS 版に自動アップデートはありません。** iOS ではアプリが自分自身を
> 差し替えられないためです（新しいビルドは入れ直してください）。

---

## 使う

### 1. モデルを選ぶ

「モデル」画面に、動作を確認済みのモデルが小さい順に並んでいます。

| モデル | サイズ | 目安 |
| --- | --- | --- |
| SmolLM 135M | 90 MB | とにかく軽い。動作確認用 |
| Qwen3 0.6B | 350 MB | iPhone でも余裕。日本語もそこそこ |
| Gemma 3 1B (QAT) | 700 MB | 量子化前提の学習で、このサイズでは品質が良い |
| Qwen3 1.7B | 1.0 GB | **既定。** iPhone での常用候補 |
| Llama 3.2 3B / SmolLM3 3B | 1.7〜1.8 GB | 8GB の iPhone なら |
| Qwen3 4B | 2.3 GB | 日本語の実用ライン。Mac の入門的な本命 |
| Mistral 7B / Qwen3 8B | 4.1〜4.6 GB | 16GB Mac の常用上限あたり |
| Gemma 2 9B | 5.2 GB | 日本語が得意。コンテキストは短め |
| Qwen3 30B A3B (MoE) | 17 GB | 32GB 以上の Mac。MoE なので驚くほど速い |

最初の送信でダウンロードが始まります（進捗が出ます）。一度落とせば以降は
オフラインで動きます。

### 2. どのモデルが動くか

**iPhone はアプリごとにメモリ上限があり、超えると警告なしに終了させられます**
（jetsam）。MLX の重みはユニファイドメモリに載るので、この上限にそのまま数えられます。

アプリは搭載メモリから使える量を見積もり（iOS は搭載の 50%、macOS は 70%）、
入らないモデルには警告を出します。**選べなくはしていません** — 見積もりは概算で、
実機のほうが強いこともあるからです。

会話が長くなると KV キャッシュが重みより大きくなります。iPhone で会話が続かなく
なったら、設定の

- **KV キャッシュ量子化** を `8bit`（さらに厳しければ `4bit`）
- **履歴の上限** を減らす

の順に試してください。

### 3. 思考を読む・畳む

Qwen3 や SmolLM3 は答えの前に考えます。その部分は吹き出しの上に
「🧠 考えた過程（N 文字）」として畳まれていて、タップ／クリックで開けます。

- 考えている間は**自動で開いて**います（何も起きていないように見えないため）
- 答えが出ると**自動で畳まれます**
- 一度でも手で開閉すると、以降はその状態を保ちます

思考が長すぎて答えに辿り着かないことがあります（上限に達した場合）。そのときは
吹き出しがその旨を伝えるので、設定で最大トークン数を増やすか、小さいモデルに
替えてください。

### 4. 速度を測る

「ベンチマーク」画面で、同じプロンプトを N 回まわします。

- **ウォームアップ**（既定 1 回）は集計から外します。1 回目は重みのメモリ配置と
  Metal のカーネル構築を含むので目に見えて遅く、「2 回目以降の実力」とは別の
  数字だからです（初回の重さも `warmup` として結果に残ります）。
- 代表値は**中央値**です。平均だとサーマルスロットリングや他アプリの割り込みに
  引きずられます。

---

## CLI（macOS）

GUI と同じ機能に、同じ語彙で届きます（`Sources/MLXChatCore/APICommand.swift` が
唯一の定義です）。

```sh
# 1 往復
mlxchat-cli "Apple Silicon のユニファイドメモリの利点を 3 つ"

# モデルとつまみを指定
mlxchat-cli chat --model mlx-community/Qwen3-4B-4bit \
                 --system "簡潔な日本語で" --temperature 0.3 --max-tokens 400 \
                 --prompt "MLX と Core ML の違いは？"

# 標準入力から（パイプで使う）
cat draft.md | mlxchat-cli chat --system "誤字を直して"

# 速度を測る
mlxchat-cli bench --model mlx-community/Qwen3-1.7B-4bit --runs 5 --max-tokens 256

# 思考は標準エラーへ流れるので、答えだけを取り出せる
mlxchat-cli "考えて答えて" > answer.txt      # answer.txt には答えだけ
mlxchat-cli "考えて答えて" 2> think.txt      # think.txt に思考が残る

# 使えるモデルの一覧（この端末で動くかも出る）
mlxchat-cli models
```

生成された本文だけが標準出力へ、進捗・実測値・**推論モデルの思考**は標準エラーへ
出ます。したがって

```sh
mlxchat-cli "要約して" < input.txt > answer.txt
```

がそのまま使えます。

## URL スキーム（iOS / macOS）

他のアプリ（ショートカット、Alfred、Raycast、スクリプト）から呼べます。

```
mlxchat://chat?prompt=<テキスト>[&model=<id>][&system=<テキスト>]
              [&temperature=0.7][&topP=0.95][&maxTokens=512]
              [&repetitionPenalty=1.1][&kvBits=8][&history=20]
mlxchat://bench?[model=<id>][&prompt=<テキスト>][&runs=3][&warmup=1]
```

```sh
open "mlxchat://chat?prompt=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF"
```

設定画面には「いまの設定を CLI で再現するコマンド」が出るので、GUI で詰めてから
コピーしてスクリプトに貼れます。

## ライブラリとして使う

純ロジック（会話・モデル一覧・つまみ・集計）は MLX に依存しない SwiftPM
パッケージです。自分のアプリに `MLXChatCore` だけを組み込むこともできます。

```swift
.package(url: "https://github.com/min-nano/agent-mlx", branch: "main")
```

---

## 自分でビルドする

### 純ロジックだけ（速い・どの Mac でも）

```sh
swift build
swift test
```

外部依存がゼロなので数十秒で終わります。MLX はここには入っていません。

### アプリ（Apple Silicon + Xcode 26 以降）

```sh
scripts/generate-xcodeproj.sh   # project.yml → MLXChat.xcodeproj（XcodeGen）
open MLXChat.xcodeproj
```

スキームは 3 つです。

| スキーム | 対象 |
| --- | --- |
| `MLXChat-macOS` | macOS アプリ（arm64 のみ） |
| `MLXChat-iOS` | iOS アプリ（**実機のみ**。シミュレータは非対応） |
| `mlxchat-cli` | コマンドライン版 |

> `.xcodeproj` はリポジトリに入れていません。`.pbxproj` は差分が読めず、競合が
> 解決できず、Xcode が勝手に書き換えるからです。**原本は `project.yml`** で、
> ローカルでも CI でも同じスクリプトが生成します。

初回ビルドは **30 分以上**かかります。mlx-swift が MLX の C++ と Metal カーネルを
丸ごとソースからビルドするためです。2 回目以降は増分ビルドになります。

Xcode 26 以降、Metal のコンパイラは別ダウンロードのコンポーネントです。
入っていない場合は:

```sh
xcodebuild -downloadComponent MetalToolchain
```

---

## リポジトリの構成

```
Sources/          SwiftPM パッケージ。純ロジックのみ・外部依存ゼロ・テストがある
  MLXChatCore/    会話・モデル一覧・つまみ・外部連携 API・端末の見立て
  MLXChatUpdater/ 自動アップデート（macOS）
Apps/             Xcode プロジェクトがビルドする層。ここだけが MLX を引く
  MLXChatEngine/  MLX の唯一のラッパー
  MLXChatUI/      SwiftUI（iOS と macOS で共通）
  iOS/ macOS/ cli/
Tests/            swift test（純ロジックだけ）
packaging/        Info.plist・アイコン（生成物）
scripts/          プロジェクト生成・スタンプ・ipa 化・CI デバッグ・CI 待機
docs/design.md    設計ノート（なぜこの形なのか）
docs/roadmap.md   この先やりたいこと
project.yml       Xcode プロジェクトの唯一の定義（XcodeGen）
```

## 設計を読む

**[docs/design.md](docs/design.md) — 設計ノート（なぜこの形なのか）**

- なぜ MLX に触る層を 1 つに絞るのか
- なぜ GUI に判断を置かないのか
- iPhone で落ちないためにどう見積もっているのか
- 推論モデルの思考をどう切り分けているのか（ストリーミングの難所つき）
- なぜテストが数十秒で終わるのか
- **意図的にやらなかったこと**と、その理由
- 片方だけ変えると壊れる「対」の一覧

作業時の規則は [CLAUDE.md](CLAUDE.md)、この先の候補は
[docs/roadmap.md](docs/roadmap.md) にあります。

## CI

| ワークフロー | いつ | 何を |
| --- | --- | --- |
| `test.yml` | push(main) / PR | `swift test` + カバレッジを PR にコメント（ゲート付き） |
| `build.yml` | push(main) / PR | macOS と iOS を**並列**にビルド → リリース公開 |
| `ci-debug.yml` | 手動のみ | CI 上で 1 コマンド動かす（調査用） |
| `cleanup-dev-release.yml` | ブランチ削除 | そのブランチの dev プレリリースを掃除 |

テストとビルドは互いに繋がっておらず並列に走ります。ビルドの結果を待たずに
テストの結果が見え、テストの結果を待たずにビルドが進みます。

## ライセンスと出どころ

- モデルの重みは [mlx-community](https://huggingface.co/mlx-community) の
  公開リポジトリから取得します。ライセンスは各モデルのものに従ってください。
- CI・リリース・自動アップデート・CI デバッグの構成は姉妹リポジトリ
  `min-nano/photogrammetry` からの移植です。
