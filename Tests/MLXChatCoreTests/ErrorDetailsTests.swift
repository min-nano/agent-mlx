//
//  ErrorDetailsTests.swift
//
//  失敗の見分けと対処の文言。ローカル LLM は失敗の仕方が特徴的なので、
//  「次に何をすればいいか」が出ることを固定する。
//

import XCTest

@testable import MLXChatCore

final class ErrorDetailsTests: XCTestCase
{
	func testClassifyOutOfMemory()
	{
		XCTAssertEqual(ErrorDetails.classify("Metal: Out of memory"), .outOfMemory)
		XCTAssertEqual(ErrorDetails.classify("Insufficient Memory"), .outOfMemory)
		XCTAssertEqual(ErrorDetails.classify("failed to allocate 4.2 GB"), .outOfMemory)
		XCTAssertEqual(ErrorDetails.classify("exceeded memory limit"), .outOfMemory)
	}

	func testClassifyOffline()
	{
		XCTAssertEqual(
			ErrorDetails.classify("The Internet connection appears to be offline."),
			.offline)
		XCTAssertEqual(
			ErrorDetails.classify("The network connection was lost."), .offline)
		XCTAssertEqual(
			ErrorDetails.classify("Could not connect to the server."), .offline)
	}

	func testClassifyDiskFull()
	{
		XCTAssertEqual(ErrorDetails.classify("No space left on device"), .diskFull)
		XCTAssertEqual(ErrorDetails.classify("not enough space to write"), .diskFull)
	}

	func testClassifyUnsupportedModel()
	{
		XCTAssertEqual(ErrorDetails.classify("unsupported model type: mamba"), .unsupportedModel)
		XCTAssertEqual(ErrorDetails.classify("no model factory available"), .unsupportedModel)
	}

	func testCancellationWinsOverSecondaryErrors()
	{
		// 中断すると下位層が二次的なエラーを吐くことがある。そちらを拾って
		// 「止めただけなのにメモリ不足と言われる」ことにならないよう、
		// キャンセルを最優先で見る。
		XCTAssertEqual(
			ErrorDetails.classify("operation cancelled: out of memory while freeing"),
			.cancelled)
	}

	func testUnknownFallsBack()
	{
		XCTAssertEqual(ErrorDetails.classify("something odd happened"), .unknown)
	}

	func testAdviceIsActionable()
	{
		for kind in ErrorDetails.Kind.allCases
		{
			let advice = ErrorDetails.advice(for: kind, modelID: ModelCatalog.defaultModelID)
			XCTAssertFalse(advice.isEmpty, kind.rawValue)
		}
		// メモリ不足の助言はモデル名を出す（どれを替えればいいか分かるように）。
		let advice = ErrorDetails.advice(
			for: .outOfMemory, modelID: ModelCatalog.defaultModelID)
		XCTAssertTrue(advice.contains("Qwen3 1.7B"), advice)
		// 一覧に無い id でもそのまま出す。
		XCTAssertTrue(
			ErrorDetails.advice(for: .outOfMemory, modelID: "who/knows").contains("who/knows"))
		// id が無ければモデル名の節そのものを出さない。
		XCTAssertFalse(
			ErrorDetails.advice(for: .outOfMemory, modelID: nil)
				.contains("大きすぎる可能性があります"))
	}

	func testMessageKeepsOriginalTextExceptForCancellation()
	{
		let message = ErrorDetails.message(rawDescription: "Out of memory")
		XCTAssertTrue(message.contains("詳細: Out of memory"), message)

		let cancelled = ErrorDetails.message(rawDescription: "cancelled")
		XCTAssertFalse(cancelled.contains("詳細"), cancelled)
	}

	/// 実機で出た文言そのもの。Gemma 3 は交互でない会話を拒む。
	func testClassifiesChatTemplateRejection()
	{
		let raw = "TemplateException(message: Optional(\"Conversation roles must "
			+ "alternate user/assistant/user/assistant/...\"))"
		XCTAssertEqual(ErrorDetails.classify(raw), .chatTemplate)
		XCTAssertEqual(
			ErrorDetails.classify("Jinja error: System role not supported"), .chatTemplate)

		// 対処が読める文言になっていること（原文も残る）。
		let message = ErrorDetails.message(rawDescription: raw)
		XCTAssertTrue(message.contains("新しい会話"), message)
		XCTAssertTrue(message.contains("詳細"), message)
	}

	func testMessageFromError()
	{
		let message = ErrorDetails.message(
			for: RequestError.unknownModel("who/knows"), modelID: nil)
		XCTAssertTrue(message.contains("who/knows"), message)

		struct Plain: Error {}
		XCTAssertFalse(ErrorDetails.message(for: Plain()).isEmpty)
	}
}
