//
//  APICommandTests.swift
//
//  外部連携 API（URL スキーム / CLI 引数）の規則を固定するテスト。
//  ここが通っている限り、GUI・CLI・ライブラリの 3 つの入口は同じ語彙で動く。
//

import XCTest

@testable import MLXChatCore

final class APICommandTests: XCTestCase
{
	// -----------------------------------------------------------------
	// URL スキーム
	// -----------------------------------------------------------------

	func testParseChatURLWithPromptOnly() throws
	{
		let url = URL(string: "mlxchat://chat?prompt=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF")!
		guard case .chat(let request) = try APICommand.parse(url: url)
		else
		{
			return XCTFail("chat として解釈されるべき")
		}
		XCTAssertEqual(request.prompt, "こんにちは")
		XCTAssertEqual(request.modelID, ModelCatalog.defaultModelID)
	}

	func testParseChatURLWithAllParameters() throws
	{
		let url = URL(string:
			"mlxchat://chat?prompt=hi&model=mlx-community/Qwen3-4B-4bit&system=be%20brief"
			+ "&temperature=0.2&topP=0.5&maxTokens=64&repetitionPenalty=1.1&kvBits=8&history=4")!
		guard case .chat(let request) = try APICommand.parse(url: url)
		else
		{
			return XCTFail("chat として解釈されるべき")
		}
		XCTAssertEqual(request.modelID, "mlx-community/Qwen3-4B-4bit")
		XCTAssertEqual(request.systemPrompt, "be brief")
		XCTAssertEqual(request.parameters.temperature, 0.2, accuracy: 0.0001)
		XCTAssertEqual(request.parameters.topP, 0.5, accuracy: 0.0001)
		XCTAssertEqual(request.parameters.maxTokens, 64)
		XCTAssertEqual(request.parameters.repetitionPenalty ?? 0, 1.1, accuracy: 0.0001)
		XCTAssertEqual(request.parameters.kvBits, 8)
		XCTAssertEqual(request.parameters.historyMessageLimit, 4)
	}

	func testParseBenchURL() throws
	{
		let url = URL(string: "mlxchat://bench?model=mlx-community/Qwen3-0.6B-4bit&runs=5&warmup=2&prompt=x")!
		guard case .bench(let request) = try APICommand.parse(url: url)
		else
		{
			return XCTFail("bench として解釈されるべき")
		}
		XCTAssertEqual(request.modelID, "mlx-community/Qwen3-0.6B-4bit")
		XCTAssertEqual(request.runs, 5)
		XCTAssertEqual(request.warmupRuns, 2)
		XCTAssertEqual(request.prompt, "x")
		XCTAssertEqual(request.measuredRuns, 3)
	}

	func testParseBenchURLUsesDefaultsWhenEmpty() throws
	{
		// 値の無い &model= は「指定なし」と同じ扱いにする（URL を機械的に
		// 組み立てる側が空文字を渡してきても弾かない）。
		let url = URL(string: "mlxchat://bench?model=&prompt=")!
		guard case .bench(let request) = try APICommand.parse(url: url)
		else
		{
			return XCTFail("bench として解釈されるべき")
		}
		XCTAssertEqual(request.modelID, ModelCatalog.defaultModelID)
		XCTAssertEqual(request.prompt, BenchmarkRequest.defaultPrompt)
	}

	func testParseURLRejectsOtherScheme() throws
	{
		let url = URL(string: "https://example.com/chat?prompt=hi")!
		XCTAssertThrowsError(try APICommand.parse(url: url))
		{ error in
			XCTAssertEqual(
				error as? APICommandError,
				.unsupportedCommand("https://example.com/chat?prompt=hi"))
		}
	}

	func testParseURLRejectsUnknownCommand()
	{
		let url = URL(string: "mlxchat://train?prompt=hi")!
		XCTAssertThrowsError(try APICommand.parse(url: url))
		{ error in
			XCTAssertEqual(error as? APICommandError, .unsupportedCommand("train"))
		}
	}

	func testParseURLRequiresPrompt()
	{
		let url = URL(string: "mlxchat://chat?model=x")!
		XCTAssertThrowsError(try APICommand.parse(url: url))
		{ error in
			XCTAssertEqual(error as? APICommandError, .missingParameter("prompt"))
		}
	}

