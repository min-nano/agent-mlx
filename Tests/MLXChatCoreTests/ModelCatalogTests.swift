//
//  ModelCatalogTests.swift
//
//  モデル一覧の不変条件と、端末に合わせた絞り込み。
//

import XCTest

@testable import MLXChatCore

final class ModelCatalogTests: XCTestCase
{
	func testCatalogIsNotEmptyAndIDsAreUnique()
	{
		XCTAssertFalse(ModelCatalog.all.isEmpty)
		XCTAssertEqual(Set(ModelCatalog.all.map(\.id)).count, ModelCatalog.all.count)
	}

	func testCatalogIsSortedBySize()
	{
		// 並びは「まず動かしてみる」から「Mac の本気」への順路そのもの。
		let sizes = ModelCatalog.all.map(\.downloadBytes)
		XCTAssertEqual(sizes, sizes.sorted())
	}

	func testRequiredMemoryExceedsDownloadSize()
	{
		// 重みに加えて KV キャッシュと作業領域が要る。見積もりが逆転していたら
		// 「入るはずが落ちる」ので不変条件として固定する。
		for model in ModelCatalog.all
		{
			XCTAssertGreaterThan(
				model.requiredMemoryBytes, model.downloadBytes, model.id)
		}
	}

	func testDefaultModelIsInCatalog()
	{
		XCTAssertTrue(ModelCatalog.contains(id: ModelCatalog.defaultModelID))
		XCTAssertNotNil(ModelCatalog.model(id: ModelCatalog.defaultModelID))
		XCTAssertNil(ModelCatalog.model(id: "does/not-exist"))
		XCTAssertFalse(ModelCatalog.contains(id: "does/not-exist"))
	}

	func testSubtitleMentionsSizeAndQuantization()
	{
		let model = ModelCatalog.all[0]
		XCTAssertTrue(model.subtitle.contains(model.parameters))
		XCTAssertTrue(model.subtitle.contains(model.quantization))
	}

	func testModelsFittingInBudget()
	{
		let smallest = ModelCatalog.all[0]
		let fitting = ModelCatalog.models(fittingIn: smallest.requiredMemoryBytes)
		XCTAssertEqual(fitting.map(\.id), [smallest.id])
		XCTAssertTrue(ModelCatalog.models(fittingIn: 0).isEmpty)
	}

	func testRecommendedModelFallsBackToSmallest()
	{
		// 1 つも収まらなくても候補ゼロにはしない（画面が空になり何もできなくなる）。
		XCTAssertEqual(ModelCatalog.recommendedModel(forBudget: 0).id, ModelCatalog.all[0].id)
		XCTAssertEqual(
			ModelCatalog.recommendedModel(forBudget: Int64.max).id,
			ModelCatalog.all.last?.id)
	}

	func testCatalogModelIsCodable() throws
	{
		let model = ModelCatalog.all[0]
		let decoded = try JSONDecoder().decode(
			CatalogModel.self, from: try JSONEncoder().encode(model))
		XCTAssertEqual(decoded, model)
	}
}
