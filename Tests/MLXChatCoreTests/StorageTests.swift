//
//  StorageTests.swift
//
//  会話の保存とモデルの置き場所。どちらもファイルシステムに触れるが、判断
//  （並び順・壊れたファイルの扱い・ダウンロード済みの見分け方）はコード側に
//  あるので、一時ディレクトリを渡せば実機なしで検証できる。
//

import XCTest

@testable import MLXChatCore

final class StorageTests: XCTestCase
{
	private var root: URL!

	override func setUpWithError() throws
	{
		root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent("mlxchat-tests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws
	{
		try? FileManager.default.removeItem(at: root)
	}

	// -----------------------------------------------------------------
	// ConversationStore
	// -----------------------------------------------------------------

	func testSaveLoadDelete() throws
	{
		let store = ConversationStore(directory: root.appendingPathComponent("conv"))
		XCTAssertTrue(try store.load().isEmpty, "ディレクトリが無くても空を返す")

		var first = Conversation(title: "one", updatedAt: Date(timeIntervalSince1970: 100))
		first.append(ChatMessage(role: .user, text: "hi"),
			at: Date(timeIntervalSince1970: 100))
		let second = Conversation(title: "two", updatedAt: Date(timeIntervalSince1970: 200))
		try store.save(first)
		try store.save(second)

		// 新しい順に並ぶ。
		XCTAssertEqual(try store.load().map(\.title), ["two", "one"])

		try store.delete(id: first.id)
		XCTAssertEqual(try store.load().map(\.title), ["two"])
		// 消し直しても失敗しない。
		XCTAssertNoThrow(try store.delete(id: first.id))
	}

	func testSaveOverwritesSameConversation() throws
	{
		let store = ConversationStore(directory: root.appendingPathComponent("conv"))
		var conversation = Conversation(title: "a")
		try store.save(conversation)
		conversation.title = "b"
		try store.save(conversation)
		XCTAssertEqual(try store.load().map(\.title), ["b"])
	}

	func testBrokenFilesAreSkipped() throws
	{
		let directory = root.appendingPathComponent("conv")
		let store = ConversationStore(directory: directory)
		try store.save(Conversation(title: "good"))
		// 書き込み中に落ちた／書式が変わった、という壊れ方で一覧が空に
		// なってはいけない。
		try "not json".write(
			to: directory.appendingPathComponent("broken.json"),
			atomically: true, encoding: .utf8)
		try "ignored".write(
			to: directory.appendingPathComponent("notes.txt"),
			atomically: true, encoding: .utf8)
		XCTAssertEqual(try store.load().map(\.title), ["good"])
	}

	func testURLForIDUsesUUID()
	{
		let store = ConversationStore(directory: root)
		let id = UUID()
		XCTAssertEqual(store.url(for: id).lastPathComponent, "\(id.uuidString).json")
	}

	func testDefaultDirectoryIsUnderApplicationSupport() throws
	{
		let directory = try ConversationStore.defaultDirectory()
		XCTAssertEqual(directory.lastPathComponent, "Conversations")
		XCTAssertTrue(directory.path.contains("MLXChat"))
	}

	// -----------------------------------------------------------------
	// ModelStorage
	// -----------------------------------------------------------------

	private func makeModel(_ storage: ModelStorage, id: String, weightBytes: Int) throws
	{
		let directory = storage.directory(for: id)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try Data(repeating: 0, count: weightBytes).write(
			to: directory.appendingPathComponent("model.safetensors"))
		try "{}".write(
			to: directory.appendingPathComponent("config.json"),
			atomically: true, encoding: .utf8)
	}

	func testDirectoryLayoutMatchesHub()
	{
		let storage = ModelStorage(base: root)
		let directory = storage.directory(for: "mlx-community/Qwen3-1.7B-4bit")
		XCTAssertEqual(directory.lastPathComponent, "Qwen3-1.7B-4bit")
		XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "mlx-community")
		XCTAssertEqual(
			directory.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
			"models")
	}

	func testDownloadedDetectionNeedsWeights() throws
	{
		let storage = ModelStorage(base: root)
		XCTAssertFalse(storage.isDownloaded("mlx-community/Qwen3-0.6B-4bit"))

		// ダウンロード中断の残骸（空のディレクトリ）を「済み」と数えない。
		let directory = storage.directory(for: "mlx-community/Qwen3-0.6B-4bit")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		XCTAssertFalse(storage.isDownloaded("mlx-community/Qwen3-0.6B-4bit"))

		try makeModel(storage, id: "mlx-community/Qwen3-0.6B-4bit", weightBytes: 16)
		XCTAssertTrue(storage.isDownloaded("mlx-community/Qwen3-0.6B-4bit"))
	}

	func testDownloadedModelsSortedBySizeAndDeletable() throws
	{
		let storage = ModelStorage(base: root)
		XCTAssertTrue(storage.downloadedModels().isEmpty, "models/ が無くても空を返す")

		try makeModel(storage, id: "mlx-community/Qwen3-0.6B-4bit", weightBytes: 16)
		try makeModel(storage, id: "mlx-community/Qwen3-1.7B-4bit", weightBytes: 64)
		try makeModel(storage, id: "someone/unlisted-model", weightBytes: 32)

		let models = storage.downloadedModels()
		XCTAssertEqual(models.map(\.id), [
			"mlx-community/Qwen3-1.7B-4bit",
			"someone/unlisted-model",
			"mlx-community/Qwen3-0.6B-4bit",
		])
		// 一覧に無いモデルは id をそのまま名前にする。
		XCTAssertEqual(models[1].displayName, "someone/unlisted-model")
		XCTAssertNil(models[1].catalog)
		XCTAssertEqual(models[0].displayName, "Qwen3 1.7B")
		XCTAssertGreaterThan(storage.totalSizeBytes(), 100)

		try storage.delete("mlx-community/Qwen3-1.7B-4bit")
		XCTAssertFalse(storage.isDownloaded("mlx-community/Qwen3-1.7B-4bit"))
		// 消し直しても失敗しない。
		XCTAssertNoThrow(try storage.delete("mlx-community/Qwen3-1.7B-4bit"))
	}

	func testSizeOfMissingDirectoryIsZero()
	{
		XCTAssertEqual(
			ModelStorage.size(
				of: root.appendingPathComponent("nope"), fileManager: .default),
			0)
	}

	func testDefaultBaseIsCachesDirectory() throws
	{
		let base = try ModelStorage.defaultBase()
		XCTAssertTrue(base.path.contains("Cache"), base.path)
	}
}
