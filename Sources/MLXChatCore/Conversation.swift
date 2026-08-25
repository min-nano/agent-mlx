//
//  Conversation.swift
//
//  会話 1 本。発言の列と、そこから決まる情報（タイトル・トークン概算・
//  直近の実測値）を持つ純粋な値型。
//
//  「履歴をどこまでモデルへ渡すか」の判断もここに置く。ローカル LLM では
//  コンテキスト長がそのまま速度とメモリに効くので、履歴の切り詰めは体感に
//  直結する重要な判断で、GUI にも CLI にも同じ規則で効かなければならない。
//

import Foundation

/// 会話 1 本。
public struct Conversation: Identifiable, Codable, Equatable, Sendable
{
	public let id: UUID
	/// 表示名。空なら最初の user 発言から自動で決まる（derivedTitle）。
	public var title: String
	/// システム指示。空文字なら指定なし扱い。
	public var systemPrompt: String
	/// system を除く発言の列（時系列）。
	public var messages: [ChatMessage]
	/// 最後に使ったモデル。再開時の既定値になる。
	public var modelID: String
	public var createdAt: Date
	public var updatedAt: Date

	public init(
		id: UUID = UUID(),
		title: String = "",
		systemPrompt: String = "",
		messages: [ChatMessage] = [],
		modelID: String = ModelCatalog.defaultModelID,
		createdAt: Date = Date(),
		updatedAt: Date = Date())
	{
		self.id = id
		self.title = title
		self.systemPrompt = systemPrompt
		self.messages = messages
		self.modelID = modelID
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}

