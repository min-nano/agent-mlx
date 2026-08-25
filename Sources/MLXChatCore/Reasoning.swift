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

	/// 本文・思考それぞれについて、空白以外を 1 文字でも出したか。
	/// 出すまでの空白は捨てる（＝先頭の空行を作らない）。
	private var answerHasContent = false
	private var reasoningHasContent = false
	/// 出すのを保留している末尾の空白。次に空白以外が来たら一緒に出し、
	/// 来なければそのまま捨てる（＝末尾の空行を作らない）。
	private var heldAnswerSpace = ""
	private var heldReasoningSpace = ""

	public init() {}

	/// 断片を食わせて、確定したぶんを受け取る。
	public mutating func consume(_ text: String) -> ReasoningText
	{
		pending += text
		var result = ReasoningText()

		// タグが見つかるかぎり切り出しを繰り返す（1 断片に複数のタグが入って
		// いることがある — 例えば全文を一度に食わせたとき）。
		//
		// **どちらの状態でも両方のタグを探す。** 閉じているときに `</think>` を
		// 探していないと、思考の外側に来た閉じタグを見つけられず、タグがそのまま
		// 本文に出る（実機で見えた。壊れかけの小さいモデルは `</think>` を 2 回
		// 出すことがある）。タグは状態を決めるためのもので、**本文にも思考にも
		// 出さない**。閉じているものをもう一度閉じても、開いているものをもう一度
		// 開いても、状態が変わらないだけで害はない。
		while let match = ReasoningSplitter.firstTag(in: pending)
		{
			emit(String(pending[pending.startIndex ..< match.range.lowerBound]), into: &result)
			pending = String(pending[match.range.upperBound...])
			isInsideReasoning = match.opens
		}

		// タグが無いぶんは出してよいが、**末尾がタグの途中かもしれない**。
		// その可能性がある長さだけ保留に残す。両方のタグについて見る —
		// `</th` は `<think>` の接頭辞ではないので、閉じタグを見ないと
		// 割れて届いた閉じタグを取りこぼす。
		let held = max(
			ReasoningSplitter.partialTagLength(atEndOf: pending, of: ReasoningSplitter.openTag),
			ReasoningSplitter.partialTagLength(atEndOf: pending, of: ReasoningSplitter.closeTag))
		let settled = String(pending.dropLast(held))
		pending = String(pending.suffix(held))
		emit(settled, into: &result)
		return result
	}

	/// 確定した断片を、いまの状態に応じて本文か思考へ足す。
	///
	/// ここを通すことで、前後の空白の扱いが 1 か所に閉じる。
	private mutating func emit(_ text: String, into result: inout ReasoningText)
	{
		guard !text.isEmpty
		else
		{
			return
		}
		if isInsideReasoning
		{
			ReasoningSplitter.append(
				text,
				to: &result.reasoning,
				hasContent: &reasoningHasContent,
				held: &heldReasoningSpace)
		}
		else
		{
			ReasoningSplitter.append(
				text,
				to: &result.answer,
				hasContent: &answerHasContent,
				held: &heldAnswerSpace)
		}
	}

	/// 前後の空白を落としながら足す。**間の空白は保つ**。
	///
	/// なぜ要るか: 推論モデルは `</think>` のあとに改行を 2 つ置いてから答えを
	/// 書き始めるので、素直に流すと吹き出しの先頭に空行ができる（実機で見えた）。
	/// 逆に末尾の改行は吹き出しの下に余白を作る。
	///
	/// ストリーミングでは「これが最後の断片か」が分からないので、
	/// `trimmingCharacters` は使えない。代わりに
	///
	///   * 空白以外をまだ 1 文字も出していない間は、先頭の空白を捨てる
	///   * 末尾の空白は**保留**し、次に空白以外が来たときに一緒に出す
	///
	/// とする。保留のまま生成が終われば、その空白は出ないまま消える。
	/// 結果は `trimmingCharacters(in: .whitespacesAndNewlines)` と同じで、
	/// しかも途中経過の見え方が最終形と食い違わない。
	private static func append(
		_ text: String,
		to destination: inout String,
		hasContent: inout Bool,
		held: inout String)
	{
		let body = text.drop(while: { $0.isWhitespace })
		if hasContent
		{
			// 直前に確定した文字があるなら、間の空白として保留に足す。
			held += text.prefix(text.count - body.count)
		}
		guard !body.isEmpty
		else
		{
			return
		}
		let trailing = body.reversed().prefix(while: { $0.isWhitespace }).count
		destination += held + String(body.dropLast(trailing))
		held = String(body.suffix(trailing))
		hasContent = true
	}

	/// 保留していた末尾を吐き出して空にする。生成の終わりに 1 回呼ぶ。
	///
	/// ここに残っているのは「タグの途中に見えたが、結局タグではなかった文字列」
	/// なので、捨てずに本文（または思考）へ足す。
	public mutating func flush() -> ReasoningText
	{
		let remaining = pending
		pending = ""
		var result = ReasoningText()
		emit(remaining, into: &result)
		return result
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

	/// 先に現れるほうのタグ。`opens` は「見つかったのが開きタグか」。
	static func firstTag(in text: String) -> (range: Range<String.Index>, opens: Bool)?
	{
		let open = text.range(of: ReasoningSplitter.openTag)
		let close = text.range(of: ReasoningSplitter.closeTag)
		switch (open, close)
		{
			case (nil, nil):
				return nil
			case (let open?, nil):
				return (open, true)
			case (nil, let close?):
				return (close, false)
			case (let open?, let close?):
				return open.lowerBound < close.lowerBound ? (open, true) : (close, false)
		}
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
