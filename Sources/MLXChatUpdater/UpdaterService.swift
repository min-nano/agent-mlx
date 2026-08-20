//
//  UpdaterService.swift
//
//  自動アップデートの実行層。GitHub への問い合わせ・アセットのダウンロード・
//  展開・差し替えスクリプトの起動という「外界に触れる」処理だけを持ち、応答の
//  解釈はすべて UpdateFeed（純ロジック）へ委譲する。
//
//  実行中の .app は自分自身を置き換えられないため、差し替えは同梱スクリプト
//  （Contents/Resources/install-update.sh）を切り離したプロセスとして起動し、
//  アプリの終了を待ってから行う。スクリプトは scripts/install-update.sh が
//  原本で、パッケージング（build.yml の "Bundle helper scripts" ステップ）が
//  バンドルへ同梱する。
//
//  **macOS 専用**。iOS はアプリが自分自身を差し替えることができない（署名済み
//  バンドルを OS が管理するため）ので、iOS 版は「新しいビルドがあります」を
//  出して配布ページへ送るだけにしてある — その判定（UpdateFeed）は共通で、
//  差し替え（このファイル）だけが macOS 限定という切り分け。
//
//  ここは Foundation のみに依存する（AppKit / SwiftUI は使わない）。アプリの
//  終了（NSApplication.terminate）は GUI 側の責任。
//

import Foundation

/// リリース一覧の取得だけを行う軽い入口。iOS からも使う（差し替えはしない）。
public struct ReleaseFeedClient: Sendable
{
	/// リリースを公開しているリポジトリ。テストや fork で差し替えられるよう
	/// イニシャライザ引数にしてある。
	public static let defaultRepository = "min-nano/agent-mlx"

	private let repository: String

	public init(repository: String = ReleaseFeedClient.defaultRepository)
	{
		self.repository = repository
	}

	/// GitHub Releases からチャンネル一覧を取得する。公開リポジトリなので
	/// 認証は不要。タイムアウトを短めにして、起動時の自動確認が UI を
	/// 待たせないようにする。
	public func fetchChannels() async throws -> [UpdateChannel]
	{
		let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100")!
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.timeoutInterval = 20
		let (data, response) = try await URLSession.shared.data(for: request)
		if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode)
		{
			throw UpdaterError.downloadFailed("HTTP \(http.statusCode)")
		}
		return try UpdateFeed.channels(fromReleasesJSON: data)
	}

	/// インストール済みビルドの情報。CI のパッケージングが Info.plist へ
	/// スタンプする（GitCommit / GitBranch / BuildChannel）。開発実行では nil。
	public static var installedCommit: String? { infoString("GitCommit") }
	public static var installedBranch: String? { infoString("GitBranch") }
	public static var installedChannel: String? { infoString("BuildChannel") }

	static func infoString(_ key: String) -> String?
	{
		guard
			let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
			!value.isEmpty, value != "unknown"
		else
		{
			return nil
		}
		return value
	}
}

public enum UpdaterError: Error, LocalizedError
{
	case notInstalledAsApp
	case downloadFailed(String)
	case extractionFailed
	case appNotFoundInArchive
	case noMacOSAsset

	public var errorDescription: String?
	{
		switch self
		{
			case .notInstalledAsApp:
				return "アプリバンドルとして実行されていないため、自動アップデートは使えません。"
			case .downloadFailed(let detail):
				return "アップデートのダウンロードに失敗しました（\(detail)）。"
			case .extractionFailed:
				return "アップデートの展開に失敗しました。"
			case .appNotFoundInArchive:
				return "ダウンロードしたアーカイブに MLXChat.app が見つかりません。"
			case .noMacOSAsset:
				return "このビルドには macOS 版のアセットが含まれていません。"
		}
	}
}

