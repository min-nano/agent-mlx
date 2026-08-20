//
//  GenerationParameters.swift
//
//  生成の振る舞いを決めるつまみ。MLXLMCommon の GenerateParameters と 1:1 で
//  対応するが、あちらの型は使わない（Core に MLX を持ち込まないため）。変換表は
//  MLXChatEngine の中に 1 つだけ置く。
//
//  値の範囲の検査もここに置く。CLI / URL スキーム / GUI のどこから来ても同じ
//  規則で弾かれる必要があるので、入口ごとに散らさない。
//

import Foundation

/// 生成 1 回のつまみ。
public struct GenerationParameters: Codable, Equatable, Sendable
{
	/// 温度。0 に近いほど決定的、大きいほど散らばる。
	public var temperature: Float
	/// top-p（核サンプリング）。
	public var topP: Float
	/// 生成するトークン数の上限。
	///
	/// ローカル実行では「止まらない生成」がそのまま発熱と電池消費になるので、
	/// 既定を控えめにしてある（続きは「続けて」と言えばよい）。
	public var maxTokens: Int
	/// 繰り返しペナルティ。nil なら無効。
	public var repetitionPenalty: Float?
	/// KV キャッシュの量子化ビット数（nil / 4 / 8）。
	///
	/// 長い会話ではキャッシュが重みより大きくなる。ここを 8 や 4 にすると
	/// メモリが目に見えて減る代わりに品質がわずかに落ちる。iPhone で長話を
	/// するときの主要な逃げ道なので、つまみとして表に出す。
	public var kvBits: Int?
	/// モデルへ渡す直近の発言数の上限（system は含まない）。
	public var historyMessageLimit: Int

	public init(
		temperature: Float = 0.7,
		topP: Float = 0.95,
		maxTokens: Int = 512,
		repetitionPenalty: Float? = nil,
		kvBits: Int? = nil,
		historyMessageLimit: Int = 20)
	{
		self.temperature = temperature
		self.topP = topP
		self.maxTokens = maxTokens
		self.repetitionPenalty = repetitionPenalty
		self.kvBits = kvBits
		self.historyMessageLimit = historyMessageLimit
	}

	/// 受け付ける範囲。GUI のスライダーの上下限もここから作る
	/// （画面と検査で範囲がずれると「動かせるのに弾かれる」つまみができる）。
	public static let temperatureRange: ClosedRange<Float> = 0 ... 2
	public static let topPRange: ClosedRange<Float> = 0 ... 1
	public static let maxTokensRange: ClosedRange<Int> = 1 ... 8192
	public static let repetitionPenaltyRange: ClosedRange<Float> = 1 ... 2
	public static let historyMessageLimitRange: ClosedRange<Int> = 0 ... 200
	/// KV キャッシュ量子化で受け付けるビット数。nil（量子化しない）は別扱い。
	public static let allowedKVBits = [4, 8]

	public func validate() throws
	{
		guard temperature.isFinite, GenerationParameters.temperatureRange.contains(temperature)
		else
		{
			throw ParameterError.outOfRange(name: "temperature", value: "\(temperature)")
		}
		guard topP.isFinite, GenerationParameters.topPRange.contains(topP)
		else
		{
			throw ParameterError.outOfRange(name: "topP", value: "\(topP)")
		}
		guard GenerationParameters.maxTokensRange.contains(maxTokens)
		else
		{
			throw ParameterError.outOfRange(name: "maxTokens", value: "\(maxTokens)")
		}
		if let penalty = repetitionPenalty
		{
			guard penalty.isFinite,
				GenerationParameters.repetitionPenaltyRange.contains(penalty)
			else
			{
				throw ParameterError.outOfRange(
					name: "repetitionPenalty", value: "\(penalty)")
			}
		}
		if let bits = kvBits
		{
			guard GenerationParameters.allowedKVBits.contains(bits)
			else
			{
				throw ParameterError.outOfRange(name: "kvBits", value: "\(bits)")
			}
		}
		guard GenerationParameters.historyMessageLimitRange.contains(historyMessageLimit)
		else
		{
			throw ParameterError.outOfRange(
				name: "historyMessageLimit", value: "\(historyMessageLimit)")
		}
	}
}

public enum ParameterError: Error, LocalizedError, Equatable
{
	case outOfRange(name: String, value: String)

	public var errorDescription: String?
	{
		switch self
		{
			case .outOfRange(let name, let value):
				return "\(name) の値が範囲外です: \(value)"
		}
	}
}
