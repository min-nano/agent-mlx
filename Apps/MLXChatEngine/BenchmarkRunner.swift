//
//  BenchmarkRunner.swift
//
//  同じプロンプトを繰り返して速度を測る段取り。GUI（BenchmarkViewModel）と
//  CLI（bench サブコマンド）が同じ実装を使うために、ここに 1 つだけ置く。
//
//  ここも「段取り」だけで判断は持たない — 何回捨てるか（warmupRuns）は
//  BenchmarkRequest が、集計の仕方は BenchmarkSummary が持つ（どちらも Core の
//  純ロジックで、テストがある）。
//

import Foundation

struct BenchmarkRunner
{
	let engine: MLXChatEngine

	init(engine: MLXChatEngine)
	{
		self.engine = engine
	}

	/// ベンチマークを実行し、出来事を順に流す。
	///
	/// 途中で失敗したら .failed を流して終える（部分的な結果で平均を出すと、
	/// 「速い回だけが残った数字」になり比較の役に立たないため）。
	func events(for request: BenchmarkRequest) -> AsyncStream<BenchmarkEvent>
	{
		let (stream, continuation) = AsyncStream<BenchmarkEvent>.makeStream()
		let engine = self.engine
		let task = Task
		{
			do
			{
				try request.validate()
			}
			catch
			{
				continuation.yield(.failed(
					ErrorDetails.message(for: error, modelID: request.modelID)))
				continuation.finish()
				return
			}

			var warmup: [GenerationStats] = []
			var measured: [GenerationStats] = []

			for index in 0 ..< request.runs
			{
				let isWarmup = index < request.warmupRuns
				continuation.yield(
					.runStarted(index: index, total: request.runs, isWarmup: isWarmup))

				// 会話履歴は毎回空にする。履歴が伸びるとプロンプト長が変わり、
				// 回ごとの数字が比較できなくなる。
				let chat = ChatRequest(
					modelID: request.modelID,
					prompt: request.prompt,
					parameters: request.parameters)

				var stats: GenerationStats?
				var failure: String?
				for await event in engine.events(for: chat)
				{
					continuation.yield(.generation(event))
					switch event
					{
						case .finished(let value):
							stats = value
						case .failed(let message):
							failure = message
						default:
							break
					}
				}

				if let failure
				{
					continuation.yield(.failed(failure))
					continuation.finish()
					return
				}
				guard let stats
				else
				{
					continuation.yield(.failed("生成が結果を返しませんでした。"))
					continuation.finish()
					return
				}
				if Task.isCancelled
				{
					continuation.finish()
					return
				}

				continuation.yield(.runFinished(stats, isWarmup: isWarmup))
				if isWarmup
				{
					warmup.append(stats)
				}
				else
				{
					measured.append(stats)
				}
			}

			continuation.yield(.completed(BenchmarkSummary(
				modelID: request.modelID, runs: measured, warmup: warmup)))
			continuation.finish()
		}
		continuation.onTermination =
		{ _ in
			task.cancel()
		}
		return stream
	}
}
