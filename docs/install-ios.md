# iOS 版を iPhone に入れる

**iPhone 実機でしか動きません。**MLX は Metal の GPU family を要求するので、
iOS シミュレータでは動作しません（Xcode のデスティネーションにも出ないように
してあります）。

入れ方は 2 通りあります。

| | 方法 A: Xcode からビルドして転送 | 方法 B: 配布された `.ipa` に署名 |
| --- | --- | --- |
| 必要なもの | Apple Silicon Mac + Xcode | Mac または Windows + 署名ツール |
| 初回の所要 | **30 分以上**（MLX を丸ごとビルド） | 5 分ほど |
| 2 回目以降 | 数分（増分ビルド） | 5 分ほど |
| コードを直せるか | できる | できない |
| 速度を正しく測れるか | **できる**（Release でビルドすれば） | できる |

手元に Xcode があるなら **方法 A** が確実です。以下はその詳細で、方法 B は
最後にまとめてあります。

---

## 方法 A: Xcode からビルドして実機へ転送する

### 用意するもの

- **Apple Silicon の Mac**（Intel Mac では MLX がビルドできません）
- **Xcode 26 以降**
- **iPhone（iOS 17 以降）** と、Mac に繋ぐケーブル
- **Apple ID**（無料で構いません。App Store のものでよい）
- iPhone の空き容量 — モデルの重みぶん。まずは **2 GB** ほど見ておけば足ります
  （Qwen3 1.7B で約 1 GB）

### 1. Metal ツールチェーンを入れる

Xcode 26 から、Metal のコンパイラは**別ダウンロード**のコンポーネントに
なりました。mlx-swift は `.metal` を丸ごとコンパイルするので、これが無いと
ビルドが `cannot execute tool 'metal'` で止まります。

```sh
xcodebuild -downloadComponent MetalToolchain
```

（Xcode の Settings → Components からでも入れられます。すでに入っていれば
すぐ終わります。）

### 2. リポジトリを取得して Xcode プロジェクトを生成する

`.xcodeproj` はリポジトリに入れていません（差分が読めず競合も解決できないため）。
原本の `project.yml` から生成します。

```sh
git clone https://github.com/min-nano/agent-mlx.git
cd agent-mlx
scripts/generate-xcodeproj.sh    # XcodeGen が無ければ Homebrew で入ります
open MLXChat.xcodeproj
```

### 3. Xcode に Apple ID を登録する

Xcode → **Settings** → **Accounts** → 左下の **+** → Apple ID → サインイン。

無料の Apple ID でも「**Personal Team**」が自動で作られ、これで実機に入れられます。

### 4. 署名（Signing）を設定する

左のファイル一覧のいちばん上 **MLXChat**（青いアイコン）→ TARGETS の
**MLXChat-iOS** → **Signing & Capabilities** タブ。

1. **Automatically manage signing** にチェック（既定でチェック済みのはずです）
2. **Team** に自分の Personal Team を選ぶ

ここで次のエラーが出ることがあります。

```
Failed to register bundle identifier
The app identifier "com.minnano.mlxchat" cannot be registered to your development team.
```

バンドル ID は Apple 全体で一意なので、他の誰かが登録済みだと弾かれます。
その場合は **`project.yml` を直してから再生成**してください（Xcode 上で
書き換えても、次に生成し直すと元に戻ります）。

```yaml
# project.yml の MLXChat-iOS ターゲット
        PRODUCT_BUNDLE_IDENTIFIER: com.example.mlxchat   # ← 自分のものに変える
```

```sh
scripts/generate-xcodeproj.sh
```

### 5. iPhone をデベロッパモードにする

iOS 16 以降、自分でビルドしたアプリを動かすには iPhone 側の設定が要ります。

1. iPhone を Mac に繋ぎ、「このコンピュータを信頼しますか？」に **信頼**
2. iPhone の **設定** → **プライバシーとセキュリティ** → **デベロッパモード** → オン
3. 再起動を求められるので再起動 → 起動後に確認ダイアログで **オンにする**

> **デベロッパモードの項目が見当たらないとき**は、一度 Xcode から実行を試みて
> ください。Mac に接続して Xcode がデバイスを認識すると項目が現れます。

### 6. ビルド構成を Release にする（速度を測るなら必須）

Xcode の ⌘R は既定で **Debug** ビルドを使います。Debug は Swift も C++ も
最適化なしでコンパイルされるので、**tok/s が実力より大きく落ちます**。
「MLX の実力を確かめる」のが目的なら、ここは必ず変えてください。

