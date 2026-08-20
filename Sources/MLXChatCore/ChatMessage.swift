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
	public var text: String
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
		modelID: String? = nil)
	{
		self.id = id
		self.role = role
		self.text = text
		self.createdAt = createdAt
		self.stats = stats
		self.modelID = modelID
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
