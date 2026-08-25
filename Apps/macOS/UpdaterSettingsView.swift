//
//  UpdaterSettingsView.swift
//
//  macOS の「設定」ウインドウ（アップデート）。
//

import SwiftUI

struct UpdaterSettingsView: View
{
	@EnvironmentObject private var updater: UpdaterViewModel

	var body: some View
	{
		Form
		{
			Section("インストール済み")
			{
				LabeledContent("ビルド", value: updater.installedDescription)
			}

			Section
			{
				Picker("追いかけるブランチ", selection: $updater.branch)
				{
					// 取得前でも選択が空にならないよう main は常に出す。
					if !updater.channels.contains(where: { $0.branch == "main" })
					{
						Text("main（安定版）").tag("main")
					}
					ForEach(updater.channels, id: \.tag)
					{ channel in
						Text(channel.displayName).tag(channel.branch)
					}
				}
				Toggle("起動時に確認する", isOn: $updater.checkOnLaunch)
				HStack
				{
					Button("いま確認する")
					{
						Task { await updater.check() }
					}
					.disabled(updater.isBusy)
					if updater.updateAvailable
					{
						Button("更新して再起動")
						{
							Task { await updater.install() }
						}
						.disabled(updater.isBusy)
						.buttonStyle(.borderedProminent)
					}
					if updater.isBusy
					{
						ProgressView().controlSize(.small)
					}
				}
				if let status = updater.status
				{
					Text(status)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			} header: {
				Text("アップデート")
			} footer: {
				Text("main は安定版、それ以外は PR ごとの開発版です。"
					+ "リリースは CI が作り直すローリング形式なので、"
					+ "「新しいか」ではなく「コミットが違うか」で判定します。")
			}
		}
		.formStyle(.grouped)
		.frame(width: 460)
		.padding()
		.alert(
			"エラー",
			isPresented: Binding(
				get: { updater.errorMessage != nil },
				set: { if !$0 { updater.errorMessage = nil } }))
		{
			Button("OK", role: .cancel) { updater.errorMessage = nil }
		} message: {
			Text(updater.errorMessage ?? "")
		}
	}
}
