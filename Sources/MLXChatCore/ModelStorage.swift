//
//  ModelStorage.swift
//
//  ダウンロード済みモデルの置き場所・大きさ・削除。
//
//  なぜアプリの機能として必要か: 量子化済みでも 1 モデル 1〜5 GB あり、
//  iPhone では数本入れただけで容量が尽きる。「どれが入っていて、何 GB 使って
//  いて、消せるのはどれか」を見せられないアプリは実用にならない。
//
//  置き場所は MLXLMCommon の defaultHubApi に合わせる（キャッシュディレクトリ配下の
//  `models/<owner>/<name>`）。ここを間違えると「ダウンロード済みなのに一覧に
//  出ない」「消したのに減らない」になるので、**組み立て規則はこの 1 か所**に置く。
//  キャッシュ領域なのは意図どおりで、容量が逼迫したとき OS が消してよい
//  （消えても再ダウンロードで復旧できる）。会話のほうは消えては困るので
//  Application Support に置く（ConversationStore を参照）。
//

import Foundation

/// 端末に入っているモデル 1 本。
public struct DownloadedModel: Identifiable, Equatable, Sendable
{
	/// Hugging Face のリポジトリ id（"mlx-community/Qwen3-1.7B-4bit"）。
	public let id: String
	/// 実体のディレクトリ。
	public let directory: URL
	/// 占有バイト数。
	public let sizeBytes: Int64
	/// 一覧に載っているモデルなら、その定義（載っていなければ nil）。
	public var catalog: CatalogModel? { ModelCatalog.model(id: id) }

	public init(id: String, directory: URL, sizeBytes: Int64)
	{
		self.id = id
		self.directory = directory
		self.sizeBytes = sizeBytes
	}

	/// 画面に出す名前。一覧外（手で置いたもの）は id をそのまま出す。
	public var displayName: String
	{
		catalog?.displayName ?? id
	}
}

public struct ModelStorage
{
	/// HubApi の downloadBase に相当するディレクトリ。
	public let base: URL
	private let fileManager: FileManager

	public init(base: URL, fileManager: FileManager = .default)
	{
		self.base = base
		self.fileManager = fileManager
	}

	/// MLXLMCommon の defaultHubApi と同じ既定の置き場所（キャッシュ）。
	public static func defaultBase(fileManager: FileManager = .default) throws -> URL
	{
		try fileManager.url(
			for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
	}

	/// HubApi がリポジトリを展開するディレクトリ。
	public func directory(for modelID: String) -> URL
	{
		var url = base.appendingPathComponent("models", isDirectory: true)
		for component in modelID.split(separator: "/")
		{
			url = url.appendingPathComponent(String(component), isDirectory: true)
		}
		return url
	}

	/// 重みが入っているか（＝ダウンロード済みか）。
	///
	/// ディレクトリの有無だけでは足りない。ダウンロード中断の残骸で空の
	/// ディレクトリができることがあり、それを「済み」と誤判定すると、
	/// オフラインで開いたときに読み込みが失敗するまで気づけない。
	/// 実際に .safetensors があるかで判定する。
	public func isDownloaded(_ modelID: String) -> Bool
	{
		let directory = self.directory(for: modelID)
		guard let entries = try? fileManager.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil)
		else
		{
			return false
		}
		return entries.contains { $0.pathExtension == "safetensors" }
	}

	/// 入っているモデルを、大きい順に返す。
	///
	/// 走査は `models/<owner>/<name>` の 2 段固定。Hub のリポジトリ id が
	/// そういう形だからで、深く潜って総当たりすると（重みの数だけファイルが
	/// あるので）目に見えて遅くなる。
	public func downloadedModels() -> [DownloadedModel]
	{
		let root = base.appendingPathComponent("models", isDirectory: true)
		guard let owners = try? fileManager.contentsOfDirectory(
			at: root, includingPropertiesForKeys: nil)
		else
		{
			return []
		}
		var result: [DownloadedModel] = []
		for owner in owners
		{
			guard let repositories = try? fileManager.contentsOfDirectory(
				at: owner, includingPropertiesForKeys: nil)
			else
			{
				continue
			}
			for repository in repositories
			{
				let id = "\(owner.lastPathComponent)/\(repository.lastPathComponent)"
				guard isDownloaded(id)
				else
				{
					continue
				}
				result.append(DownloadedModel(
					id: id,
					directory: repository,
					sizeBytes: ModelStorage.size(of: repository, fileManager: fileManager)))
			}
		}
		result.sort { $0.sizeBytes > $1.sizeBytes }
		return result
	}

	/// 入っているモデルの合計サイズ。
	public func totalSizeBytes() -> Int64
	{
		downloadedModels().reduce(0) { $0 + $1.sizeBytes }
	}

	/// 1 本消す。無ければ何もしない。
	public func delete(_ modelID: String) throws
	{
		let directory = self.directory(for: modelID)
		guard fileManager.fileExists(atPath: directory.path)
		else
		{
			return
		}
		try fileManager.removeItem(at: directory)
	}

	/// ディレクトリ以下の合計バイト数。シンボリックリンクは辿らない
	/// （Hub の blob/snapshot 構成で同じ実体を二重に数えないため）。
	static func size(of directory: URL, fileManager: FileManager) -> Int64
	{
		guard let enumerator = fileManager.enumerator(
			at: directory,
			includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
			options: [.skipsHiddenFiles])
		else
		{
			return 0
		}
		var total: Int64 = 0
		for case let url as URL in enumerator
		{
			guard let values = try? url.resourceValues(
				forKeys: [.fileSizeKey, .isRegularFileKey]),
				values.isRegularFile == true,
				let size = values.fileSize
			else
			{
				continue
			}
			total += Int64(size)
		}
		return total
	}
}