	func testParseURLRejectsBadNumbers()
	{
		XCTAssertThrowsError(
			try APICommand.parse(url: URL(string: "mlxchat://chat?prompt=x&maxTokens=abc")!))
		{ error in
			XCTAssertEqual(
				error as? APICommandError,
				.invalidValue(parameter: "maxTokens", value: "abc"))
		}
		XCTAssertThrowsError(
			try APICommand.parse(url: URL(string: "mlxchat://chat?prompt=x&temperature=nope")!))
		{ error in
			XCTAssertEqual(
				error as? APICommandError,
				.invalidValue(parameter: "temperature", value: "nope"))
		}
		XCTAssertThrowsError(
			try APICommand.parse(url: URL(string: "mlxchat://bench?runs=x")!))
	}

	// -----------------------------------------------------------------
	// CLI 引数
	// -----------------------------------------------------------------

	func testParseArgumentsDefaultsToChat() throws
	{
		guard case .chat(let request) = try APICommand.parse(arguments: ["こんにちは"])
		else
		{
			return XCTFail("サブコマンド無しは chat")
		}
		XCTAssertEqual(request.prompt, "こんにちは")
	}

	func testParseArgumentsChatOptions() throws
	{
		let arguments = [
			"chat", "--model", "mlx-community/Qwen3-4B-4bit", "--prompt", "hi",
			"--system", "be brief", "--temperature", "0.3", "--top-p", "0.8",
			"--max-tokens", "128", "--repetition-penalty", "1.05", "--kv-bits", "4",
			"--history", "6", "--output", "/tmp/a.txt",
		]
		guard case .chat(let request) = try APICommand.parse(arguments: arguments)
		else
		{
			return XCTFail("chat として解釈されるべき")
		}
		XCTAssertEqual(request.modelID, "mlx-community/Qwen3-4B-4bit")
		XCTAssertEqual(request.prompt, "hi")
		XCTAssertEqual(request.systemPrompt, "be brief")
		XCTAssertEqual(request.parameters.maxTokens, 128)
		XCTAssertEqual(request.parameters.kvBits, 4)
		XCTAssertEqual(request.parameters.historyMessageLimit, 6)
		XCTAssertEqual(request.outputFile?.path, "/tmp/a.txt")
	}

	func testParseArgumentsShortOptions() throws
	{
		guard case .chat(let request) = try APICommand.parse(
			arguments: ["-m", "mlx-community/Qwen3-0.6B-4bit", "-p", "hi", "-s", "sys",
				"-t", "0.1", "-o", "/tmp/out.txt"])
		else
		{
			return XCTFail("chat として解釈されるべき")
		}
		XCTAssertEqual(request.modelID, "mlx-community/Qwen3-0.6B-4bit")
		XCTAssertEqual(request.systemPrompt, "sys")
		XCTAssertEqual(request.parameters.temperature, 0.1, accuracy: 0.0001)
	}

	func testParseArgumentsBench() throws
	{
		guard case .bench(let request) = try APICommand.parse(
			arguments: ["bench", "-n", "4", "--warmup", "2", "-p", "x", "-m",
				"mlx-community/Qwen3-0.6B-4bit", "--max-tokens", "32"])
		else
		{
			return XCTFail("bench として解釈されるべき")
		}
		XCTAssertEqual(request.runs, 4)
		XCTAssertEqual(request.warmupRuns, 2)
		XCTAssertEqual(request.parameters.maxTokens, 32)
	}

	func testParseArgumentsModels() throws
	{
		XCTAssertEqual(try APICommand.parse(arguments: ["models"]), .models)
	}

	func testParseArgumentsModelsRejectsExtras()
	{
		XCTAssertThrowsError(try APICommand.parse(arguments: ["models", "--model", "x"]))
		{ error in
			XCTAssertEqual(error as? APICommandError, .unknownOption("--model"))
		}
	}

	func testParseArgumentsRejectsUnknownOption()
	{
		XCTAssertThrowsError(try APICommand.parse(arguments: ["chat", "--nope", "1"]))
		{ error in
			XCTAssertEqual(error as? APICommandError, .unknownOption("--nope"))
		}
		XCTAssertThrowsError(try APICommand.parse(arguments: ["bench", "--nope"]))
		{ error in
			XCTAssertEqual(error as? APICommandError, .unknownOption("--nope"))
		}
	}

