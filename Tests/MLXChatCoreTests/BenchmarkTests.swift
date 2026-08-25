//
//  BenchmarkTests.swift
//
//  ベンチマークの指示と集計。速度の代表値に中央値を使うこと、ウォームアップを
//  計測から外すことを固定する。
//

import XCTest

@testable import MLXChatCore

final class BenchmarkTests: XCTestCase
{
	private func stats(tokensPerSecond: Double, promptTokensPerSecond: Double = 100,
		ttft: Double? = nil, peak: Int64? = nil) -> GenerationStats
	{
		GenerationStats(
			promptTokens: Int(promptTokensPerSecond),
			generatedTokens: Int(tokensPerSecond),
			promptSeconds: 1,
			generateSeconds: 1,
			timeToFirstTokenSeconds: ttft,
			peakMemoryBytes: peak)
	}

	// -----------------------------------------------------------------
	// BenchmarkRequest
	// -----------------------------------------------------------------

	func testDefaultRequestIsValid()
	{
		XCTAssertNoThrow(try BenchmarkRequest().validate())
		XCTAssertEqual(BenchmarkRequest().measuredRuns, 2)
	}

	func testRunsMustLeaveSomethingToMeasure()
	{
		XCTAssertThrowsError(try BenchmarkRequest(runs: 1, warmupRuns: 1).validate())
		{ error in
			XCTAssertEqual(error as? RequestError, .invalidRunCount(1))
		}
		XCTAssertThrowsError(try BenchmarkRequest(runs: 0, warmupRuns: 0).validate())
		XCTAssertNoThrow(try BenchmarkRequest(runs: 1, warmupRuns: 0).validate())
	}

	func testRequestRejectsUnknownModelAndEmptyPrompt()
	{
		XCTAssertThrowsError(try BenchmarkRequest(modelID: "nope/nope").validate())
		XCTAssertThrowsError(try BenchmarkRequest(prompt: " ").validate())
		XCTAssertThrowsError(
			try BenchmarkRequest(parameters: GenerationParameters(maxTokens: 0)).validate())
	}

	func testNegativeWarmupIsTreatedAsZero()
	{
		XCTAssertEqual(BenchmarkRequest(runs: 3, warmupRuns: -5).measuredRuns, 3)
	}

	// -----------------------------------------------------------------
	// BenchmarkSummary
	// -----------------------------------------------------------------

	func testMedianOfOddAndEvenSamples()
	{
		XCTAssertEqual(BenchmarkSummary.median([3, 1, 2]), 2)
		XCTAssertEqual(BenchmarkSummary.median([4, 1, 2, 3]), 2.5)
		XCTAssertEqual(BenchmarkSummary.median([]), 0)
		XCTAssertEqual(BenchmarkSummary.mean([1, 2, 3]), 2)
		XCTAssertEqual(BenchmarkSummary.mean([]), 0)
	}

	func testSummaryStatistics()
	{
		let summary = BenchmarkSummary(
			modelID: ModelCatalog.defaultModelID,
			runs: [
				stats(tokensPerSecond: 10, ttft: 0.4, peak: 100),
				stats(tokensPerSecond: 30, ttft: 0.2, peak: 300),
				stats(tokensPerSecond: 20, ttft: 0.6, peak: 200),
			],
			warmup: [stats(tokensPerSecond: 5, peak: 50)])

		XCTAssertEqual(summary.medianTokensPerSecond, 20, accuracy: 0.0001)
		XCTAssertEqual(summary.meanTokensPerSecond, 20, accuracy: 0.0001)
		XCTAssertEqual(summary.minTokensPerSecond, 10, accuracy: 0.0001)
		XCTAssertEqual(summary.maxTokensPerSecond, 30, accuracy: 0.0001)
		XCTAssertEqual(summary.medianPromptTokensPerSecond, 100, accuracy: 0.0001)
		XCTAssertEqual(summary.medianTimeToFirstToken ?? 0, 0.4, accuracy: 0.0001)
		XCTAssertEqual(summary.peakMemoryBytes, 300)
		// 計測回（中央値 20）はウォームアップ（5）の 4 倍。
		XCTAssertEqual(summary.warmupPenalty ?? 0, 4, accuracy: 0.0001)
	}

	func testSummaryHandlesMissingOptionalData()
	{
		let summary = BenchmarkSummary(
			modelID: "m", runs: [stats(tokensPerSecond: 10)], warmup: [])
		XCTAssertNil(summary.medianTimeToFirstToken)
		XCTAssertNil(summary.peakMemoryBytes)
		XCTAssertNil(summary.warmupPenalty)
		XCTAssertEqual(summary.tokensPerSecondSamples.count, 1)
	}

	func testEmptySummaryReport()
	{
		let summary = BenchmarkSummary(modelID: "m", runs: [])
		XCTAssertEqual(summary.minTokensPerSecond, 0)
		XCTAssertEqual(summary.maxTokensPerSecond, 0)
		XCTAssertTrue(summary.report().contains("計測できた回がありません"))
	}

	func testReportMentionsEveryAvailableMetric()
	{
		let summary = BenchmarkSummary(
			modelID: "mlx-community/Qwen3-0.6B-4bit",
			runs: [stats(tokensPerSecond: 42, ttft: 0.5, peak: 1024 * 1024 * 1024)],
			warmup: [stats(tokensPerSecond: 21)])
		let report = summary.report()
		XCTAssertTrue(report.contains("mlx-community/Qwen3-0.6B-4bit"), report)
		XCTAssertTrue(report.contains("42.0 tok/s"), report)
		XCTAssertTrue(report.contains("ttft"), report)
		XCTAssertTrue(report.contains("peak GPU"), report)
		XCTAssertTrue(report.contains("warmup"), report)
	}

	func testSummaryIsCodable() throws
	{
		let summary = BenchmarkSummary(
			modelID: "m", runs: [stats(tokensPerSecond: 10)], warmup: [])
		let decoded = try JSONDecoder().decode(
			BenchmarkSummary.self, from: try JSONEncoder().encode(summary))
		XCTAssertEqual(decoded, summary)
	}

	func testBenchmarkEventsAreEquatable()
	{
		XCTAssertEqual(
			BenchmarkEvent.runStarted(index: 0, total: 3, isWarmup: true),
			BenchmarkEvent.runStarted(index: 0, total: 3, isWarmup: true))
		XCTAssertNotEqual(
			BenchmarkEvent.failed("a"), BenchmarkEvent.failed("b"))
		XCTAssertEqual(
			BenchmarkEvent.generation(.token("x")), BenchmarkEvent.generation(.token("x")))
	}
}
