#!/usr/bin/env bash
#
# ci-debug-job.sh — `.github/workflows/ci-debug.yml`（CI debug）のランナー側本体。
#
# ワークフローは「チェックアウト → Xcode 選択 → このスクリプトを 1 回実行」だけを
# 行い、実際の調査コマンドはすべてここに集約する。こうしている理由は 2 つ:
#
#   1. workflow_dispatch は「デフォルトブランチに存在するワークフロー」しか起動でき
#      ないため、ワークフロー本体を頻繁に触ると毎回 main へマージする必要が出る。
#      モードの追加・修正をこのスクリプト側に閉じ込めれば、作業ブランチに push する
#      だけで（dispatch の ref がそのブランチなので）すぐ試せる。
#   2. インライン YAML の run: と違い、独立したシェルスクリプトなので shellcheck に
#      そのままかけられる。
#
# 入力はすべて環境変数（ワークフローが inputs から詰める）:
#
#   MODE     build | test | xcode-mac | xcode-ios | xcode-cli | run-cli | shell
#   ARGS     モードごとの引数
#   SCRIPT   MODE=shell のときに実行する bash スクリプト本文
#
# 出力は「ペイロードマーカー」で挟んだ 1 ブロックとして stdout に出す:
#
#   ===== BEGIN PAYLOAD (mode=...) =====
#   ...
#   ===== END PAYLOAD (exit=N lines_total=N truncated=yes|no) =====
#
# 呼び出し側（scripts/ci-debug.sh）はこのマーカー間だけを抜き出すので、セット
# アップ手順のノイズを読まずに済む。生の全出力は debug-out/ に残し、ワークフローが
# アーティファクトとしてアップロードする（人間用の保険。AI は GitHub MCP で
# アーティファクトを取得できないため、必要な情報は必ずログ側に出すこと）。
#
# 終了ステータスは調査コマンドのものをそのまま返す（＝run の conclusion になる）。
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

MODE="${MODE:-}"
ARGS="${ARGS:-}"
SCRIPT="${SCRIPT:-}"
OUT_DIR="${OUT_DIR:-debug-out}"
DERIVED="${DERIVED_DATA:-$PWD/.derived}"

# ペイロードに載せる最大行数。これを超えたぶんは切り捨て、END マーカーの
# truncated=yes で「全部は見えていない」ことを呼び出し側に明示する（AI が
# 「該当なし」と誤読しないための最重要ポイント）。全文は debug-out/raw.txt に残る。
MAX_LINES="${PAYLOAD_MAX_LINES:-400}"

mkdir -p "$OUT_DIR"
RAW="$OUT_DIR/raw.txt"
PAYLOAD="$OUT_DIR/payload.txt"

# ---------------------------------------------------------------------------
# 小さなヘルパー
# ---------------------------------------------------------------------------

# die <message>: 使い方の誤り。モード実装はサブシェル内で走るので、この exit は
# スクリプト全体ではなくサブシェルだけを終わらせる。メッセージは（stderr ごと）
# RAW に入り、通常どおりペイロードとして出力される — つまり失敗しても呼び出し側は
# 必ずマーカー付きの理由を受け取れる。
die() {
	echo "ci-debug-job: error: $1" >&2
	exit 2
}

# ensure_metal_toolchain: Xcode 26 以降、Metal のコンパイラは**別ダウンロード**の
# コンポーネントになった。mlx-swift は .metal を丸ごとコンパイルするので、これが
# 無いと "cannot execute tool 'metal'" でビルドが落ちる。GitHub のランナー画像に
# 入っているとは限らないため、無ければここで入れる。
ensure_metal_toolchain() {
	if xcrun metal --version >/dev/null 2>&1; then
		echo "# metal toolchain: ok"
		return 0
	fi
	echo "# metal toolchain: downloading…"
	xcodebuild -downloadComponent MetalToolchain || true
	xcrun metal --version || echo "warning: metal ツールチェーンを用意できませんでした"
}

# ensure_project: project.yml から MLXChat.xcodeproj を作る（.xcodeproj は
# リポジトリに入れていない）。
ensure_project() {
	scripts/generate-xcodeproj.sh
}

