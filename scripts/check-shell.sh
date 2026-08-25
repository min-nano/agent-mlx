#!/usr/bin/env bash
#
# check-shell.sh — シェルスクリプトの機械的な検査。
#
# 見るのは 2 つだけ。
#
#   1. bash -n（構文）
#   2. 変数展開の直後にマルチバイト文字が続いていないか
#
# 2 が要る理由（実機で踏んだ）: macOS に標準で入っている bash は 3.2 で、
#
#     say "ビルドします（team=$TEAM_ID）"
#
# のように `$TEAM_ID` の直後へ全角文字が続くと、その**バイトを変数名に含めて
# しまう**ことがある（`isalnum()` に負の char を渡す古い実装のため）。結果、
#
#     line 333: TEAM_ID?: unbound variable
#
# で落ちる。CI のランナーには新しい bash が入っていて再現しないので、**この検査が
# 無いと気づけない**。このリポジトリはメッセージが全部日本語なので、必ずまた踏む。
#
# 直し方は波括弧で閉じるだけ:  "…（team=${TEAM_ID}）"
#
# 使い方: scripts/check-shell.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

for script in scripts/*.sh; do
	if ! bash -n "$script"; then
		echo "::error file=${script}::bash -n に失敗しました"
		status=1
	fi
done

python3 - <<'CHECK_PY' || status=1
import glob
import re
import sys

# コメント行は展開されないので対象外。
pattern = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])")
failed = False

for path in sorted(glob.glob("scripts/*.sh")):
	with open(path, encoding="utf-8") as handle:
		for number, line in enumerate(handle, 1):
			if line.lstrip().startswith("#"):
				continue
			for match in pattern.finditer(line):
				name = match.group(1)
				print(
					"::error file=%s,line=%d::$%s の直後にマルチバイト文字があります。"
					"macOS の bash 3.2 が変数名に取り込んでしまうので ${%s} と書いてください"
					% (path, number, name, name))
				failed = True

sys.exit(1 if failed else 0)
CHECK_PY

if [ "$status" = "0" ]; then
	echo "check-shell: ok（$(ls scripts/*.sh | wc -l | tr -d ' ') 本）"
fi
exit "$status"