#if os(macOS)

	/// ダウンロード・展開まで済んだ更新。launchInstaller へ渡す。
	public struct StagedUpdate: Sendable
	{
		/// 展開済みの新しい MLXChat.app。
		public let stagedApp: URL
		/// 置き換え先（現在実行中のアプリバンドル）。
		public let installTarget: URL
		/// バンドル同梱の差し替えスクリプト。
		public let installScript: URL
	}

	public final class UpdaterService
	{
		public static let defaultRepository = ReleaseFeedClient.defaultRepository

		private let feed: ReleaseFeedClient

		public init(repository: String = UpdaterService.defaultRepository)
		{
			self.feed = ReleaseFeedClient(repository: repository)
		}

		public var installedCommit: String? { ReleaseFeedClient.installedCommit }
		public var installedBranch: String? { ReleaseFeedClient.installedBranch }
		public var installedChannel: String? { ReleaseFeedClient.installedChannel }

		public func fetchChannels() async throws -> [UpdateChannel]
		{
			try await feed.fetchChannels()
		}

		// -----------------------------------------------------------------
		// ダウンロード → 展開（ステージング）
		// -----------------------------------------------------------------

		public func downloadAndStage(_ channel: UpdateChannel) async throws -> StagedUpdate
		{
			guard let assetURL = channel.appAssetURL
			else
			{
				throw UpdaterError.noMacOSAsset
			}
			// バンドル実行でなければ差し替えのしようがないので先に弾く。
			guard
				let script = Bundle.main.url(forResource: "install-update", withExtension: "sh"),
				Bundle.main.bundleURL.pathExtension == "app"
			else
			{
				throw UpdaterError.notInstalledAsApp
			}
			let target = Bundle.main.bundleURL

			let (downloaded, response) = try await URLSession.shared.download(from: assetURL)
			if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode)
			{
				throw UpdaterError.downloadFailed("HTTP \(http.statusCode)")
			}

			let fileManager = FileManager.default
			let work = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
				.appendingPathComponent("mlxchat-update-\(UUID().uuidString)", isDirectory: true)
			try fileManager.createDirectory(at: work, withIntermediateDirectories: true)

			let zip = work.appendingPathComponent(UpdateFeed.appAssetName)
			try fileManager.moveItem(at: downloaded, to: zip)

			// ditto は macOS 標準で、シンボリックリンク・実行権限・リソースを保った
			// まま展開できる（unzip より .app 向き）。
			let extracted = work.appendingPathComponent("extracted", isDirectory: true)
			try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
			let status = try await runProcess(
				"/usr/bin/ditto", arguments: ["-x", "-k", zip.path, extracted.path])
			guard status == 0
			else
			{
				throw UpdaterError.extractionFailed
			}

			let staged = extracted.appendingPathComponent("MLXChat.app", isDirectory: true)
			guard fileManager.fileExists(atPath: staged.path)
			else
			{
				throw UpdaterError.appNotFoundInArchive
			}

			return StagedUpdate(stagedApp: staged, installTarget: target, installScript: script)
		}

		// -----------------------------------------------------------------
		// 差し替えスクリプトの起動
		// -----------------------------------------------------------------

		/// 差し替えスクリプトを切り離して起動する。スクリプトはこのプロセスの
		/// 終了を待ってから .app を置き換えて再起動するので、呼び出し側は成功後
		/// すみやかにアプリを終了させること。
		public func launchInstaller(_ staged: StagedUpdate) throws
		{
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/bin/bash")
			process.arguments = [
				staged.installScript.path,
				String(ProcessInfo.processInfo.processIdentifier),
				staged.stagedApp.path,
				staged.installTarget.path,
			]
			process.standardOutput = FileHandle.nullDevice
			process.standardError = FileHandle.nullDevice
			try process.run()
			// wait しない — 親（このアプリ）が終了しても子は動き続ける。
		}

		// -----------------------------------------------------------------
		// 小さなヘルパー
		// -----------------------------------------------------------------

		private func runProcess(_ path: String, arguments: [String]) async throws -> Int32
		{
			try await withCheckedThrowingContinuation
			{ (continuation: CheckedContinuation<Int32, Error>) in
				let process = Process()
				process.executableURL = URL(fileURLWithPath: path)
				process.arguments = arguments
				process.terminationHandler =
				{ finished in
					continuation.resume(returning: finished.terminationStatus)
				}
				do
				{
					try process.run()
				}
				catch
				{
					process.terminationHandler = nil
					continuation.resume(throwing: error)
				}
			}
		}
	}

#endif
