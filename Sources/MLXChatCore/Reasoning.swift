//
//  Reasoning.swift
//
//  推論モデルが出す「考えている途中」を本文から切り分ける純ロジック。
//
//  なぜ要るか
//  ----------
//  Qwen3 / SmolLM3 / DeepSeek-R1 系は、答えの前に思考を `<think> … </think>` で
//  囲んで出す。そのまま画面に流すと
//    * 答えが数百トークン先まで出てこないように見える
//    * 会話ログが思考で埋まる
//    * **次の生成でその思考を履歴として食べさせてしまう**（コンテキストを浪費し、
//      品質も落ちる。モデル提供元も履歴から外すことを勧めている）
//  という 3 つが同時に起きる。だから受け取った時点で切り分け、本文（answer）と
//  思考（reasoning）を別々に持つ。
//
//  切り分けを Core に置く理由は、これが「判断」だから — どのタグを思考と見なすか、
//  途中まで届いたタグをどう扱うかは、GUI と CLI で違ってはいけない。
//
//  ストリーミングが本題
//  --------------------
//  トークンは 1〜数文字ずつ届くので、`<think>` が `<th` と `ink>` に割れて届く。
//  素朴に「届いた断片にタグが含まれるか」で見ると、割れたタグがそのまま本文に
//  出てしまう。そこで ``ReasoningSplitter`` は
//    * タグの**接頭辞になりうる末尾**だけを内部に保留し
//    * 確定した部分だけを返す
//  という形にしてある。生成の最後に ``flush()`` を呼べば保留分が出る。
//

import Foundation

/// 本文と思考に分かれたテキスト。
public struct ReasoningText: Equatable, Sendable
{
	/// `<think>` の外側（＝利用者に見せる答え）。
	public var answer: String
	/// `<think>` の内側（＝折りたたんで見せる思考）。
	public var reasoning: String

	public init(answer: String = "", reasoning: String = "")
	{
		self.answer = answer
		self.reasoning = reasoning
	}

	/// 思考を含むか。
	public var hasReasoning: Bool
	{
		!reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}

/// 届いた断片を本文と思考へ振り分ける。生成 1 回につき 1 つ作って使い回す。
///
/// ```swift
/// var splitter = ReasoningSplitter()
/// for token in tokens
/// {
///     let chunk = splitter.consume(token)
///     answer += chunk.answer
///     reasoning += chunk.reasoning
/// }
/// let tail = splitter.flush()   // 保留していた末尾を取り出す
/// ```
public struct ReasoningSplitter: Equatable, Sendable
{
	/// 思考の開始タグ。
	public static let openTag = "<think>"
	/// 思考の終了タグ。
	public static let closeTag = "</think>"

	/// まだ確定していない末尾（タグの途中かもしれない部分）。
	private var pending = ""
	/// いま `<think>` の内側にいるか。
	public private(set) var isInsideReasoning = false

	public init() {}

	/// 断片を食わせて、確定したぶんを受け取る。
	public mutating func consume(_ text: String) -> ReasoningText
	{
		pending += text
		var result = ReasoningText()

		// タグが見つかるかぎり切り出しを繰り返す（1 断片に複数のタグが入って
		// いることがある — 例えば全文を一度に食わせたとき）。
		while true
		{
			let tag = isInsideReasoning
				? ReasoningSplitter.closeTag
				: ReasoningSplitter.openTag
			guard let range = pending.range(of: tag)
			else
			{
				break
			}
			let head = String(pending[pending.startIndex ..< range.lowerBound])
			if isInsideReasoning
			{
				result.reasoning += head
			}
			else
			{
				result.answer += head
			}
			pending = String(pending[range.upperBound...])
			isInsideReasoning.toggle()
		}

		// タグが無いぶんは出してよいが、**末尾がタグの途中かもしれない**。
		// その可能性がある長さだけ保留に残す。
		let tag = isInsideReasoning
			? ReasoningSplitter.closeTag
			: ReasoningSplitter.openTag
		let held = ReasoningSplitter.partialTagLength(atEndOf: pending, of: tag)
		let settled = String(pending.dropLast(held))
		pending = String(pending.suffix(held))
		if isInsideReasoning
		{
			result.reasoning += settled
		}
		else
		{
			result.answer += settled
		}
		return result
	}

