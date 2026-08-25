//
//  RequestValidationTests.swift
//
//  つまみの範囲と指示の検査。入口（GUI / CLI / URL / ライブラリ）に関係なく
//  ここが唯一の規則であることを固定する。
//

import XCTest

@testable import MLXChatCore

final class RequestValidationTests: XCTestCase
{
	// -----------------------------------------------------------------
	// GenerationParameters
	// -----------------------------------------------------------------

	func testDefaultParametersAreValid() throws
	{
		XCTAssertNoThrow(try GenerationParameters().validate())
	}

	func testTemperatureRange()
	{
		XCTAssertThrowsError(try GenerationParameters(temperature: -0.1).validate())
		XCTAssertThrowsError(try GenerationParameters(temperature: 2.1).validate())
		XCTAssertThrowsError(try GenerationParameters(temperature: .nan).validate())
		XCTAssertNoThrow(try GenerationParameters(temperature: 0).validate())
		XCTAssertNoThrow(try GenerationParameters(temperature: 2).validate())
	}

	func testTopPRange()
	{
		XCTAssertThrowsError(try GenerationParameters(topP: 1.5).validate())
		XCTAssertThrowsError(try GenerationParameters(topP: .infinity).validate())
	}

	func testMaxTokensRange()
	{
		XCTAssertThrowsError(try GenerationParameters(maxTokens: 0).validate())
		XCTAssertThrowsError(try GenerationParameters(maxTokens: 9000).validate())
	}

	func testRepetitionPenaltyRange()
	{
		XCTAssertThrowsError(try GenerationParameters(repetitionPenalty: 0.5).validate())
		XCTAssertThrowsError(try GenerationParameters(repetitionPenalty: .nan).validate())
		XCTAssertNoThrow(try GenerationParameters(repetitionPenalty: 1.1).validate())
	}

	func testKVBitsMustBeSupported()
	{
		XCTAssertThrowsError(try GenerationParameters(kvBits: 3).validate())
		for bits in GenerationParameters.allowedKVBits
		{
			XCTAssertNoThrow(try GenerationParameters(kvBits: bits).validate())
		}
	}

	func testHistoryLimitRange()
	{
		XCTAssertThrowsError(try GenerationParameters(historyMessageLimit: -1).validate())
		XCTAssertThrowsError(try GenerationParameters(historyMessageLimit: 1000).validate())
		XCTAssertNoThrow(try GenerationParameters(historyMessageLimit: 0).validate())
	}

	func testParameterErrorNamesTheOffendingKnob()
	{
		XCTAssertThrowsError(try GenerationParameters(maxTokens: 0).validate())
		{ error in
			guard case .outOfRange(let name, _)? = error as? ParameterError
			else
			{
				return XCTFail("ParameterError であるべき")
			}
			XCTAssertEqual(name, "maxTokens")
			XCTAssertFalse(error.localizedDescription.isEmpty)
		}
	}

	func testParametersAreCodable() throws
	{
		let parameters = GenerationParameters(
			temperature: 0.1, topP: 0.2, maxTokens: 8,
			repetitionPenalty: 1.3, kvBits: 4, historyMessageLimit: 2)
		let decoded = try JSONDecoder().decode(
			GenerationParameters.self, from: try JSONEncoder().encode(parameters))
		XCTAssertEqual(decoded, parameters)
	}

	// -----------------------------------------------------------------
	// ChatRequest
	// -----------------------------------------------------------------

	func testChatRequestRequiresPrompt()
	{
		XCTAssertThrowsError(try ChatRequest(prompt: "   ").validate())
		{ error in
			XCTAssertEqual(error as? RequestError, .emptyPrompt)
		}
	}

	func testChatRequestRequiresKnownModel()
	{
		XCTAssertThrowsError(try ChatRequest(modelID: "", prompt: "hi").validate())
		{ error in
			XCTAssertEqual(error as? RequestError, .modelNotSpecified)
		}
		XCTAssertThrowsError(try ChatRequest(modelID: "who/knows", prompt: "hi").validate())
		{ error in
			XCTAssertEqual(error as? RequestError, .unknownModel("who/knows"))
		}
	}

	func testChatRequestPropagatesParameterErrors()
	{
		XCTAssertThrowsError(
			try ChatRequest(
				prompt: "hi",
				parameters: GenerationParameters(maxTokens: 0)).validate())
	}

	func testValidChatRequest()
	{
		XCTAssertNoThrow(try ChatRequest(prompt: "hi").validate())
	}

	func testNextBuildsRequestFromConversation()
	{
		var conversation = Conversation(
			systemPrompt: "簡潔に", modelID: "mlx-community/Qwen3-4B-4bit")
		conversation.append(ChatMessage(role: .user, text: "u0"))
		conversation.append(ChatMessage(role: .assistant, text: "a0"))

		let request = ChatRequest.next(
			in: conversation, prompt: "u1",
			parameters: GenerationParameters(historyMessageLimit: 10))
		XCTAssertEqual(request.modelID, "mlx-community/Qwen3-4B-4bit")
		XCTAssertEqual(request.systemPrompt, "簡潔に")
		XCTAssertEqual(request.prompt, "u1")
		// system は systemPrompt として別に持つので、history には入らない。
		XCTAssertEqual(request.history.map(\.role), [.user, .assistant])
	}

	func testRequestErrorDescriptions()
	{
		let errors: [RequestError] = [
			.modelNotSpecified, .unknownModel("x"), .emptyPrompt, .invalidRunCount(0),
		]
		for error in errors
		{
			XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
		}
	}
}