**Product** → **Scheme** → **Edit Scheme…** → 左の **Run** → **Info** タブ →
**Build Configuration** を **Release** に。

（コードを直しながら動かしたいときは Debug のままで構いません。そのときの
速度は参考値として見てください。）

### 7. 実行する

1. Xcode 上部のデスティネーション（スキームの右）で **自分の iPhone** を選ぶ
2. **⌘R**

**初回は 30 分以上かかります。**mlx-swift が MLX の C++ と Metal カーネルを
丸ごとソースからビルドするためです。2 回目以降は増分ビルドで数分です。

> ケーブルを外して使いたいときは、**Window** → **Devices and Simulators** →
> 自分の iPhone → **Connect via network** にチェックを入れると、以降は
> 同じ Wi-Fi にいれば無線で転送できます。

### 8. iPhone 側で開発者を信頼する

初回起動時に「**信頼されていないデベロッパ**」と言われて起動できません。

iPhone の **設定** → **一般** → **VPN とデバイス管理** → **デベロッパ APP** の
下にある自分の Apple ID → **"（Apple ID）" を信頼** → **信頼**。

これでアプリが起動します。

### 9. 最初の生成

初回の送信でモデルの重みをダウンロードします（既定の Qwen3 1.7B で約 1 GB）。
**Wi-Fi でつないだ状態**で、アプリを前面にしたまま待ってください。
一度落としてしまえば、以降は機内モードでも動きます。

---

## 無料 Apple ID の制約

無料アカウント（Personal Team）で署名したアプリには、Apple の制限があります。

| | 無料 Apple ID | 有料の Apple Developer Program |
| --- | --- | --- |
| アプリの有効期間 | **7 日**で起動できなくなる | 1 年 |
| 同時に入れられる自作アプリ | 3 つまで | 制限なし（デバイス登録数の上限内） |
| App ID の作成 | 7 日あたり 10 個まで | 制限なし |

**7 日で切れたら、Xcode から ⌘R でもう一度入れ直すだけ**で復活します。
バンドル ID が同じであれば、**会話もダウンロード済みモデルも消えません**
（アプリを削除した場合は消えます）。

---

## 方法 B: 配布された `.ipa` に署名して入れる

GitHub Releases の `MLXChat.ipa` は**未署名**です（証明書を CI に置かない方針
のため）。そのままでは iPhone に入らないので、自分の Apple ID で署名し直します。

1. リリースから `MLXChat.ipa` をダウンロード
   - `stable` … `main` の最新
   - `dev-<ブランチ名>` … PR ごとの開発版
2. 署名ツールに渡す
   - [Sideloadly](https://sideloadly.io/)（Mac / Windows）
   - [AltStore](https://altstore.io/) / SideStore
3. Apple ID を入力すると、署名して iPhone へ転送してくれます
4. 上の **手順 5**（デベロッパモード）と **手順 8**（開発者を信頼）は同じように必要です

有効期間などの制約は方法 A と同じ（無料アカウントなら 7 日）です。

---

## うまくいかないとき

| 症状 | 原因と対処 |
| --- | --- |
| `cannot execute tool 'metal'` | Metal ツールチェーンが無い。**手順 1** を実行 |
| `Signing for "MLXChat-iOS" requires a development team` | **手順 4** で Team を選んでいない |
| `The app identifier ... cannot be registered` | バンドル ID が他の人に使われている。**手順 4** の後半のとおり `project.yml` を直して再生成 |
| `Unable to install ... This provisioning profile cannot be installed` | iPhone がデベロッパモードになっていない。**手順 5** |
| 起動しようとすると「信頼されていないデベロッパ」 | **手順 8** |
| `The maximum number of apps for free development profiles has been reached` | 無料アカウントの 3 アプリ制限。他の自作アプリを消す |
| デスティネーションに iPhone が出ない | ケーブル接続と「信頼」を確認。それでも出なければ Xcode を再起動 |
| シミュレータを選ぶとビルドできない | **仕様です。**MLX は Metal の GPU family を要求するので実機のみ |
| 数分で「メモリ不足」と言われて落ちる | モデルが大きすぎます。設定の **KV キャッシュ量子化**を 8bit に、それでも駄目なら 1 つ小さいモデルへ |
| 生成が遅い気がする | **手順 6** の Release ビルドになっているか確認 |

---

## 関連

- 使い方の全体 → [../README.md](../README.md)
- なぜ署名しないのか、なぜシミュレータ非対応なのか → [design.md](design.md)