	/// 保留していた末尾を吐き出して空にする。生成の終わりに 1 回呼ぶ。
	///
	/// ここに残っているのは「タグの途中に見えたが、結局タグではなかった文字列」
	/// なので、捨てずに本文（または思考）へ足す。
	public mutating func flush() -> ReasoningText
	{
		let remaining = pending
		pending = ""
		guard !remaining.isEmpty
		else
		{
			return ReasoningText()
		}
		return isInsideReasoning
			? ReasoningText(reasoning: remaining)
			: ReasoningText(answer: remaining)
	}

	/// 全文を一度に切り分ける（保存済みの本文を読み直すとき用）。
	///
	/// 逐次版を内部で回しているので、**ストリーミングと同じ結果になる**ことが
	/// 構造的に保証される（切り分けの実装が 2 つに割れない）。
	public static func split(_ text: String) -> ReasoningText
	{
		var splitter = ReasoningSplitter()
		var result = splitter.consume(text)
		let tail = splitter.flush()
		result.answer += tail.answer
		result.reasoning += tail.reasoning
		return result
	}

	/// 文字列の末尾が `tag` の途中（＝真の接頭辞）になっている長さ。無ければ 0。
	///
	/// 例: "…答えは<thi" に対して `<think>` を渡すと 4（"<thi" を保留する）。
	static func partialTagLength(atEndOf text: String, of tag: String) -> Int
	{
		let maximum = min(text.count, tag.count - 1)
		guard maximum > 0
		else
		{
			return 0
		}
		for length in stride(from: maximum, through: 1, by: -1)
		{
			if text.suffix(length) == tag.prefix(length)
			{
				return length
			}
		}
		return 0
	}
}

/// 思考（`<think>`）を開いて見せるか畳むかの記憶。
///
/// **自動では開閉しない** — 開閉が変わるのは利用者が操作したときだけ。
/// これは好みの問題ではなく、表示の安定性のための決定です。
///
/// 以前は「考えている間は開く・答えが出たら畳む」という自動の切り替えを
/// 入れていたが、実機で次のことが起きた:
///
/// * 思考は数千文字になる。開いた状態の吹き出しは画面数枚ぶんの高さになる。
/// * 履歴（`ChatView.transcript`）はトークンが届くたびに末尾へ寄せ続けている。
/// * 答えの最初のトークンが届いた瞬間に自動で畳むと、**その高さが一度に消える**。
///   寄せる先の座標は縮む前のもののままなので、内容より下へ飛んでしまい、
///   画面が真っ黒（空白）になる。
///
/// 縮み方が大きいほど戻れなくなるので、「自動で縮めない」と決めるのが唯一の
/// 確実な直し方でした。開いたまま読みたい人は自分で開く（その選択はこの型が
/// 覚えていて、生成が終わっても勝手に閉じない）。
///
/// 記憶を画面（`MessageRow` の `@State`）ではなくここに置いているのも同じ理由で、
/// `LazyVStack` は画面外へ出た行の `@State` を捨てることがある。捨てられると
/// 開いていた思考が勝手に畳まれ、上と同じ「高さが一度に消える」が起きる。
public struct ReasoningDisclosure: Equatable, Sendable
{
	/// 利用者が明示的に選んだ発言（true = 開く）。載っていない発言は畳んだまま。
	private var choices: [UUID: Bool] = [:]

	public init()
	{
	}

	/// この発言の思考を開いて見せるか。既定は畳む。
	public func isExpanded(_ id: UUID) -> Bool
	{
		choices[id] ?? false
	}

	/// 利用者の操作を覚える。
	public mutating func setExpanded(_ expanded: Bool, for id: UUID)
	{
		choices[id] = expanded
	}

	/// 覚えていることを捨てる（会話を切り替えたとき）。
	public mutating func reset()
	{
		choices.removeAll()
	}

	/// 開いている発言の数。テストと、必要になったときの一括操作のため。
	public var expandedCount: Int
	{
		choices.values.filter { $0 }.count
	}
}
