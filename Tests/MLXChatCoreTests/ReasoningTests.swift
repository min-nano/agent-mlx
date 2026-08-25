//
//  ReasoningTests.swift
//
//  思考（<think>）の切り分け。**トークンが 1 文字ずつ届いてもタグが本文へ
//  漏れない**ことがこのテストの主眼で、そこが崩れると画面に "<thi" のような
//  かけらが出る。
//

import XCTest

@testable import MLXChatCore

final class ReasoningTests: XCTestCase
{
	/// 1 文字ずつ食わせて、最後に flush した結果をまとめる（実際の
	/// ストリーミングと同じ経路を通す）。
	private func streamed(_ text: String) -> ReasoningText
	{
		var splitter = ReasoningSplitter()
		var result = ReasoningText()
		for character in text
		{
			let chunk = splitter.consume(String(character))
			result.answer += chunk.answer
			result.reasoning += chunk.reasoning
		}
		let tail = splitter.flush()
		result.answer += tail.answer
		result.reasoning += tail.reasoning
		return result
	}

	func testPlainTextHasNoReasoning()
	{
		let result = ReasoningSplitter.split("こんにちは")
		XCTAssertEqual(result.answer, "こんにちは")
		XCTAssertEqual(result.reasoning, "")
		XCTAssertFalse(result.hasReasoning)
	}

	func testSplitsThinkBlock()
	{
		let result = ReasoningSplitter.split("<think>まず整理する</think>答えは 42 です")
		XCTAssertEqual(result.reasoning, "まず整理する")
		XCTAssertEqual(result.answer, "答えは 42 です")
		XCTAssertTrue(result.hasReasoning)
	}

	func testTextBeforeAndAfterTheBlock()
	{
		let result = ReasoningSplitter.split("前<think>中</think>後")
		XCTAssertEqual(result.answer, "前後")
		XCTAssertEqual(result.reasoning, "中")
	}

	func testMultipleBlocks()
	{
		let result = ReasoningSplitter.split("<think>A</think>1<think>B</think>2")
		XCTAssertEqual(result.reasoning, "AB")
		XCTAssertEqual(result.answer, "12")
	}

	func testStreamingCharacterByCharacterMatchesWholeText()
	{
		// 1 文字ずつ届く経路と全文を一度に渡す経路で、結果が一致すること。
		// ここが一致しなくなると「画面と保存済みの本文が食い違う」。
		let samples = [
			"<think>考える</think>答え",
			"答えだけ",
			"前<think>中</think>後<think>もう一度</think>おわり",
			"<think>閉じないまま終わる",
			"< think > はタグではない",
			"不等号 5 < 7 と </think っぽい何か",
			// 前後の空白の扱いも、逐次と全文で一致していなければならない。
			"<think>\n考える\n</think>\n\n答え\n",
			"\n\n  前後に空白  \n\n",
			"前 <think>中</think> 後",
			"   ",
			// 壊れた並び（閉じタグが 2 回・開きタグが 2 回）も一致すること。
			"<think>考える</think>答え。\n</think>\n続き",
			"<think>考え<think>まだ考え</think>答え",
			"</think>いきなり閉じる",
		]
		for sample in samples
		{
			XCTAssertEqual(streamed(sample), ReasoningSplitter.split(sample), sample)
		}
	}

	func testPartialTagIsNotLeakedWhileStreaming()
	{
		var splitter = ReasoningSplitter()
		// "<thi" までしか届いていない時点では、まだ何も確定させない。
		XCTAssertEqual(splitter.consume("<thi"), ReasoningText())
		XCTAssertEqual(splitter.consume("nk>"), ReasoningText())
		XCTAssertTrue(splitter.isInsideReasoning)
		XCTAssertEqual(splitter.consume("中身"), ReasoningText(reasoning: "中身"))
	}

	func testPartialTagThatTurnsOutNotToBeATagIsKept()
	{
		// "<thi" で終わったまま生成が終わることがある。捨てずに本文へ戻す。
		var splitter = ReasoningSplitter()
		XCTAssertEqual(splitter.consume("答え<thi"), ReasoningText(answer: "答え"))
		XCTAssertEqual(splitter.flush(), ReasoningText(answer: "<thi"))
		// flush 後は空になる。
		XCTAssertEqual(splitter.flush(), ReasoningText())
	}

	// -----------------------------------------------------------------
	// 壊れたタグの並び
	// -----------------------------------------------------------------

	/// 小さいモデルが壊れると `</think>` を 2 回出すことがある。閉じているのに
	/// もう一度閉じられた形で、片方のタグしか探していないと**タグがそのまま
	/// 本文に出る**（実機で見えた）。タグは本文にも思考にも出さない。
	func testStrayCloseTagIsNotShown()
	{
		let result = ReasoningSplitter.split("<think>考える</think>答え。\n</think>\n続き")
		XCTAssertEqual(result.reasoning, "考える")
		XCTAssertEqual(result.answer, "答え。\n\n続き")
		XCTAssertFalse(result.answer.contains("think"), result.answer)
	}

