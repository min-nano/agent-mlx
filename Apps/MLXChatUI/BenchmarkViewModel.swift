//
//  BenchmarkViewModel.swift
//
//  ベンチマーク画面の状態。段取りは BenchmarkRunner が、集計は
//  BenchmarkSummary（Core）が持つので、ここは受け取った値を並べるだけ。
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class BenchmarkViewModel: ObservableObject
{
	@Published var request = BenchmarkRequest()
	/// 実行中の進捗表示（"2 / 4 回目（計測）"）。
	@Published private(set) var progressLabel: String?
	@Published private(set) var phase: GenerationPhase?
	@Published private(set) var downloadProgress: Double = 0
	/// 終わった回の実測値（ウォームアップを含む。届いた順）。
	@Published private(set) var finishedRuns: [GenerationStats] = []
	@Published private(set) var summary: BenchmarkSummary?
	@Published var errorMessage: String?

	var isRunning: Bool { progressLabel != nil }

	/// いまの設定を CLI で再現するコマンド。
	var equivalentCommand: String
	{
		(["mlxchat-cli"] + APICommand.arguments(for: request))
			.map { $0.contains(" ") ? "\"\($0)\"" : $0 }
			.joined(separator: " ")
	}

	/// エンジンはチャット画面と共有する（MLXChatEngine.shared）。ベンチマークの
	/// たびに読み込み直すと、数 GB の読み込みが二重に走るうえメモリも二重に要る。
	private let engine = MLXChatEngine.shared
	private var task: Task<Void, Never>?
	/// チャット画面で選ばれているモデルを一度だけ引き継いだか。
	private var didAdoptChatModel = false

	/// 初回表示のときだけ、チャット画面のモデルを既定として引き継ぐ。
	/// 毎回上書きすると、この画面で選び直したモデルが戻ってしまう。
	func adoptIfNeeded(modelID: String)
	{
		guard !didAdoptChatModel
		else
		{
			return
		}
		didAdoptChatModel = true
		request.modelID = modelID
	}

	func run()
	{
		guard !isRunning
		else
		{
			return
		}
		errorMessage = nil
		summary = nil
		finishedRuns = []
		progressLabel = "準備中…"

		let runner = BenchmarkRunner(engine: engine)
		let request = self.request
		task = Task
		{ [weak self] in
			for await event in runner.events(for: request)
			{
				await self?.apply(event)
			}
			await self?.finish()
		}
	}

	func stop()
	{
		task?.cancel()
		task = nil
		progressLabel = nil
		phase = nil
	}

	private func apply(_ event: BenchmarkEvent)
	{
		switch event
		{
			case .runStarted(let index, let total, let isWarmup):
				progressLabel = "\(index + 1) / \(total) 回目"
					+ (isWarmup ? "（ウォームアップ）" : "（計測）")
			case .generation(let generation):
				switch generation
				{
					case .phase(let phase):
						self.phase = phase == .finished ? nil : phase
					case .downloadProgress(let fraction):
						downloadProgress = fraction
					default:
						break
				}
			case .runFinished(let stats, _):
				finishedRuns.append(stats)
			case .completed(let summary):
				self.summary = summary
				progressLabel = nil
				phase = nil
			case .failed(let message):
				errorMessage = message
				progressLabel = nil
				phase = nil
		}
	}

	private func finish()
	{
		task = nil
		progressLabel = nil
		phase = nil
	}
}
