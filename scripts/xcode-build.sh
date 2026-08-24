#!/usr/bin/env bash
#
# xcode-build.sh — アプリ／CLI をビルドする**唯一の**呼び出し。
#
# build.yml（本番のビルド）と ci-debug-job.sh（調査）が同じ関数を通るようにして
# ある。片方だけにフラグを足すと「CI では通るが調査では落ちる（逆もある）」が
# 起きるので、xcodebuild の引数はここでしか組み立てない。
#
# 使い方:
#   scripts/xcode-build.sh <scheme> <destination> [<configuration>] [追加フラグ...]
#
# 例:
#   scripts/xcode-build.sh MLXChat-macOS 'platform=macOS,arch=arm64' Release
#   scripts/xcode-build.sh MLXChat-iOS   'generic/platform=iOS'      Release
#
# 環境変数:
#   DERIVED_DATA   ビルド成果物の置き場所（既定 .derived）
#   SPM_DIR        SwiftPM のソース取得先（既定 .spm。CI がキャッシュする）
#
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${1:?スキーム名を指定してください}"
DESTINATION="${2:?デスティネーションを指定してください}"
CONFIGURATION="${3:-Release}"
shift 3 2>/dev/null || shift "$#"

DERIVED="${DERIVED_DATA:-$PWD/.derived}"
SPM="${SPM_DIR:-$PWD/.spm}"

[ -d MLXChat.xcodeproj ] || scripts/generate-xcodeproj.sh

# なぜ署名を切るか:
#   Apple Developer 証明書を CI に置かない方針なので、ここでは署名せずに
#   ビルドする（macOS 版はこの後 ad-hoc 署名を付け、iOS 版は未署名の .ipa と
#   して配る）。**この指定を project.yml へ書いてはいけない** — プロジェクト
#   自体が「署名しない」になると、手元の Xcode から自分の Apple ID で実機へ
#   入れられなくなる（iOS は未署名アプリのインストールを拒否する）。
#   署名を切るのはこのビルド呼び出しの都合であって、プロジェクトの性質ではない。
#
# なぜ検証をスキップするか:
#   * -skipPackagePluginValidation … mlx-swift の Cmlx ターゲットはビルドツール
#     プラグイン（CudaBuild）を宣言している。Xcode はプラグインの実行前に
#     「利用者の信頼」を要求し、対話的に許可できない CI では
#     "Validate plug-in “CudaBuild” in package “mlx-swift”" で必ず失敗する。
#     プラグインは依存先の公開パッケージのもので、バージョンは project.yml で
#     固定してあるため、ここでスキップして構わない。
#   * -skipMacroValidation … 同じ理由（マクロを使うパッケージが依存に入った
#     ときのため。いまは効いていないが、外すと後で同じ形で落ちる）。
exec xcodebuild build \
	-project MLXChat.xcodeproj \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-destination "$DESTINATION" \
	-derivedDataPath "$DERIVED" \
	-clonedSourcePackagesDirPath "$SPM" \
	-skipPackagePluginValidation \
	-skipMacroValidation \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY= \
	CODE_SIGN_ENTITLEMENTS= \
	DEVELOPMENT_TEAM= \
	"$@"
