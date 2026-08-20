//
//  ParametersView.swift
//
//  生成のつまみ。スライダーの範囲は GenerationParameters（Core）が持つ定数から
//  作る — 画面と検査で範囲がずれると「動かせるのに弾かれるつまみ」ができるため。
//

import SwiftUI

struct ParametersView: View
{
	@EnvironmentObject private var model: ChatViewModel

	var body: some View
	{
		Form
		{
			Section("システム指示")
			{
				TextField(
					"例: 簡潔な日本語で答えてください。",
					text: $model.conversation.systemPrompt, axis: .vertical)
					.lineLimit(2 ... 6)
			}

			Section
			{
				slider(
					title: "温度",
					value: $model.parameters.temperature,
					range: GenerationParameters.temperatureRange,
					step: 0.05,
					detail: "0 に近いほど決まりきった答え、大きいほど散らばります。")
				slider(
					title: "top-p",
					value: $model.parameters.topP,
					range: GenerationParameters.topPRange,
					step: 0.01,
					detail: "候補の広さ。")
				Stepper(
					value: $model.parameters.maxTokens,
					in: GenerationParameters.maxTokensRange,
					step: 64)
				{
					LabeledContent("最大トークン数", value: "\(model.parameters.maxTokens)")
				}
				Text("ローカル実行では長い生成がそのまま発熱と電池消費になります。"
					+ "足りなければ「続けて」と言うほうが安上がりです。")
					.font(.caption2)
					.foregroundStyle(.secondary)
			} header: {
				Text("生成")
			}

			Section
			{
				Picker("KV キャッシュ量子化", selection: kvBitsBinding)
				{
					Text("しない").tag(0)
					ForEach(GenerationParameters.allowedKVBits, id: \.self)
					{ bits in
						Text("\(bits)bit").tag(bits)
					}
				}
				Stepper(
					value: $model.parameters.historyMessageLimit,
					in: GenerationParameters.historyMessageLimitRange,
					step: 2)
				{
					LabeledContent("履歴の上限", value: "\(model.parameters.historyMessageLimit) 発言")
				}
			} header: {
				Text("メモリ")
			} footer: {
				Text("長い会話では KV キャッシュが重みより大きくなります。"
					+ "iPhone で会話が続かなくなったら、まずここを 8bit にしてください。")
			}

			Section
			{
				Text(model.equivalentCommand)
					.font(.system(.caption2, design: .monospaced))
					.textSelection(.enabled)
			} header: {
				Text("CLI で再現するには")
			} footer: {
				Text("同じ設定を macOS の mlxchat-cli で実行するコマンドです"
					+ "（設定を人に伝えるとき・不具合を報告するときに）。")
			}
		}
		.navigationTitle("設定")
	}

	/// Picker は Optional を扱いにくいので 0 =「量子化しない」に写す。
	/// 変換をここに閉じ込め、Core 側は Optional のまま保つ（0bit という
	/// 意味のない値を Core の語彙に持ち込まないため）。
	private var kvBitsBinding: Binding<Int>
	{
		Binding(
			get: { model.parameters.kvBits ?? 0 },
			set: { model.parameters.kvBits = $0 == 0 ? nil : $0 })
	}

	private func slider(
		title: String, value: Binding<Float>, range: ClosedRange<Float>,
		step: Float, detail: String) -> some View
	{
		VStack(alignment: .leading, spacing: 2)
		{
			LabeledContent(title, value: String(format: "%.2f", value.wrappedValue))
			Slider(value: value, in: range, step: step)
			Text(detail)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}
}
