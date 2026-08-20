//
//  ConversationTests.swift
//
//  会話の組み立てと、履歴の切り詰め規則を固定する。切り詰めはローカル LLM の
//  速度とメモリに直結する判断なので、GUI と CLI で同じでなければならない。
//

import XCTest

@testable import MLXChatCore

final class ConversationTests: XCTestCase
{
	private func conversation(userAssistantPairs count: Int) -> Conversation
	{
		var conversation = Conversation()
		for index in 0 ..< count
		{
			conversation.append(ChatMessage(role: .user, text: "u\(index)"))
			conversation.append(ChatMessage(
				role: .assistant, text: "a\(index)",
				stats: GenerationStats(
					generatedTokens: 10, generateSeconds: 1),
				modelID: ModelCatalog.defaultModelID))
		}
		return conversation
	}

	func testDerivedTitleUsesExplicitTitleFirst()
	{
		var conversation = conversation(userAssistantPairs: 1)
		conversation.title = "手で付けた名前"
		XCTAssertEqual(conversation.derivedTitle, "手で付けた名前")
	}

	func testDerivedTitleFallsBackToFirstUserMessage()
	{
		let conversation = conversation(userAssistantPairs: 1)
		XCTAssertEqual(conversation.derivedTitle, "u0")
	}

	func testDerivedTitleForEmptyConversation()
	{
		XCTAssertEqual(Conversation().derivedTitle, "新しい会話")
	}

	func testSnippetFlattensAndTruncates()
	{
		XCTAssertEqual(Conversation.snippet(of: "a\nb", limit: 40), "a b")
		XCTAssertEqual(Conversation.snippet(of: "   ", limit: 40), "新しい会話")
		XCTAssertEqual(Conversation.snippet(of: String(repeating: "x", count: 50), limit: 10),
			String(repeating: "x", count: 10) + "…")
	}

	func testPromptMessagesKeepsMostRecentAndStartsWithUser()
	{
		let conversation = self.conversation(userAssistantPairs: 5)
		// 直近 3 発言（u4 / a4 の前は a3）を求めると先頭が assistant になるので、
		// 1 つ落として user から始める。
		let messages = conversation.promptMessages(maxMessages: 3)
		XCTAssertEqual(messages.map(\.role), [.user, .assistant])
		XCTAssertEqual(messages.map(\.text), ["u4", "a4"])
	}

	func testPromptMessagesPrependsSystemPrompt()
	{
		var conversation = self.conversation(userAssistantPairs: 1)
		conversation.systemPrompt = "  簡潔に  "
		let messages = conversation.promptMessages(maxMessages: 10)
		XCTAssertEqual(messages.first?.role, .system)
		XCTAssertEqual(messages.first?.text, "簡潔に")
		XCTAssertEqual(messages.count, 3)
	}

	func testPromptMessagesWithZeroLimitDropsHistory()
	{
		let conversation = self.conversation(userAssistantPairs: 3)
		XCTAssertTrue(conversation.promptMessages(maxMessages: 0).isEmpty)
	}

	func testStatsAggregation()
	{
		var conversation = self.conversation(userAssistantPairs: 2)
		XCTAssertEqual(conversation.totalGeneratedTokens, 20)
		// 10 トークン / 1 秒 が 2 回 → 20 / 2 = 10 tok/s
		XCTAssertEqual(conversation.averageTokensPerSecond, 10, accuracy: 0.0001)
		XCTAssertEqual(conversation.lastStats?.generatedTokens, 10)

		conversation = Conversation()
		XCTAssertEqual(conversation.averageTokensPerSecond, 0)
		XCTAssertNil(conversation.lastStats)
		XCTAssertEqual(conversation.totalGeneratedTokens, 0)
	}

	func testAppendAdvancesUpdatedAt()
	{
		var conversation = Conversation(updatedAt: Date(timeIntervalSince1970: 0))
		let later = Date(timeIntervalSince1970: 1000)
		conversation.append(ChatMessage(role: .user, text: "hi"), at: later)
		XCTAssertEqual(conversation.updatedAt, later)
	}

	func testRoleLabels()
	{
		XCTAssertEqual(ChatMessage(role: .system, text: "").roleLabel, "システム")
		XCTAssertEqual(ChatMessage(role: .user, text: "").roleLabel, "あなた")
		XCTAssertEqual(ChatMessage(role: .assistant, text: "").roleLabel, "モデル")
	}

	func testCodableRoundTrip() throws
	{
		let conversation = self.conversation(userAssistantPairs: 2)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(
			Conversation.self, from: try encoder.encode(conversation))
		XCTAssertEqual(decoded.messages.count, conversation.messages.count)
		XCTAssertEqual(decoded.id, conversation.id)
	}
}
