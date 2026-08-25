#!/usr/bin/env bash
#
# package-ipa.sh — ビルド済みの iOS .app を .ipa に固める。
#
# .ipa は「Payload/ というディレクトリに .app を入れた zip」でしかない。
# xcodebuild -exportArchive は署名を要求するので、証明書を CI に置かない
# この構成では使えない。かわりに手で固める。
#
# **できあがる .ipa は未署名**で、そのままでは iPhone に入らない。導入方法は
# README を参照（自分の Apple ID で署名し直す / 開発者証明書で再署名する）。
#
# 使い方:
#   scripts/package-ipa.sh <.app のパス> <出力する .ipa のパス>
#
set -euo pipefail

APP="${1:?.app のパスを指定してください}"
OUT="${2:?出力する .ipa のパスを指定してください}"

[ -d "$APP" ] || { echo "error: .app がありません: $APP" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload"
# ditto はシンボリックリンクと実行権限を保ったまま複製できる（cp -R より
# バンドル向き）。
ditto "$APP" "$WORK/Payload/$(basename "$APP")"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# -X で macOS の拡張属性を落とす（他 OS の署名ツールが嫌うことがある）。
(cd "$WORK" && zip -qry -X "ipa.zip" Payload)
mv "$WORK/ipa.zip" "$OUT"

echo "packaged: $OUT ($(du -h "$OUT" | cut -f1))"
