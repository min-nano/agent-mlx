#!/usr/bin/env bash
#
# stamp-app.sh — ビルド済みの .app へビルドスタンプを書き込む。
#
# スタンプ（GitCommit / GitBranch / BuildChannel / BuiltAt / CFBundleVersion）は
# 自動アップデート（MLXChatUpdater の UpdateFeed）がリリースと突き合わせる鍵。
# 「いま入っているのはどのコミットか」が分からないと、更新の要否を判定できない。
#
# xcodebuild のビルド設定ではなく後から書き込むのは、同じビルド成果物を
# チャンネル違い（stable / dev）で再利用できるようにするため、かつ Info.plist の
# テンプレートを 1 つに保つため。
#
# 使い方:
#   scripts/stamp-app.sh <.app のパス>
#
# 環境変数（CI が渡す。省略時は unknown）:
#   MLX_COMMIT        ビルド元コミット（7 桁短縮）
#   MLX_BRANCH        ビルド元ブランチ
#   MLX_CHANNEL       stable | dev
#   MLX_BUILD_NUMBER  CI の連番 → CFBundleVersion
#
set -euo pipefail

APP="${1:?スタンプ先の .app を指定してください}"
PLIST="$APP/Contents/Info.plist"

# iOS の .app は Contents/ を持たない（バンドル直下に Info.plist がある）。
if [ ! -f "$PLIST" ]; then
	PLIST="$APP/Info.plist"
fi
[ -f "$PLIST" ] || { echo "error: Info.plist が見つかりません: $APP" >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }

# Set はキーが無いと失敗するので、無ければ Add する。Info.plist の
# テンプレートには 4 つとも書いてあるが、将来テンプレートを差し替えても
# 壊れないようにしておく。
set_or_add() {
	local key="$1" value="$2"
	if ! plist "Set :$key $value" 2>/dev/null; then
		plist "Add :$key string $value"
	fi
}

set_or_add GitCommit "${MLX_COMMIT:-unknown}"
set_or_add GitBranch "${MLX_BRANCH:-unknown}"
set_or_add BuildChannel "${MLX_CHANNEL:-unknown}"
set_or_add BuiltAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -n "${MLX_BUILD_NUMBER:-}" ]; then
	set_or_add CFBundleVersion "$MLX_BUILD_NUMBER"
fi

echo "stamped: $PLIST"
plist "Print :GitBranch"
plist "Print :GitCommit"
plist "Print :BuildChannel"
