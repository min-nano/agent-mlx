//
//  DeviceProfileTests.swift
//
//  「この端末でどのモデルまで動くか」の判断。実機なしで検証できるよう、
//  入力は搭載メモリと OS だけにしてある。
//

import XCTest

@testable import MLXChatCore

final class DeviceProfileTests: XCTestCase
{
	private let gb: Int64 = 1024 * 1024 * 1024

	func testBudgetIsStricterOniOS()
	{
		let phone = DeviceProfile(physicalMemoryBytes: 8 * gb, platform: .iOS)
		let mac = DeviceProfile(physicalMemoryBytes: 8 * gb, platform: .macOS)
		XCTAssertEqual(phone.memoryBudgetBytes, 4 * gb)
		XCTAssertLessThan(phone.memoryBudgetBytes, mac.memoryBudgetBytes)
	}

	func testNegativeMemoryIsClampedToZero()
	{
		let profile = DeviceProfile(physicalMemoryBytes: -1, platform: .macOS)
		XCTAssertEqual(profile.physicalMemoryBytes, 0)
		XCTAssertEqual(profile.memoryBudgetBytes, 0)
	}

	func testAvailableModelsGrowWithMemory()
	{
		let small = DeviceProfile(physicalMemoryBytes: 4 * gb, platform: .iOS)
		let large = DeviceProfile(physicalMemoryBytes: 64 * gb, platform: .macOS)
		XCTAssertLessThan(small.availableModels.count, large.availableModels.count)
		XCTAssertEqual(large.availableModels.count, ModelCatalog.all.count)
	}

	func testRecommendedModelPrefersCatalogDefaultWhenItFits()
	{
		let mac = DeviceProfile(physicalMemoryBytes: 32 * gb, platform: .macOS)
		XCTAssertEqual(mac.recommendedModel.id, ModelCatalog.defaultModelID)
	}

	func testRecommendedModelShrinksOnSmallDevices()
	{
		let tiny = DeviceProfile(physicalMemoryBytes: 1 * gb, platform: .iOS)
		XCTAssertNotEqual(tiny.recommendedModel.id, ModelCatalog.defaultModelID)
		XCTAssertEqual(tiny.recommendedModel.id, ModelCatalog.all[0].id)
	}

	func testWarningOnlyForModelsThatDoNotFit()
	{
		let phone = DeviceProfile(physicalMemoryBytes: 6 * gb, platform: .iOS)
		let smallest = ModelCatalog.all[0]
		let largest = ModelCatalog.all[ModelCatalog.all.count - 1]
		XCTAssertTrue(phone.canRun(smallest))
		XCTAssertNil(phone.warning(for: smallest))
		XCTAssertFalse(phone.canRun(largest))
		let warning = phone.warning(for: largest) ?? ""
		XCTAssertTrue(warning.contains(largest.displayName), warning)
	}

	func testCurrentProfileReportsSomething()
	{
		// 実行環境（CI の macOS ランナー）でも 0 にはならないはず。
		let profile = DeviceProfile.current()
		XCTAssertGreaterThan(profile.physicalMemoryBytes, 0)
		XCTAssertGreaterThan(profile.memoryBudgetBytes, 0)
		XCTAssertTrue(DeviceProfile.Platform.allCases.contains(profile.platform))
	}
}
