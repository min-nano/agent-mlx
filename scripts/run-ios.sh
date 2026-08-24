#!/usr/bin/env bash
#
# run-ios.sh — 署名付きでビルドして iPhone へ転送し、起動するところまでを 1 コマンドで。
#
#   scripts/run-ios.sh
#
# Xcode の GUI を開かずに実機で試せるようにするためのスクリプト。中身は
#
#   1. Metal ツールチェーンの確認（Xcode 26 以降は別ダウンロードのため）
#   2. project.yml → MLXChat.xcodeproj（無ければ生成）
#   3. チームと接続中のデバイスを解決
#   4. xcodebuild（**署名あり**・-allowProvisioningUpdates）
#   5. xcrun devicectl で転送
#   6. xcrun devicectl で起動
#
# **scripts/xcode-build.sh とは別物**であることに注意。あちらは証明書を持たない
# CI 用で、署名を切ってビルドする。こちらは手元の Apple ID で署名する。同じ
# スクリプトにまとめると「CI で署名してしまう / 手元で署名し忘れる」がどちらも
# 起こり得るので、意図的に分けてある。
#
# 使い方:
#   scripts/run-ios.sh                 Release でビルド → 転送 → 起動
#   scripts/run-ios.sh --debug         Debug でビルド（速度は落ちる。開発用）
#   scripts/run-ios.sh --no-launch     転送まで（起動しない）
#   scripts/run-ios.sh --build-only    ビルドまで（転送しない）
#   scripts/run-ios.sh --list          使えるチームとデバイスを一覧して終了
#
# 設定（環境変数、または .mlxchat-local.env に書く。後者は git 管理外）:
#   MLX_TEAM_ID    署名に使う Team ID（10 文字）。省略時は Xcode の設定から自動検出
#   MLX_BUNDLE_ID  バンドル ID。既定の com.minnano.mlxchat が他人に取られている
#                  ときに自分のものへ差し替える
#   MLX_DEVICE     転送先。デバイス名の一部か UDID。省略時は接続中の 1 台
#
# 前提（一度だけ手でやる必要があるもの）:
#   * Xcode に Apple ID を登録してある（Settings → Accounts）
#   * iPhone がペアリング済みで、デベロッパモードが有効
#   * その iPhone で一度 Xcode から実行し、デバイス登録とプロファイル作成が
#     済んでいる（無料アカウントでは、初回だけ GUI を通したほうが確実）
#   * 初回起動時に iPhone 側で開発者を信頼する
#     （設定 → 一般 → VPN とデバイス管理）
#   詳しくは docs/install-ios.md。
#
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="MLXChat-iOS"
CONFIGURATION="Release"
DERIVED="${DERIVED_DATA:-$PWD/.derived}"
SPM="${SPM_DIR:-$PWD/.spm}"
DO_INSTALL=1
DO_LAUNCH=1
LIST_ONLY=0

# 手元だけの設定を置く場所（.gitignore 済み）。
if [ -f .mlxchat-local.env ]; then
	# shellcheck disable=SC1091
	. ./.mlxchat-local.env
fi

while [ "$#" -gt 0 ]; do
	case "$1" in
		--debug) CONFIGURATION="Debug" ; shift ;;
		--release) CONFIGURATION="Release" ; shift ;;
		--no-launch) DO_LAUNCH=0 ; shift ;;
		--build-only) DO_INSTALL=0 ; DO_LAUNCH=0 ; shift ;;
		--list) LIST_ONLY=1 ; shift ;;
		--device) MLX_DEVICE="${2:-}" ; shift 2 ;;
		--team) MLX_TEAM_ID="${2:-}" ; shift 2 ;;
		-h | --help) sed -n '2,45p' "$0" ; exit 0 ;;
		*) echo "run-ios: 未知のオプション: $1" >&2 ; exit 2 ;;
	esac
done

die() {
	echo "run-ios: error: $1" >&2
	exit 1
}

say() {
	echo "==> $1"
}

command -v xcodebuild >/dev/null 2>&1 || die "Xcode が要ります（xcodebuild が見つかりません）"
command -v python3 >/dev/null 2>&1 || die "python3 が要ります（デバイス一覧の解釈に使います）"