# xcode_build <scheme> <destination>: 共通のビルド呼び出し。
# 引数の組み立ては scripts/xcode-build.sh に 1 か所だけ置いてある（build.yml と
# 同じものを通す — 片方だけにフラグを足すと「CI では通るが調査では落ちる」が起きる）。
xcode_build() {
	local scheme="$1" destination="$2"
	# shellcheck disable=SC2086
	DERIVED_DATA="$DERIVED" scripts/xcode-build.sh "$scheme" "$destination" Debug $ARGS
}

# ---------------------------------------------------------------------------
# モード実装。すべて stdout/stderr に出し、呼び出し元が RAW へリダイレクトする。
# ARGS は空白区切りの追加フラグとして意図的に word splitting する。
# ---------------------------------------------------------------------------

# build: Sources/ の純ロジックだけを swift build する。MLX を引かないので速い
# （「Core が壊れていないか」を数十秒で確かめたいときはこれ）。
mode_build() {
	echo "# swift build $ARGS"
	echo
	# shellcheck disable=SC2086
	swift build $ARGS
}

# test: swift test。ARGS に追加フラグ（例: '--filter UpdateFeedTests'）。
mode_test() {
	echo "# swift test $ARGS"
	echo
	# shellcheck disable=SC2086
	swift test $ARGS
}

# xcode-mac / xcode-ios / xcode-cli: 実アプリのビルド。MLX（C++ と Metal
# カーネル）を丸ごとビルドするので初回は 30 分以上かかる。
mode_xcode_mac() {
	ensure_metal_toolchain
	ensure_project
	xcode_build "MLXChat-macOS" "platform=macOS,arch=arm64"
}

mode_xcode_ios() {
	ensure_metal_toolchain
	ensure_project
	# MLX はシミュレータでは動かない（Metal の GPU family 要件）ので、
	# 実機向け（generic/platform=iOS）だけをビルドする。
	xcode_build "MLXChat-iOS" "generic/platform=iOS"
}

mode_xcode_cli() {
	ensure_metal_toolchain
	ensure_project
	xcode_build "mlxchat-cli" "platform=macOS,arch=arm64"
}

# run-cli: mlxchat-cli をビルドして実行する。ARGS が CLI の引数になる。
# GPU が要る生成そのものはランナーで動かない可能性が高いが、**その出力自体が
# 調査結果**になる（`models` のように GPU が要らないサブコマンドは普通に動く）。
mode_run_cli() {
	ensure_metal_toolchain
	ensure_project
	local cli_args="$ARGS"
	ARGS=""
	xcode_build "mlxchat-cli" "platform=macOS,arch=arm64" || return $?
	local binary
	binary="$(find "$DERIVED/Build/Products" -name mlxchat-cli -type f | head -1)"
	[ -n "$binary" ] || die "mlxchat-cli の成果物が見つかりません"
	echo
	echo "# $binary $cli_args"
	echo
	# shellcheck disable=SC2086
	"$binary" $cli_args
}

# shell: 逃げ道。固定モードで表現できない一発調査を bash でそのまま流す。
# SCRIPT は環境変数で渡ってくる（YAML へ展開しないのでクォート事故が起きない）。
mode_shell() {
	[ -n "$SCRIPT" ] || die "mode=shell には script が必要です"
	local f="$OUT_DIR/script.sh"
	printf '%s\n' "$SCRIPT" >"$f"
	echo "# bash $f"
	echo
	bash "$f"
}

# ---------------------------------------------------------------------------
# ペイロード出力
# ---------------------------------------------------------------------------

# digest_log: ビルド・テストログ向けの抜粋。診断行（error/FAILED …）を先に、
# その後に末尾の数十行を出す。並列ビルドではエラーが末尾に来るとは限らないので、
# 単純な tail ではなく両方を出している。
digest_log() {
	local hits
	hits="$(grep -nE -- '(^|[^A-Za-z])([Ee]rror|ERROR|FAILED|failed|fatal|warning:|XCTAssert)' "$RAW" | head -n 300)"
	if [ -n "$hits" ]; then
		echo "--- diagnostics (max 300 lines, prefixed with the line number in raw.txt) ---"
		printf '%s\n' "$hits"
		echo
	fi
	echo "--- tail of the log (last 80 lines) ---"
	tail -n 80 "$RAW"
}

