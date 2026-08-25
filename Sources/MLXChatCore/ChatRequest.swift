//
//  ChatRequest.swift
//
//  生成 1 回分の指示。GUI・CLI・URL スキーム・ライブラリのどの入口から来ても
//  最終的にこの構造体 1 つへ正規化され、MLXChatEngine へ渡される。
//
//  「入口ごとに規則を散らさない」ための要になる型なので、検査（validate）も
//  ここに置く。ライブラリとして直接組み立てる呼び出しも同じ規則で守られる。
//

import Foundation

/// 生成 1 回分の指示。
public struct ChatRequest: Equatable, Sendable
{
	/// 使うモデル（ModelCatalog の id）。
	public var modelID: String
	/// 今回の入力。
	///
	/// CLI では `--prompt` を省いて標準入力から流し込めるので、パースの時点では
	/// 空のことがある。空のまま実行することはできない（validate が弾く）。
	public var prompt: String
	/// システム指示（空なら指定なし）。
	public var systemPrompt: String
	/// これまでのやり取り。モデルへは systemPrompt → history → prompt の順で渡る。
	public var history: [ChatMessage]
	/// 生成のつまみ。
	public var parameters: GenerationParameters
	/// 応答の書き出し先（任意）。CLI で結果をファイルに残したいとき用。
	public var outputFile: URL?

	public init(
		modelID: String = ModelCatalog.defaultModelID,
		prompt: String = "",
		systemPrompt: String = "",
		history: [ChatMessage] = [],
		parameters: GenerationParameters = GenerationParameters(),
		outputFile: URL? = nil)
	{
		self.modelID = modelID
		self.prompt = prompt
		self.systemPrompt = systemPrompt
		self.history = history
		self.parameters = parameters
		self.outputFile = outputFile
	}

	/// 会話から次の 1 回ぶんの指示を組み立てる。履歴の切り詰め規則
	/// （Conversation.promptMessages）を GUI と CLI で共有するための入口。
	public static func next(
		in conversation: Conversation,
		prompt: String,
		parameters: GenerationParameters) -> ChatRequest
	{
		ChatRequest(
			modelID: conversation.modelID,
			prompt: prompt,
			systemPrompt: conversation.systemPrompt,
			history: conversation.promptMessages(
				maxMessages: parameters.historyMessageLimit)
				.filter { $0.role != .system },
			parameters: parameters,
			outputFile: nil)
	}

	/// モデルへ実際に渡す履歴。
	///
	/// `history` をそのまま使わないのは、チャットテンプレートが「user と
	/// assistant が交互」を要求することがあるため（詳しくは
	/// ``Conversation/alternatingHistory(_:)``）。ここを通しておけば、入口が
	/// GUI でも CLI でも URL スキームでも、ライブラリから直接組み立てた
	/// 場合でも同じ規則で守られる。**エンジンはこちらを使うこと。**
	public var promptHistory: [ChatMessage]
	{
		Conversation.alternatingHistory(history)
	}

	/// 実行前に分かる誤りを検出する。
	///
	/// モデル id を一覧に限っているのは ModelCatalog のコメントにある理由による
	/// （数 GB 落としてから「非対応でした」を避ける）。一覧外を試したいときは
	/// ライブラリではなく ModelCatalog へ足す — そうすればサイズと必要メモリも
	/// 一緒に定義され、端末で動くかの判断が働く。
	public func validate() throws
	{
		guard !modelID.isEmpty
		else
		{
			throw RequestError.modelNotSpecified
		}
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
		try parameters.validate()
	}
}

/// 生成の指示に対する検査エラー。
public enum RequestError: Error, LocalizedError, Equatable
{
	case modelNotSpecified
	case unknownModel(String)
	case emptyPrompt
	case invalidRunCount(Int)

	public var errorDescription: String?
	{
		switch self
		{
			case .modelNotSpecified:
				return "モデルが指定されていません。"
			case .unknownModel(let id):
				return "一覧にないモデルです: \(id)（`mlxchat-cli models` で一覧を確認できます）"
			case .emptyPrompt:
				return "入力が空です。"
			case .invalidRunCount(let count):
				return "繰り返し回数が不正です: \(count)（1 以上を指定してください）"
		}
	}
}
