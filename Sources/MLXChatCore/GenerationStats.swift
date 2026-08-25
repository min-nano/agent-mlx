//
//  GenerationStats.swift
//
//  1 回の生成の実測値。「MLX の実力を確かめる」のがこのアプリの目的なので、
//  速度と規模の数字は会話と同じ重みで扱う（画面にも出すし、会話ごと保存する）。
//
//  MLX に依存しない純粋な値型にしてあるのは、
//    * 秒あたりトークン数のような割り算を 1 か所に閉じ込めて単体テストするため
//    * ベンチマーク（BenchmarkSummary）が同じ型を集計に使えるようにするため
//    * 保存した会話を MLX 抜きで（テストからも）読み書きできるようにするため。
//  MLXLMCommon の GenerateCompletionInfo からの写し替えは MLXChatEngine の中だけで
//  行う（フレームワークの型をここへ漏らさない）。
//

import Foundation

/// 1 回の生成の実測値。
public struct GenerationStats: Codable, Equatable, Sendable
{
	/// プロンプト（会話履歴を含む）のトークン数。
	public var promptTokens: Int
	/// 生成されたトークン数。
	public var generatedTokens: Int
	/// プロンプトの処理（プリフィル）にかかった秒数。
	public var promptSeconds: Double
	/// トークン生成（デコード）にかかった秒数。
	public var generateSeconds: Double
	/// 最初のトークンが出るまでの秒数（TTFT）。体感速度はほぼこれで決まる。
	/// エンジンが計測できなかったときは nil。
	public var timeToFirstTokenSeconds: Double?
	/// 生成中の GPU メモリのピーク（バイト）。MLX の GPU.peakMemory を写したもの。
	/// iPhone では「動くかどうか」がここで決まるので記録する。
	public var peakMemoryBytes: Int64?
	/// 生成が止まった理由。
	public var stopReason: StopReason

	/// 生成が止まった理由。MLXLMCommon の GenerateStopReason に対応する自前の enum
	/// （フレームワークの型を Core へ持ち込まないため）。
	public enum StopReason: String, Codable, CaseIterable, Sendable
	{
		/// モデルが終了トークンを出した（正常終了）。
		case stop
		/// 上限トークン数に達した（続きがある）。
		case length
		/// 利用者が停止した。
		case cancelled
	}

	public init(
		promptTokens: Int = 0,
		generatedTokens: Int = 0,
		promptSeconds: Double = 0,
		generateSeconds: Double = 0,
		timeToFirstTokenSeconds: Double? = nil,
		peakMemoryBytes: Int64? = nil,
		stopReason: StopReason = .stop)
	{
		self.promptTokens = promptTokens
		self.generatedTokens = generatedTokens
		self.promptSeconds = promptSeconds
		self.generateSeconds = generateSeconds
		self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
		self.peakMemoryBytes = peakMemoryBytes
		self.stopReason = stopReason
	}

	/// 生成速度（トークン/秒）。これがベンチマークの主指標。
	///
	/// 0 秒で割らない。生成が一瞬で終わった（＝計測不能）ときに Infinity を
	/// 画面に出さないための防御で、集計（BenchmarkSummary）も同じ値を使う。
	public var tokensPerSecond: Double
	{
		guard generateSeconds > 0, generatedTokens > 0
		else
		{
			return 0
		}
		return Double(generatedTokens) / generateSeconds
	}

	/// プロンプト処理速度（トークン/秒）。長い会話履歴を食わせたときの
	/// 「待たされ具合」はこちらで決まる。
	public var promptTokensPerSecond: Double
	{
		guard promptSeconds > 0, promptTokens > 0
		else
		{
			return 0
		}
		return Double(promptTokens) / promptSeconds
	}

	/// 生成全体にかかった秒数（プロンプト処理 + 生成）。
	public var totalSeconds: Double
	{
		promptSeconds + generateSeconds
	}

	/// 画面と CLI の両方で使う 1 行サマリ。書式を 1 か所に持たせて、
	/// GUI と CLI で数字の読み方がずれないようにする。
	public var summaryLine: String
	{
		var parts = [
			String(format: "%.1f tok/s", tokensPerSecond),
			"\(generatedTokens) tok",
		]
		if promptTokens > 0
		{
			parts.append(String(format: "prompt %d tok / %.1f tok/s", promptTokens, promptTokensPerSecond))
		}
		if let ttft = timeToFirstTokenSeconds
		{
			parts.append(String(format: "TTFT %.2fs", ttft))
		}
		if let peak = peakMemoryBytes
		{
			parts.append("peak \(ByteCount.humanReadable(peak))")
		}
		if stopReason != .stop
		{
			parts.append(stopReason.rawValue)
		}
		return parts.joined(separator: " · ")
	}
}

/// バイト数の表示。モデルのサイズ・空き容量・GPU メモリと出番が多いので、
/// 書式を 1 か所に置く（ByteCountFormatter は Linux で挙動が違ううえ、
/// テストしたい丸め方が固定できない）。
public enum ByteCount
{
	/// 1024 進で "1.2 GB" のように整える。負値は 0 として扱う。
	public static func humanReadable(_ bytes: Int64) -> String
	{
		let value = max(0, bytes)
		let units = ["B", "KB", "MB", "GB", "TB"]
		var scaled = Double(value)
		var unit = 0
		while scaled >= 1024, unit < units.count - 1
		{
			scaled /= 1024
			unit += 1
		}
		// B と KB は小数を出さない（"1.0 B" は読みにくいだけ）。
		if unit <= 1
		{
			return "\(Int(scaled.rounded())) \(units[unit])"
		}
		return String(format: "%.1f %@", scaled, units[unit])
	}
}
