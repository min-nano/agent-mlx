//
//  ChatMessage.swift
//
//  会話 1 発言。保存（ConversationStore）・画面（MLXChatUI）・モデルへの入力
//  （MLXChatEngine）のすべてがこの型を通る。
//
//  役割（Role）は MLXLMCommon の Chat.Message.Role と 1:1 で対応するが、あちらの型は
//  使わない。理由は ReconstructionRequest が RealityKit の enum を使わないのと同じで、
//  (1) 保存形式（rawValue）を MLX のバージョンから独立させるため、(2) MLX 抜きで
//  単体テストできるようにするため。変換表は MLXChatEngine の中に 1 つだけ置く。
//

import Foundation

/// 会話の 1 発言。
public struct ChatMessage: Identifiable, Codable, Equatable, Sendable
{
	/// 発言者。
	public enum Role: String, Codable, CaseIterable, Sendable
	{
		/// システム指示（モデルへの前提）。会話の先頭に 1 つだけ置く。
		case system
		/// 利用者。
		case user
		/// モデル。
		case assistant
	}

	public let id: UUID
	public var role: Role
	/// 本文。生成中の assistant 発言は、届いたトークンを継ぎ足して伸びていく。
	///
	/// 推論モデルの `<think> … </think>` は**ここには入らない**（`reasoning` へ回す）。
	/// そう分けてあるおかげで、次の生成へ渡す履歴・書き出し・コピーのどれもが
	/// 自動的に「答えだけ」になる — 入口ごとに思考を除く処理を書かなくてよい。
	public var text: String
	/// 思考（`<think>` の中身）。推論モデルでなければ nil。
	///
	/// 画面では折りたたんで見せる。モデルへは**渡さない** — 前の思考を履歴に
	/// 混ぜるとコンテキストを浪費し、品質も落ちる（モデル提供元の推奨でもある）。
	public var reasoning: String?
	public var createdAt: Date
	/// この発言を生成したときの実測値（assistant のみ。生成中は nil）。
	public var stats: GenerationStats?
	/// 生成に使ったモデル（assistant のみ）。会話の途中でモデルを替えられるので、
	/// 発言ごとに覚えておかないと後からログを読めなくなる。
	public var modelID: String?

	public init(
		id: UUID = UUID(),
		role: Role,
		text: String,
		createdAt: Date = Date(),
		stats: GenerationStats? = nil,
		modelID: String? = nil,
		// 思考は後から足した項目なので、既存の呼び出しを壊さないよう末尾に置く。
		reasoning: String? = nil)
	{
		self.id = id
		self.role = role
		self.text = text
		self.reasoning = reasoning
		self.createdAt = createdAt
		self.stats = stats
		self.modelID = modelID
	}

	/// 折りたたんで見せる価値のある思考を持っているか。
	public var hasReasoning: Bool
	{
		guard let reasoning
		else
		{
			return false
		}
		return !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	/// 吹き出しに出す本文。
	///
	/// 「思考だけで終わった」ときに空の吹き出しを出さないための判断がここにある。
	/// 推論モデルは考えが長く、上限（maxTokens）に達して**答えに辿り着かない**
	/// ことが実際にある。生成が終わって（stats がある）本文が空なのに思考だけが
	/// あるなら、それは失敗ではなく「途中で力尽きた」なので、そう伝える。
	public var displayText: String
	{
		if !text.isEmpty
		{
			return text
		}
		if stats != nil, hasReasoning
		{
			return "（考えている途中で上限に達しました。設定で最大トークン数を増やすか、"
				+ "小さいモデルに替えてみてください。）"
		}
		return text
	}

	/// 表示・書き出しに使う短い肩書き。
	public var roleLabel: String
	{
		switch role
		{
			case .system:
				return "システム"
			case .user:
				return "あなた"
			case .assistant:
				return "モデル"
		}
	}
}
