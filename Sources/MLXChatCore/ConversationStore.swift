//
//  ConversationStore.swift
//
//  会話の保存。1 会話 = 1 つの JSON ファイルにする。
//
//  1 ファイルにまとめない理由: 生成のたびに全会話を書き直すことになり、
//  会話が増えるほど「1 トークン届くたびの保存」が重くなる。分けておけば、
//  更新は当該ファイルだけで済むし、壊れたファイルが 1 つあっても他が読める
//  （読めないファイルは黙って飛ばす — 起動できないアプリにしないため）。
//
//  ファイルシステムには触れるが、判断（並び順・ファイル名の作り方・壊れた
//  ファイルの扱い）はすべてここにあり、一時ディレクトリを渡せば単体テストできる。
//

import Foundation

public struct ConversationStore
{
	/// 会話ファイルを置くディレクトリ。
	public let directory: URL
	private let fileManager: FileManager

	public init(directory: URL, fileManager: FileManager = .default)
	{
		self.directory = directory
		self.fileManager = fileManager
	}

	/// アプリが既定で使う保存先（Application Support/MLXChat/Conversations）。
	///
	/// キャッシュではなく Application Support に置く。キャッシュは OS が予告なく
	/// 消せる領域で、会話を消されては困るため（モデルの重みは逆に
	/// キャッシュへ置く — ModelStorage を参照）。
	public static func defaultDirectory(fileManager: FileManager = .default) throws -> URL
	{
		let base = try fileManager.url(
			for: .applicationSupportDirectory, in: .userDomainMask,
			appropriateFor: nil, create: true)
		return base
			.appendingPathComponent("MLXChat", isDirectory: true)
			.appendingPathComponent("Conversations", isDirectory: true)
	}

	/// 保存済みの会話を新しい順（updatedAt の降順）で返す。
	///
	/// 読めないファイルは飛ばす。JSON の書式を変えたときや、書き込み中に落ちた
	/// ファイルが 1 つあるだけで一覧が空になる、という壊れ方を避ける。
	public func load() throws -> [Conversation]
	{
		guard fileManager.fileExists(atPath: directory.path)
		else
		{
			return []
		}
		let files = try fileManager.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		var result: [Conversation] = []
		for file in files where file.pathExtension == "json"
		{
			guard let data = try? Data(contentsOf: file),
				let conversation = try? decoder.decode(Conversation.self, from: data)
			else
			{
				continue
			}
			result.append(conversation)
		}
		result.sort { $0.updatedAt > $1.updatedAt }
		return result
	}

	/// 1 会話を保存する（既にあれば上書き）。
	public func save(_ conversation: Conversation) throws
	{
		try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(conversation)
		try data.write(to: url(for: conversation.id), options: .atomic)
	}

	/// 1 会話を消す。無ければ何もしない（消し直しでエラーにしない）。
	public func delete(id: UUID) throws
	{
		let file = url(for: id)
		guard fileManager.fileExists(atPath: file.path)
		else
		{
			return
		}
		try fileManager.removeItem(at: file)
	}

	/// 会話 1 本のファイル。UUID をそのままファイル名にする
	/// （タイトルから作るとファイル名に使えない文字・重複・改名の問題が出る）。
	public func url(for id: UUID) -> URL
	{
		directory.appendingPathComponent("\(id.uuidString).json")
	}
}
