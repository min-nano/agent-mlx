//
//  GenerationStatsTests.swift
//
//  速度の割り算とバイト表記。0 割りで Infinity を画面に出さないことを含め、
//  数字の出し方を 1 か所に固定する。
//

import XCTest

@testable import MLXChatCore

final class GenerationStatsTests: XCTestCase
{
	func testTokensPerSecond()
	{
		let stats = GenerationStats(
			promptTokens: 40, generatedTokens: 100,
			promptSeconds: 2, generateSeconds: 4)
		XCTAssertEqual(stats.tokensPerSecond, 25, accuracy: 0.0001)
		XCTAssertEqual(stats.promptTokensPerSecond, 20, accuracy: 0.0001)
		XCTAssertEqual(stats.totalSeconds, 6, accuracy: 0.0001)
	}

	func testZeroTimeDoesNotProduceInfinity()
	{
		let stats = GenerationStats(
			promptTokens: 10, generatedTokens: 10,
			promptSeconds: 0, generateSeconds: 0)
		XCTAssertEqual(stats.tokensPerSecond, 0)
		XCTAssertEqual(stats.promptTokensPerSecond, 0)
	}

	func testZeroTokensDoesNotProduceNaN()
	{
		let stats = GenerationStats(generatedTokens: 0, generateSeconds: 5)
		XCTAssertEqual(stats.tokensPerSecond, 0)
	}

	func testSummaryLineIncludesEverythingAvailable()
	{
		let stats = GenerationStats(
			promptTokens: 40, generatedTokens: 100,
			promptSeconds: 2, generateSeconds: 4,
			timeToFirstTokenSeconds: 0.35,
			peakMemoryBytes: 2 * 1024 * 1024 * 1024,
			stopReason: .length)
		let line = stats.summaryLine
		XCTAssertTrue(line.contains("25.0 tok/s"), line)
		XCTAssertTrue(line.contains("100 tok"), line)
		XCTAssertTrue(line.contains("TTFT 0.35s"), line)
		XCTAssertTrue(line.contains("2.0 GB"), line)
		XCTAssertTrue(line.contains("length"), line)
	}

	func testSummaryLineOmitsMissingParts()
	{
		let line = GenerationStats(generatedTokens: 4, generateSeconds: 2).summaryLine
		XCTAssertFalse(line.contains("TTFT"), line)
		XCTAssertFalse(line.contains("peak"), line)
		XCTAssertFalse(line.contains("prompt"), line)
		XCTAssertFalse(line.contains("stop"), line)
	}

	func testStopReasonsAreCodable() throws
	{
		for reason in GenerationStats.StopReason.allCases
		{
			let stats = GenerationStats(stopReason: reason)
			let decoded = try JSONDecoder().decode(
				GenerationStats.self, from: try JSONEncoder().encode(stats))
			XCTAssertEqual(decoded, stats)
		}
	}

	func testByteCountFormatting()
	{
		XCTAssertEqual(ByteCount.humanReadable(0), "0 B")
		XCTAssertEqual(ByteCount.humanReadable(-5), "0 B")
		XCTAssertEqual(ByteCount.humanReadable(512), "512 B")
		XCTAssertEqual(ByteCount.humanReadable(2048), "2 KB")
		XCTAssertEqual(ByteCount.humanReadable(3 * 1024 * 1024), "3.0 MB")
		XCTAssertEqual(ByteCount.humanReadable(1536 * 1024 * 1024), "1.5 GB")
		XCTAssertEqual(
			ByteCount.humanReadable(2 * 1024 * 1024 * 1024 * 1024), "2.0 TB")
	}
}