	/// 一覧に出す名前。title が空なら最初の user 発言の冒頭を使う。
	///
	/// 「タイトルを付ける」ためだけにモデルをもう 1 回走らせるのは、ローカル
	/// 実行では高すぎる（数秒〜数十秒と、その間の発熱・電池）。だから機械的に決める。
	public var derivedTitle: String
	{
		if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			return title
		}
		guard let first = messages.first(where: { $0.role == .user })
		else
		{
			return "新しい会話"
		}
		return Conversation.snippet(of: first.text, limit: 40)
	}

	/// 直近の assistant 発言の実測値（あれば）。画面の速度表示に使う。
	public var lastStats: GenerationStats?
	{
		messages.last(where: { $0.role == .assistant })?.stats
	}

	/// この会話でこれまでに生成したトークンの合計。
	public var totalGeneratedTokens: Int
	{
		messages.compactMap { $0.stats?.generatedTokens }.reduce(0, +)
	}

	/// この会話の平均生成速度（トークン/秒）。生成時間で重み付けする
	/// （速度の単純平均は、短い生成 1 回に引きずられて実態を外す）。
	public var averageTokensPerSecond: Double
	{
		let stats = messages.compactMap { $0.stats }
		let tokens = stats.reduce(0) { $0 + $1.generatedTokens }
		let seconds = stats.reduce(0.0) { $0 + $1.generateSeconds }
		guard seconds > 0, tokens > 0
		else
		{
			return 0
		}
		return Double(tokens) / seconds
	}

	/// モデルへ渡す履歴を組み立てる。
	///
	/// - Parameter maxMessages: 渡す発言数の上限（system は数えない）。
	///   0 以下なら履歴なし（1 往復ごとに忘れる）。
	/// - Returns: system 指示（あれば）を先頭に置いた発言列。
	///
	/// 古いほうから落とすが、**必ず user 発言から始まる**ように 1 つ余分に落とす
	/// ことがある。assistant 発言で始まる履歴はチャットテンプレートの前提を崩し、
	/// モデルによっては露骨に品質が落ちるため。
	///
	/// 推論モデルの思考は ``ChatMessage/reasoning`` に分けてあり ``ChatMessage/text``
	/// には入らないので、ここでは何もしなくても履歴から外れる（前の思考を食べさせ
	/// ないための処置。詳しくは ``ReasoningSplitter``）。
	public func promptMessages(maxMessages: Int) -> [ChatMessage]
	{
		var history: [ChatMessage] = []
		if maxMessages > 0
		{
			history = Conversation.alternatingHistory(Array(messages.suffix(maxMessages)))
		}
		let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedSystem.isEmpty
		else
		{
			return history
		}
		return [ChatMessage(role: .system, text: trimmedSystem)] + history
	}

	/// 履歴を「user と assistant が交互・user で始まり assistant で終わる」形に整える。
	///
	/// なぜ要るか: チャットテンプレートには**役割が交互であることを要求する**もの
	/// がある（Gemma 3 は崩れていると `Conversation roles must alternate
	/// user/assistant/user/assistant/...` を投げて生成そのものが失敗する）。
	/// 会話は簡単に崩れる — 生成が失敗すると答えの無い user 発言が残り、次に
	/// 送ると user が 2 つ続く。実機で踏んだのはこの形でした。
	///
	/// 整え方は 4 つ。
	///
	/// 1. **中身の無い発言を捨てる。** 停止・失敗の残骸（本文が空の assistant）は
	///    モデルに何も教えないうえ、テンプレートによっては壊れる。
	/// 2. **同じ役割が続いたら最後の 1 つだけ残す。** 答えの無いまま繰り返された
	///    問いのうち、意味があるのは最後のものだけ。
	/// 3. **assistant で始まらない。** 途中から切り出したときに起きる。
	/// 4. **user で終わらない。** 履歴の後ろには必ず今回の prompt（user）が続くので、
	///    user で終わっているとそこで 2 つ続いてしまう。落とすのは「答えを
	///    もらえなかった問い」で、たいていは今まさに送り直そうとしているもの。
	///
	/// system 発言はここでは扱わない（``promptMessages`` が先頭に置く）。
	public static func alternatingHistory(_ messages: [ChatMessage]) -> [ChatMessage]
	{
		var result: [ChatMessage] = []
		for message in messages
		{
			guard message.role != .system,
				!message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			else
			{
				continue
			}
			if result.last?.role == message.role
			{
				// 同じ役割が続いた。新しいほうで置き換える。
				result.removeLast()
			}
			result.append(message)
		}
		if result.first?.role == .assistant
		{
			result.removeFirst()
		}
		if result.last?.role == .user
		{
			result.removeLast()
		}
		return result
	}

	/// 失敗した 1 往復を取り除き、送れなかった問いの本文を返す。
	///
	/// 生成が 1 文字も出せずに終わると、答えの無い user 発言が残る。そのままだと
	/// (1) 送り直したときに画面へ同じ問いが 2 つ並び、(2) user が 2 つ続くので
	/// チャットテンプレートが壊れる（``alternatingHistory(_:)``）。(2) は履歴を
	/// 整えることで防いでいるが、(1) は残骸を消さないと直らない。
	///
	/// 思考（`reasoning`）だけでも出ていれば**残す** — 利用者に見せる価値がある
	/// し、上限に達して答えが出なかったことの証拠でもある。
	///
	/// - Returns: 取り除いた問いの本文（入力欄へ戻すため）。何も取り除かなかった
	///   ときは nil。
	public mutating func removeFailedExchange(answerID: UUID) -> String?
	{
		guard let index = messages.firstIndex(where: { $0.id == answerID }),
			messages[index].role == .assistant,
			messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			!messages[index].hasReasoning
		else
		{
			return nil
		}
		messages.remove(at: index)
		guard index > 0, messages[index - 1].role == .user
		else
		{
			return nil
		}
		return messages.remove(at: index - 1).text
	}

	/// 発言を足して updatedAt を進める。呼び出し側が更新日時を書き忘れると
	/// 一覧の並びが壊れるので、足す操作をここに閉じる。
	public mutating func append(_ message: ChatMessage, at date: Date = Date())
	{
		messages.append(message)
		updatedAt = date
	}

	/// 本文の冒頭を 1 行に切り詰める（タイトル・一覧の副題用）。
	static func snippet(of text: String, limit: Int) -> String
	{
		let flattened = text
			.replacingOccurrences(of: "\n", with: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		if flattened.isEmpty
		{
			return "新しい会話"
		}
		if flattened.count <= limit
		{
			return flattened
		}
		return String(flattened.prefix(limit)) + "…"
	}
}