# ---------------------------------------------------------------------------
# チーム（署名に使う Team ID）
#
# Xcode に登録した Apple ID の情報は com.apple.dt.Xcode の設定に入っている。
# defaults export → plutil で JSON にすれば確実に読める（`defaults read` の
# 旧形式 plist を正規表現で削るより壊れにくい）。
# ---------------------------------------------------------------------------

xcode_teams_json() {
	defaults export com.apple.dt.Xcode - 2>/dev/null |
		plutil -convert json -o - - 2>/dev/null || true
}

list_teams() {
	xcode_teams_json | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for account, teams in (data.get("IDEProvisioningTeams") or {}).items():
    for team in teams or []:
        free = "無料" if team.get("isFreeProvisioningProfile") in (1, True, "YES") else "有料"
        print("%s\t%s\t%s\t%s" % (team.get("teamID", "?"), free,
                                  team.get("teamName", "?"), account))
'
}

resolve_team() {
	if [ -n "${MLX_TEAM_ID:-}" ]; then
		printf '%s\n' "$MLX_TEAM_ID"
		return 0
	fi
	local ids
	ids="$(list_teams | cut -f1 | sort -u)"
	local count
	count="$(printf '%s' "$ids" | grep -c . || true)"
	if [ "$count" = "1" ]; then
		printf '%s\n' "$ids"
		return 0
	fi
	return 1
}

# ---------------------------------------------------------------------------
# デバイス
# ---------------------------------------------------------------------------

devices_tsv() {
	local out
	out="$(mktemp)"
	xcrun devicectl list devices --json-output "$out" >/dev/null 2>&1 || {
		rm -f "$out"
		return 1
	}
	python3 - "$out" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    data = json.load(handle)
for device in (data.get("result") or {}).get("devices") or []:
    hardware = device.get("hardwareProperties") or {}
    if hardware.get("platform") != "iOS":
        continue
    connection = device.get("connectionProperties") or {}
    print("%s\t%s\t%s" % (
        hardware.get("udid", "?"),
        (device.get("deviceProperties") or {}).get("name", "?"),
        connection.get("tunnelState", "?")))
PY
	rm -f "$out"
}

resolve_device() {
	local all
	all="$(devices_tsv)" || return 1
	[ -n "$all" ] || return 1
	if [ -n "${MLX_DEVICE:-}" ]; then
		printf '%s\n' "$all" | awk -F'\t' -v want="$MLX_DEVICE" \
			'index($1, want) || index($2, want) { print $1; exit }'
		return 0
	fi
	# 指定が無ければ、繋がっている 1 台を使う。複数あるときは選べないので失敗させる。
	local connected count
	connected="$(printf '%s\n' "$all" | awk -F'\t' '$3 != "unavailable" { print $1 }')"
	count="$(printf '%s' "$connected" | grep -c . || true)"
	if [ "$count" = "1" ]; then
		printf '%s\n' "$connected"
		return 0
	fi
	return 1
}

# ---------------------------------------------------------------------------
# --list
# ---------------------------------------------------------------------------

if [ "$LIST_ONLY" = "1" ]; then
	echo "Team ID（MLX_TEAM_ID に入れる値）:"
	if [ -n "$(list_teams)" ]; then
		list_teams | awk -F'\t' '{printf "  %s  [%s]  %s  (%s)\n", $1, $2, $3, $4}'
	else
		echo "  （見つかりません。Xcode → Settings → Accounts で Apple ID を追加してください）"
	fi
	echo
	echo "iOS デバイス（MLX_DEVICE に入れる値）:"
	if devices_tsv >/dev/null 2>&1 && [ -n "$(devices_tsv)" ]; then
		devices_tsv | awk -F'\t' '{printf "  %s  %s  [%s]\n", $1, $2, $3}'
	else
		echo "  （見つかりません。ケーブル接続と「このコンピュータを信頼」、"
		echo "    デベロッパモードの有効化を確認してください）"
	fi
	exit 0
fi

# ---------------------------------------------------------------------------
# 準備
# ---------------------------------------------------------------------------

