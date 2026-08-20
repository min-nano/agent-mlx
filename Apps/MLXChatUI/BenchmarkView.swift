//
//  BenchmarkView.swift
//
//  同じプロンプトを繰り返して速度を測る画面。「MLX の実力を確かめる」という
//  このアプリの目的そのものなので、おまけではなく主要な画面の 1 つ。
//

import SwiftUI

struct BenchmarkView: View
{
	@EnvironmentObject private var chat: ChatViewModel
	@StateObject private var model = BenchmarkViewModel()

	var body: some View
	{
		Form
		{
			Section("条件")
			{
				Picker("モデル", selection: $model.request.modelID)
				{
					ForEach(ModelCatalog.all)
					{ entry in
						Text(entry.displayName).tag(entry.id)
					}
				}
				Stepper(value: $model.request.runs, in: 1 ... 20)
				{
					LabeledContent("実行回数", value: "\(model.request.runs)")
				}
				Stepper(value: $model.request.warmupRuns, in: 0 ... 5)
				{
					LabeledContent("ウォームアップ", value: "\(model.request.warmupRuns) 回")
				}
				Stepper(
					value: $model.request.parameters.maxTokens,
					in: GenerationParameters.maxTokensRange, step: 64)
				{
					LabeledContent("生成トークン数", value: "\(model.request.parameters.maxTokens)")
				}
				TextField("プロンプト", text: $model.request.prompt, axis: .vertical)
					.lineLimit(2 ... 5)
			}

			Section
			{
				if model.isRunning
				{
					HStack
					{
						ProgressView()
							.controlSize(.small)
						Text(model.progressLabel ?? "")
						Spacer()
						Button("停止", role: .destructive) { model.stop() }
							.buttonStyle(.borderless)
					}
					if let phase = model.phase
					{
						Text(phase.description)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				else
				{
					Button("計測する") { model.run() }
				}
			}

			if !model.finishedRuns.isEmpty
			{
				Section("各回")
				{
					ForEach(Array(model.finishedRuns.enumerated()), id: \.offset)
					{ index, stats in
						LabeledContent(
							"\(index + 1) 回目",
							value: String(format: "%.1f tok/s", stats.tokensPerSecond))
					}
				}
			}

			if let summary = model.summary
			{
				Section
				{
					Text(summary.report())
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)
				} header: {
					Text("結果")
				}
			}

			Section
			{
				Text(model.equivalentCommand)
					.font(.system(.caption2, design: .monospaced))
					.textSelection(.enabled)
			} header: {
				Text("CLI で再現するには")
			}
		}
		.navigationTitle("ベンチマーク")
		.onAppear { model.adoptIfNeeded(modelID: chat.conversation.modelID) }
		.alert(
			"エラー",
			isPresented: Binding(
				get: { model.errorMessage != nil },
				set: { if !$0 { model.errorMessage = nil } }))
		{
			Button("OK", role: .cancel) { model.errorMessage = nil }
		} message: {
			Text(model.errorMessage ?? "")
		}
	}
}
