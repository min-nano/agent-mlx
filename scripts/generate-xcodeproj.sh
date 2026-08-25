#!/usr/bin/env bash
#
# generate-xcodeproj.sh — project.yml から MLXChat.xcodeproj を生成する。
#
# .xcodeproj はリポジトリに入れない（.pbxproj は差分が読めず、競合が解決できず、
# Xcode が勝手に書き換えるため）。原本は project.yml で、ローカルでも CI でも
# このスクリプトが同じものを作る。
#
# XcodeGen が無ければ Homebrew で入れる。CI もローカルもこの 1 本で済ませる
# ため、導入まで面倒を見る。
#
# 使い方:
#   scripts/generate-xcodeproj.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
	if ! command -v brew >/dev/null 2>&1; then
		echo "error: xcodegen も Homebrew も見つかりません。" >&2
		echo "       https://github.com/yonaskolb/XcodeGen から入れてください。" >&2
		exit 1
	fi
	echo "xcodegen を Homebrew で導入します…"
	brew install xcodegen
fi

xcodegen generate --spec project.yml --project .

echo "generated: MLXChat.xcodeproj"
echo
echo "スキーム:"
echo "  MLXChat-iOS     iOS アプリ（実機のみ。MLX はシミュレータでは動きません）"
echo "  MLXChat-macOS   macOS アプリ（Apple Silicon のみ）"
echo "  mlxchat-cli     コマンドライン版"
