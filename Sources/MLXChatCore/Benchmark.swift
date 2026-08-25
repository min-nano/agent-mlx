//
//  Benchmark.swift
//
//  同じプロンプトを何度か回して速度を測る。このアプリの目的が「MLX の実力を
//  確かめる」ことなので、ベンチマークはおまけではなく機能の 1 つとして
//  GUI・CLI の両方から実行できる。
//
//  集計（BenchmarkSummary）は純ロジックで、GenerationStats の配列しか受け取らない。
//  つまり MLX なしでテストでき、GUI と CLI で数字の出し方がずれない。
//

import Foundation

/// ベンチマーク 1 回分の指示。
public struct BenchmarkRequest: Equatable, Sendable
{
	public var modelID: String
	/// 毎回同じものを投げる。比較のためには入力が固定されている必要がある。
	public var prompt: String
	/// 実行回数。
	public var runs: Int
	/// 計測から除く先頭の回数（ウォームアップ）。
	///
	/// 1 回目は重みのメモリ配置や Metal のカーネル構築を含むため目に見えて遅い。
	/// 「2 回目以降の実力」と「初回の重さ」は別の数字なので、既定では 1 回だけ
	/// 捨て、捨てたぶんも warmup として結果に残す。
	public var warmupRuns: Int
	public var parameters: GenerationParameters

	public init(
		modelID: String = ModelCatalog.defaultModelID,
		prompt: String = BenchmarkRequest.defaultPrompt,
		runs: Int = 3,
		warmupRuns: Int = 1,
		parameters: GenerationParameters = GenerationParameters(temperature: 0, maxTokens: 256))
	{
		self.modelID = modelID
		self.prompt = prompt
		self.runs = runs
		self.warmupRuns = warmupRuns
		self.parameters = parameters
	}

	/// 既定のプロンプト。長さがトークン数に効くので、比較用に固定文を持つ。
	public static let defaultPrompt =
		"Apple Silicon のユニファイドメモリが機械学習にとって有利な理由を、"
		+ "3 つの観点から日本語で説明してください。"

	/// 計測に使われる回数（ウォームアップを除いた回数）。
	public var measuredRuns: Int
	{
		max(0, runs - max(0, warmupRuns))
	}

	public func validate() throws
	{
		guard ModelCatalog.contains(id: modelID)
		else
		{
			throw RequestError.unknownModel(modelID)
		}
		guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			throw RequestError.emptyPrompt
		}
		// ウォームアップだけで終わる指示は「測らないベンチマーク」なので弾く。
		guard runs >= 1, measuredRuns >= 1
		else
		{
			throw RequestError.invalidRunCount(runs)
		}
		try parameters.validate()
	}
}

/// ベンチマークの集計結果。
public struct BenchmarkSummary: Codable, Equatable, Sendable
{
	public let modelID: String
	/// 計測に使った回のみ（ウォームアップは含まない）。
	public let runs: [GenerationStats]
	/// 捨てたウォームアップの回。初回の重さを見るために残す。
	public let warmup: [GenerationStats]

	public init(modelID: String, runs: [GenerationStats], warmup: [GenerationStats] = [])
	{
		self.modelID = modelID
		self.runs = runs
		self.warmup = warmup
	}

	/// 計測回の生成速度（トークン/秒）。
	public var tokensPerSecondSamples: [Double]
	{
		runs.map(\.tokensPerSecond)
	}

	/// 中央値。外れ値（サーマルスロットリングや他アプリの割り込み）に強いので、
	/// 代表値にはこちらを使う。
	public var medianTokensPerSecond: Double
	{
		BenchmarkSummary.median(tokensPerSecondSamples)
	}

	public var meanTokensPerSecond: Double
	{
		BenchmarkSummary.mean(tokensPerSecondSamples)
	}

	public var minTokensPerSecond: Double
	{
		tokensPerSecondSamples.min() ?? 0
	}

	public var maxTokensPerSecond: Double
	{
		tokensPerSecondSamples.max() ?? 0
	}

	/// プロンプト処理速度の中央値。
	public var medianPromptTokensPerSecond: Double
	{
		BenchmarkSummary.median(runs.map(\.promptTokensPerSecond))
	}

	/// TTFT の中央値（計測できた回だけで集計。1 回も無ければ nil）。
	public var medianTimeToFirstToken: Double?
	{
		let samples = runs.compactMap(\.timeToFirstTokenSeconds)
		guard !samples.isEmpty
		else
		{
			return nil
		}
		return BenchmarkSummary.median(samples)
	}

	/// 全回を通したメモリのピーク（計測できた回だけ）。
	public var peakMemoryBytes: Int64?
	{
		(runs + warmup).compactMap(\.peakMemoryBytes).max()
	}

	/// ウォームアップと計測回の速度差（倍率）。初回がどれだけ重いかの目安。
	/// どちらかが 0 なら nil。
	public var warmupPenalty: Double?
	{
		let warm = BenchmarkSummary.median(warmup.map(\.tokensPerSecond))
		let measured = medianTokensPerSecond
		guard warm > 0, measured > 0
		else
		{
			return nil
		}
		return measured / warm
	}

	/// CLI と GUI が共有する複数行のレポート。
	public func report() -> String
	{
		guard !runs.isEmpty
		else
		{
			return "計測できた回がありません。"
		}
		var lines = [
			"model:      \(modelID)",
			"runs:       \(runs.count)（ウォームアップ \(warmup.count) 回を除く）",
			String(
				format: "generate:   median %.1f tok/s  (mean %.1f, min %.1f, max %.1f)",
				medianTokensPerSecond, meanTokensPerSecond,
				minTokensPerSecond, maxTokensPerSecond),
			String(format: "prompt:     median %.1f tok/s", medianPromptTokensPerSecond),
		]
		if let ttft = medianTimeToFirstToken
		{
			lines.append(String(format: "ttft:       median %.2f s", ttft))
		}
		if let peak = peakMemoryBytes
		{
			lines.append("peak GPU:   \(ByteCount.humanReadable(peak))")
		}
		if let penalty = warmupPenalty
		{
			lines.append(String(format: "warmup:     計測回は初回の %.2f 倍の速度", penalty))
		}
		return lines.joined(separator: "\n")
	}

	// -----------------------------------------------------------------
	// 小さな統計（外部依存を増やさない方針なので自前で持つ）
	// -----------------------------------------------------------------

	static func mean(_ values: [Double]) -> Double
	{
		guard !values.isEmpty
		else
		{
			return 0
		}
		return values.reduce(0, +) / Double(values.count)
	}

	/// 中央値。偶数個なら中央 2 つの平均。空なら 0。
	static func median(_ values: [Double]) -> Double
	{
		guard !values.isEmpty
		else
		{
			return 0
		}
		let sorted = values.sorted()
		let middle = sorted.count / 2
		if sorted.count % 2 == 1
		{
			return sorted[middle]
		}
		return (sorted[middle - 1] + sorted[middle]) / 2
	}
}

/// ベンチマーク中に起きること。GUI と CLI が同じ列を受け取る。
public enum BenchmarkEvent: Sendable, Equatable
{
	/// 1 回ぶんが始まった（index は 0 起点。ウォームアップも数える）。
	case runStarted(index: Int, total: Int, isWarmup: Bool)
	/// 実行中の生成イベント（進捗表示のためそのまま流す）。
	case generation(GenerationEvent)
	/// 1 回ぶんが終わった。
	case runFinished(GenerationStats, isWarmup: Bool)
	/// 全部終わった。
	case completed(BenchmarkSummary)
	/// 失敗した。
	case failed(String)
}
