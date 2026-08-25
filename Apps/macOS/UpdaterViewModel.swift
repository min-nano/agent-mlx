//
//  UpdaterViewModel.swift
//
//  自動アップデート画面の状態（macOS 専用）。判定は UpdateFeed（純ロジック）、
//  ネットワークと差し替えは UpdaterService が持ち、ここは状態の受け渡しだけ。
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class UpdaterViewModel: ObservableObject
{
	/// 取得済みのチャンネル（= ブランチごとの最新ビルド）。
	@Published private(set) var channels: [UpdateChannel] = []
	/// 表示用のひとこと。
	@Published private(set) var status: String?
	@Published private(set) var isBusy = false
	@Published var errorMessage: String?

	/// 追いかけるブランチ。既定は安定版（main）。開発版を試したい人だけが変える。
	@AppStorage("updateBranch") var branch: String = "main"
	/// 起動時に自動で確認するか。
	@AppStorage("updateCheckOnLaunch") var checkOnLaunch: Bool = true

	private let service = UpdaterService()

	var installedCommit: String? { service.installedCommit }
	var installedBranch: String? { service.installedBranch }
	var installedChannel: String? { service.installedChannel }

	/// インストール済みビルドの表示（開発実行ならその旨）。
	var installedDescription: String
	{
		guard let commit = installedCommit
		else
		{
			return "開発実行（ビルドスタンプなし）"
		}
		let branch = installedBranch ?? "?"
		let channel = installedChannel ?? "?"
		return "\(branch) / \(commit)（\(channel)）"
	}

	/// いま選んでいるブランチのチャンネル。
	var selectedChannel: UpdateChannel?
	{
		UpdateFeed.channel(named: branch, in: channels)
	}

	/// 更新できるか。
	var updateAvailable: Bool
	{
		guard let channel = selectedChannel
		else
		{
			return false
		}
		return UpdateFeed.updateAvailable(installed: installedCommit, channel: channel)
			&& channel.appAssetURL != nil
	}

	/// 起動時の自動確認。失敗しても黙る（オフライン時に起動のたび
	/// エラーを見せない）。
	func autoCheckOnLaunch() async
	{
		guard checkOnLaunch
		else
		{
			return
		}
		try? await refresh()
	}

	func check() async
	{
		do
		{
			try await refresh()
			status = updateAvailable ? "新しいビルドがあります。" : "最新です。"
		}
		catch
		{
			errorMessage = ErrorDetails.message(for: error)
		}
	}

	private func refresh() async throws
	{
		isBusy = true
		defer { isBusy = false }
		channels = try await service.fetchChannels()
	}

	/// ダウンロード → 展開 → 差し替えスクリプト起動 → 自分を終了。
	///
	/// 実行中の .app は自分自身を置き換えられないので、差し替えは別プロセスが
	/// このアプリの終了を待ってから行う（scripts/install-update.sh）。
	func install() async
	{
		guard let channel = selectedChannel
		else
		{
			return
		}
		isBusy = true
		defer { isBusy = false }
		do
		{
			status = "ダウンロードしています…"
			let staged = try await service.downloadAndStage(channel)
			status = "差し替えて再起動します…"
			try service.launchInstaller(staged)
			NSApplication.shared.terminate(nil)
		}
		catch
		{
			errorMessage = ErrorDetails.message(for: error)
			status = nil
		}
	}
}
