//
//  PresentationTests.swift
//
//  画面と CLI が共有する文言（段階の説明・書き出し）。GUI がロジックを持たない
//  ためには、これらが Core 側でテストできる純ロジックである必要がある。
//

import XCTest

@testable import MLXChatCore

final class PresentationTests: XCTestCase
{
	func testEveryPhaseHasDescription()
	{
		for phase in GenerationPhase.allCases
		{
			XCTAssertFalse(phase.description.isEmpty, phase.rawValue)
		}
	}

	func testOnlyDownloadHasDeterminateProgress()
	{
		// 終わりが読めない段階に偽の進捗バーを出さない。
		for phase in GenerationPhase.allCases
		{
			XCTAssertEqual(phase.hasDeterminateProgress, phase == .downloading, phase.rawValue)
		}
	}

	func testGenerationEventsAreEquatable()
	{
		XCTAssertEqual(GenerationEvent.phase(.loading), GenerationEvent.phase(.loading))
		XCTAssertNotEqual(GenerationEvent.token("a"), GenerationEvent.token("b"))
		XCTAssertEqual(
			GenerationEvent.downloadProgress(0.5), GenerationEvent.downloadProgress(0.5))
		XCTAssertEqual(GenerationEvent.modelReady(seconds: 1), GenerationEvent.modelReady(seconds: 1))
		XCTAssertEqual(
			GenerationEvent.finished(GenerationStats()),
			GenerationEvent.finished(GenerationStats()))
		XCTAssertEqual(GenerationEvent.failed("x"), GenerationEvent.failed("x"))
	}

	func testMarkdownTranscriptIncludesStatsAndSystemPrompt()
	{
		var conversation = Conversation(title: "実験", systemPrompt: "簡潔に")
		conversation.append(ChatMessage(role: .user, text: "速い？"))
		conversation.append(ChatMessage(
			role: .assistant, text: "はい",
			stats: GenerationStats(generatedTokens: 20, generateSeconds: 1),
			modelID: ModelCatalog.defaultModelID))

		let markdown = Transcript.markdown(conversation)
		XCTAssertTrue(markdown.hasPrefix("# 実験"), markdown)
		XCTAssertTrue(markdown.contains("システム指示: 簡潔に"), markdown)
		XCTAssertTrue(markdown.contains("## あなた"), markdown)
		XCTAssertTrue(markdown.contains("20.0 tok/s"), markdown)
		XCTAssertTrue(markdown.contains(ModelCatalog.defaultModelID), markdown)
	}

	func testMarkdownTranscriptCanOmitStats()
	{
		var conversation = Conversation()
		conversation.append(ChatMessage(
			role: .assistant, text: "はい",
			stats: GenerationStats(generatedTokens: 20, generateSeconds: 1)))
		let markdown = Transcript.markdown(conversation, includeStats: false)
		XCTAssertFalse(markdown.contains("tok/s"), markdown)
		XCTAssertFalse(markdown.contains("システム指示"), markdown)
	}

	func testPlainTextTranscript()
	{
		var conversation = Conversation()
		conversation.append(ChatMessage(role: .user, text: "a"))
		conversation.append(ChatMessage(role: .assistant, text: "b"))
		XCTAssertEqual(Transcript.plainText(conversation), "あなた: a\n\nモデル: b")
	}
}