# emit_payload <exit-status>: マーカーで挟んだ 1 ブロックを stdout と payload.txt へ。
emit_payload() {
	local status="$1" total truncated="no"
	total="$(wc -l <"$RAW" | tr -d ' ')"

	{
		echo "===== BEGIN PAYLOAD (mode=$MODE) ====="
		if [ "$DIGEST" = "log" ]; then
			digest_log
		else
			head -n "$MAX_LINES" "$RAW"
			if [ "$total" -gt "$MAX_LINES" ]; then
				truncated="yes"
			fi
		fi
		echo "===== END PAYLOAD (exit=$status lines_total=$total truncated=$truncated) ====="
	} >"$PAYLOAD"

	cat "$PAYLOAD"
	emit_annotation
}

# emit_annotation: ペイロードを **チェックラン注釈** としても出す。
#
# なぜ二重に出すか: 呼び出し側がペイロードを取る経路は本来ジョブログだが、ログ API は
# 署名付きの Azure Blob Storage へ 302 で飛ぶ。組織の egress ポリシーがそのホストを
# 拒否している環境（Claude Code のリモートセッションなど）では、コンテナからログ本文を
# 取得できない。一方、注釈は
#
#   GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations
#
# つまり api.github.com だけで読めるうえ、ログのノイズ（セットアップ手順・アーティ
# ファクトアップロード・ポストジョブ後始末）が混ざらない。ワークフローコマンドの
# 仕様で改行は %0A へエスケープする必要がある（% と CR も同様）。
#
# **GitHub は注釈のメッセージを 4096 文字ちょうどで切る**（実測）。しかも切り方は
# 単語の途中でも構わない乱暴なもので、そのままだと END マーカーごと消えて「これで
# 全部だ」と誤読される。そこで自前でバイト予算に収め、切り詰めた旨の 1 行と END
# マーカー行を**必ず**収まる形で残す。全文はジョブログとアーティファクトに残る。
#
# END 行には lines_total が入っているので、注釈側が切られていても「本当は何行
# あったのか」は読み手に伝わる。
emit_annotation() {
	local budget="${ANNOTATION_MAX_BYTES:-3800}" total kept body tail_line notice
	total="$(wc -l <"$PAYLOAD" | tr -d ' ')"
	tail_line="$(tail -n 1 "$PAYLOAD")"
	notice="... (annotation truncated by GitHub's 4096-char limit — the full payload is in the job log and the run artifact)"

	# 予算から「切り詰め通知＋END 行」ぶんを引いた範囲まで、行単位で詰める。
	# 文字数ではなくバイト数で数えるため LC_ALL=C（日本語のエラーメッセージ対策）。
	body="$(LC_ALL=C awk -v limit="$((budget - ${#notice} - ${#tail_line} - 4))" '
		{
			len += length($0) + 1
			if (len > limit) { exit }
			print
		}' "$PAYLOAD")"

	kept="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
	if [ "$kept" -lt "$total" ]; then
		body="$(printf '%s\n%s\n%s' "$body" "$notice" "$tail_line")"
	fi

	body="$(printf '%s\n' "$body" |
		sed -e 's/%/%25/g' -e 's/\r/%0D/g' |
		awk '{printf "%s%%0A", $0}')"
	echo "::notice title=ci-debug payload::${body}"
}

# ---------------------------------------------------------------------------
# 本体
# ---------------------------------------------------------------------------

# ビルド・テスト・CLI 実行のログは「診断行＋末尾」のダイジェストにする。
# 短い出力しか出ないモードは head で十分。
case "$MODE" in
	build | test | xcode-mac | xcode-ios | xcode-cli | run-cli) DIGEST="log" ;;
	*) DIGEST="head" ;;
esac

# モード実装はサブシェルで動かす。die の exit がここで止まるので、使い方の誤りでも
# 必ず emit_payload まで到達する（＝呼び出し側は理由をマーカー付きで受け取れる）。
(
	case "$MODE" in
		build) mode_build ;;
		test) mode_test ;;
		xcode-mac) mode_xcode_mac ;;
		xcode-ios) mode_xcode_ios ;;
		xcode-cli) mode_xcode_cli ;;
		run-cli) mode_run_cli ;;
		shell) mode_shell ;;
		*) die "未知の mode: '$MODE'（build / test / xcode-mac / xcode-ios / xcode-cli / run-cli / shell）" ;;
	esac
) >"$RAW" 2>&1
STATUS=$?

emit_payload "$STATUS"
exit "$STATUS"