	/// 思考の外側で閉じタグが割れて届いても取りこぼさない。
	/// （`</th` は `<think>` の接頭辞ではないので、開きタグだけを見ていると漏れる）
	func testSplitCloseTagOutsideReasoningIsStillATag()
	{
		var splitter = ReasoningSplitter()
		XCTAssertEqual(
			splitter.consume("<think>思考</think>答え</th"),
			ReasoningText(answer: "答え", reasoning: "思考"))
		XCTAssertEqual(splitter.consume("ink>続き"), ReasoningText(answer: "続き"))
		XCTAssertEqual(splitter.flush(), ReasoningText())
	}

	/// 開いているのにもう一度開かれた場合も、状態が変わらないだけ。
	func testStrayOpenTagIsNotShown()
	{
		let result = ReasoningSplitter.split("<think>考え<think>まだ考え</think>答え")
		XCTAssertEqual(result.reasoning, "考えまだ考え")
		XCTAssertEqual(result.answer, "答え")
	}

	// -----------------------------------------------------------------
	// 前後の空白
	// -----------------------------------------------------------------

	/// 推論モデルは `</think>` のあとに改行を置いてから答えを書き始める。
	/// そのまま流すと吹き出しの先頭に空行ができる（実機で見えた）。
	func testBlankLinesAroundTheAnswerAreDropped()
	{
		let result = ReasoningSplitter.split("<think>\n考える\n</think>\n\nこんにちは！\n")
		XCTAssertEqual(result.answer, "こんにちは！")
		XCTAssertEqual(result.reasoning, "考える")
	}

	/// 落とすのは前後だけ。段落の区切り（間の空行）は残す。
	func testBlankLinesInsideTheAnswerAreKept()
	{
		let result = ReasoningSplitter.split("\n一段落目\n\n二段落目\n\n")
		XCTAssertEqual(result.answer, "一段落目\n\n二段落目")
	}

	/// ストリーミングでも同じ結果になること。末尾の空白は「次に空白以外が
	/// 来たら出す」保留にしてあるので、`trimmingCharacters` を使わずに済む。
	func testTrailingWhitespaceIsHeldUntilMoreTextArrives()
	{
		var splitter = ReasoningSplitter()
		XCTAssertEqual(splitter.consume("\n\n答え"), ReasoningText(answer: "答え"))
		// 改行だけの断片は、この時点では何も出さない。
		XCTAssertEqual(splitter.consume("\n\n"), ReasoningText())
		// 続きが来たら、保留していた改行ごと出す。
		XCTAssertEqual(splitter.consume("続き"), ReasoningText(answer: "\n\n続き"))
		// 来なければ出ないまま終わる。
		XCTAssertEqual(splitter.consume("\n"), ReasoningText())
		XCTAssertEqual(splitter.flush(), ReasoningText())
	}

	/// 空白しか無い応答は空のまま（空白 1 つの本文を作らない）。
	func testWhitespaceOnlyOutputStaysEmpty()
	{
		let result = ReasoningSplitter.split("<think>考えただけ</think>\n\n")
		XCTAssertEqual(result.answer, "")
		XCTAssertEqual(result.reasoning, "考えただけ")
	}

	func testUnclosedBlockStaysReasoning()
	{
		// 上限（maxTokens）に達して </think> が来ないまま終わる、は実際に起きる。
		let result = ReasoningSplitter.split("<think>まだ考えている途中")
		XCTAssertEqual(result.reasoning, "まだ考えている途中")
		XCTAssertEqual(result.answer, "")
	}

	func testIsInsideReasoningTracksState()
	{
		var splitter = ReasoningSplitter()
		XCTAssertFalse(splitter.isInsideReasoning)
		_ = splitter.consume("<think>")
		XCTAssertTrue(splitter.isInsideReasoning)
		_ = splitter.consume("</think>")
		XCTAssertFalse(splitter.isInsideReasoning)
	}

	func testPartialTagLengthHelper()
	{
		let tag = ReasoningSplitter.openTag
		XCTAssertEqual(ReasoningSplitter.partialTagLength(atEndOf: "答え<thi", of: tag), 4)
		XCTAssertEqual(ReasoningSplitter.partialTagLength(atEndOf: "答え", of: tag), 0)
		XCTAssertEqual(ReasoningSplitter.partialTagLength(atEndOf: "", of: tag), 0)
		// 完全一致は「途中」ではない（呼び出し側が先に切り出している）。
		XCTAssertEqual(ReasoningSplitter.partialTagLength(atEndOf: "<think>", of: tag), 0)
	}

	func testWhitespaceOnlyReasoningDoesNotCount()
	{
		let result = ReasoningSplitter.split("<think>   \n </think>答え")
		XCTAssertFalse(result.hasReasoning)
		XCTAssertEqual(result.answer, "答え")
	}

	// -----------------------------------------------------------------
	// ChatMessage との組み合わせ
	// -----------------------------------------------------------------