# Xcode 26 以降、Metal のコンパイラは別ダウンロード。mlx-swift は .metal を
# 丸ごとコンパイルするので、無いとビルドが落ちる。
if ! xcrun metal --version >/dev/null 2>&1; then
	say "Metal ツールチェーンを取得します（初回のみ・数分）"
	xcodebuild -downloadComponent MetalToolchain ||
		die "Metal ツールチェーンを用意できませんでした"
fi

if [ ! -d MLXChat.xcodeproj ]; then
	say "Xcode プロジェクトを生成します"
	scripts/generate-xcodeproj.sh
fi

TEAM_ID="$(resolve_team || true)"
[ -n "$TEAM_ID" ] || die "$(
	printf '%s\n' \
		"署名に使う Team ID を決められませんでした。" \
		"  scripts/run-ios.sh --list  で候補を確認し、" \
		"  echo 'MLX_TEAM_ID=XXXXXXXXXX' >> .mlxchat-local.env" \
		"のように設定してください（Xcode に Apple ID を登録済みであることが前提です）。"
)"

if [ "$DO_INSTALL" = "1" ]; then
	UDID="$(resolve_device || true)"
	[ -n "$UDID" ] || die "$(
		printf '%s\n' \
			"転送先の iPhone を決められませんでした。" \
			"  scripts/run-ios.sh --list  で接続中のデバイスを確認し、" \
			"  echo 'MLX_DEVICE=<名前か UDID>' >> .mlxchat-local.env" \
			"のように指定してください（複数繋がっているときは必須です）。"
	)"
	DESTINATION="platform=iOS,id=$UDID"
else
	UDID=""
	DESTINATION="generic/platform=iOS"
fi

# ---------------------------------------------------------------------------
# ビルド（署名あり）
# ---------------------------------------------------------------------------

say "ビルドします（$CONFIGURATION / team=$TEAM_ID）"
if [ "$CONFIGURATION" = "Debug" ]; then
	echo "    ※ Debug は最適化が効かないので tok/s は実力より落ちます"
fi
echo "    ※ 初回は MLX を丸ごとビルドするため 30 分以上かかります"

BUILD_ARGS=(
	-project MLXChat.xcodeproj
	-scheme "$SCHEME"
	-configuration "$CONFIGURATION"
	-destination "$DESTINATION"
	-derivedDataPath "$DERIVED"
	-clonedSourcePackagesDirPath "$SPM"
	-skipPackagePluginValidation
	-skipMacroValidation
	# 手元の Apple ID でプロファイルを作らせる。無料アカウントでは、初回だけ
	# Xcode の GUI から一度実行しておくと確実（デバイス登録が済む）。
	-allowProvisioningUpdates
	CODE_SIGN_STYLE=Automatic
	"DEVELOPMENT_TEAM=$TEAM_ID"
)
if [ -n "${MLX_BUNDLE_ID:-}" ]; then
	BUILD_ARGS+=("PRODUCT_BUNDLE_IDENTIFIER=$MLX_BUNDLE_ID")
fi

xcodebuild build "${BUILD_ARGS[@]}"

APP="$DERIVED/Build/Products/$CONFIGURATION-iphoneos/MLXChat.app"
[ -d "$APP" ] || die "ビルド成果物が見つかりません: $APP"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")"
say "できました: $APP （$BUNDLE_ID）"

if [ "$DO_INSTALL" = "0" ]; then
	exit 0
fi

# ---------------------------------------------------------------------------
# 転送と起動
# ---------------------------------------------------------------------------

say "転送します（$UDID）"
xcrun devicectl device install app --device "$UDID" "$APP"

if [ "$DO_LAUNCH" = "0" ]; then
	exit 0
fi

say "起動します"
if ! xcrun devicectl device process launch \
	--device "$UDID" --terminate-existing "$BUNDLE_ID"; then
	echo
	echo "起動できませんでした。初回は iPhone 側で開発者を信頼する必要があります:"
	echo "  設定 → 一般 → VPN とデバイス管理 → デベロッパ APP → 自分の Apple ID → 信頼"
	echo "信頼したあと、ホーム画面から起動するか、このスクリプトをもう一度実行してください。"
	exit 1
fi