	func testParseArgumentsRejectsMissingOptionValue()
	{
		XCTAssertThrowsError(try APICommand.parse(arguments: ["chat", "--model"]))
		{ error in
			XCTAssertEqual(error as? APICommandError, .missingParameter("--model"))
		}
	}

	func testParseArgumentsRejectsTooManyPositionals()
	{
		XCTAssertThrowsError(try APICommand.parse(arguments: ["a", "b"]))
		{ error in
			XCTAssertEqual(error as? APICommandError, .tooManyArguments)
		}
	}

	func testParseArgumentsRejectsDuplicatePrompt()
	{
		XCTAssertThrowsError(try APICommand.parse(arguments: ["--prompt", "a", "b"]))
		{ error in
			XCTAssertEqual(error as? APICommandError, .duplicatePrompt)
		}
	}

	func testParseArgumentsRejectsBadNumber()
	{
		XCTAssertThrowsError(try APICommand.parse(arguments: ["--max-tokens", "x"]))
		XCTAssertThrowsError(try APICommand.parse(arguments: ["--top-p", "x"]))
		XCTAssertThrowsError(try APICommand.parse(arguments: ["--kv-bits", "x"]))
		XCTAssertThrowsError(try APICommand.parse(arguments: ["--history", "x"]))
		XCTAssertThrowsError(try APICommand.parse(arguments: ["--repetition-penalty", "x"]))
	}

	// -----------------------------------------------------------------
	// 往復（Request → 引数 → Request）
	// -----------------------------------------------------------------

	func testChatArgumentsRoundTrip() throws
	{
		var request = ChatRequest(
			modelID: "mlx-community/Qwen3-4B-4bit",
			prompt: "説明して",
			systemPrompt: "簡潔に",
			parameters: GenerationParameters(
				temperature: 0.25, topP: 0.9, maxTokens: 256,
				repetitionPenalty: 1.2, kvBits: 8, historyMessageLimit: 10))
		request.outputFile = URL(fileURLWithPath: "/tmp/answer.txt")

		let arguments = APICommand.arguments(for: request)
		guard case .chat(let parsed) = try APICommand.parse(arguments: arguments)
		else
		{
			return XCTFail("chat として解釈されるべき")
		}
		XCTAssertEqual(parsed, request)
	}

	func testChatArgumentsOmitOptionalsWhenUnset() throws
	{
		let request = ChatRequest(prompt: "hi")
		let arguments = APICommand.arguments(for: request)
		XCTAssertFalse(arguments.contains("--kv-bits"))
		XCTAssertFalse(arguments.contains("--repetition-penalty"))
		XCTAssertFalse(arguments.contains("--system"))
		XCTAssertFalse(arguments.contains("--output"))

		// プロンプトが空（標準入力から読む形）なら --prompt も出さない。
		let empty = APICommand.arguments(for: ChatRequest())
		XCTAssertFalse(empty.contains("--prompt"))
	}

	func testBenchArgumentsRoundTrip() throws
	{
		let request = BenchmarkRequest(
			modelID: "mlx-community/Qwen3-0.6B-4bit",
			prompt: "測って",
			runs: 6,
			warmupRuns: 2,
			parameters: GenerationParameters(temperature: 0, maxTokens: 128))
		let arguments = APICommand.arguments(for: request)
		guard case .bench(let parsed) = try APICommand.parse(arguments: arguments)
		else
		{
			return XCTFail("bench として解釈されるべき")
		}
		XCTAssertEqual(parsed, request)
	}

	func testFloatFormattingIsLocaleIndependent()
	{
		// そのまま貼って実行できるコマンドでなければ意味がないので、
		// 小数点は必ず "." になる。
		XCTAssertEqual(APICommand.format(0.5), "0.5")
		XCTAssertEqual(APICommand.format(1), "1")
	}

	func testErrorDescriptionsAreProvided()
	{
		let errors: [APICommandError] = [
			.unsupportedCommand("x"), .missingParameter("y"),
			.invalidValue(parameter: "p", value: "v"), .unknownOption("--z"),
			.tooManyArguments, .duplicatePrompt,
		]
		for error in errors
		{
			XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
		}
	}
}