	func testMessageHasReasoning()
	{
		XCTAssertFalse(ChatMessage(role: .assistant, text: "a").hasReasoning)
		XCTAssertFalse(
			ChatMessage(role: .assistant, text: "a", reasoning: "  ").hasReasoning)
		XCTAssertTrue(
			ChatMessage(role: .assistant, text: "a", reasoning: "考えた").hasReasoning)
	}

	func testDisplayTextExplainsThinkingOnlyAnswers()
	{
		// 生成中（stats がまだ無い）は空のまま — 枠だけ出して待つ。
		let streaming = ChatMessage(role: .assistant, text: "", reasoning: "考え中")
		XCTAssertEqual(streaming.displayText, "")

		// 終わったのに本文が無いなら、上限に達したと伝える。
		let exhausted = ChatMessage(
			role: .assistant, text: "",
			stats: GenerationStats(stopReason: .length), reasoning: "考え中")
		XCTAssertTrue(exhausted.displayText.contains("上限に達しました"), exhausted.displayText)

		// 本文があるならそのまま。
		let done = ChatMessage(
			role: .assistant, text: "答え",
			stats: GenerationStats(), reasoning: "考えた")
		XCTAssertEqual(done.displayText, "答え")
	}

	func testReasoningIsNotSentBackToTheModel()
	{
		// 思考は text ではなく reasoning に入るので、履歴には自動的に載らない。
		var conversation = Conversation()
		conversation.append(ChatMessage(role: .user, text: "質問"))
		conversation.append(ChatMessage(
			role: .assistant, text: "答え", reasoning: "長い思考"))
		let history = conversation.promptMessages(maxMessages: 10)
		XCTAssertEqual(history.map(\.text), ["質問", "答え"])
		XCTAssertFalse(history.contains { $0.text.contains("長い思考") })
	}

	func testMarkdownCanFoldReasoning()
	{
		var conversation = Conversation(title: "t")
		conversation.append(ChatMessage(
			role: .assistant, text: "答え", reasoning: "考えた"))

		let without = Transcript.markdown(conversation)
		XCTAssertFalse(without.contains("考えた"), without)
		XCTAssertFalse(without.contains("<details>"), without)

		let with = Transcript.markdown(conversation, includeReasoning: true)
		XCTAssertTrue(with.contains("<details><summary>考えた過程</summary>"), with)
		XCTAssertTrue(with.contains("考えた"), with)
	}

	func testMessageWithReasoningIsCodable() throws
	{
		let message = ChatMessage(role: .assistant, text: "答え", reasoning: "考えた")
		let decoded = try JSONDecoder().decode(
			ChatMessage.self, from: try JSONEncoder().encode(message))
		XCTAssertEqual(decoded, message)
	}

	// -----------------------------------------------------------------
	// 開閉の記憶（ReasoningDisclosure）
	// -----------------------------------------------------------------

	/// 既定は畳む。**自動では開かない**ことがこの型の要点で、生成の途中で
	/// 勝手に開閉すると履歴の高さが一度に変わり、スクロール位置が内容より
	/// 下へ飛んで画面が空白になる（実機で踏んだ）。
	func testReasoningIsCollapsedByDefault()
	{
		let disclosure = ReasoningDisclosure()
		XCTAssertFalse(disclosure.isExpanded(UUID()))
		XCTAssertEqual(disclosure.expandedCount, 0)
	}

	/// 利用者が開いたら、そのまま覚えている（生成が終わっても畳まない）。
	func testRemembersUserChoicePerMessage()
	{
		let opened = UUID()
		let untouched = UUID()
		var disclosure = ReasoningDisclosure()
		disclosure.setExpanded(true, for: opened)

		XCTAssertTrue(disclosure.isExpanded(opened))
		XCTAssertFalse(disclosure.isExpanded(untouched))
		XCTAssertEqual(disclosure.expandedCount, 1)

		disclosure.setExpanded(false, for: opened)
		XCTAssertFalse(disclosure.isExpanded(opened))
		XCTAssertEqual(disclosure.expandedCount, 0)
	}

	/// 会話を切り替えたら忘れる（発言の id は会話をまたいで再利用しない）。
	func testResetForgetsEverything()
	{
		let id = UUID()
		var disclosure = ReasoningDisclosure()
		disclosure.setExpanded(true, for: id)
		disclosure.reset()
		XCTAssertFalse(disclosure.isExpanded(id))
		XCTAssertEqual(disclosure.expandedCount, 0)
	}

	/// 画面（ChatView）は開閉が変わったことを Equatable で見て末尾へ寄せ直す。
	/// 等しさが壊れるとその寄せ直しが起きなくなるので、ここで固定しておく。
	func testDisclosureIsEquatable()
	{
		let id = UUID()
		var one = ReasoningDisclosure()
		var other = ReasoningDisclosure()
		XCTAssertEqual(one, other)

		one.setExpanded(true, for: id)
		XCTAssertNotEqual(one, other)

		other.setExpanded(true, for: id)
		XCTAssertEqual(one, other)
	}
}
