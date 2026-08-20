//
//  MLXChatMacApp.swift
//
//  macOS 版のエントリポイント。GUI はロジックを持たない薄いシェルで、実処理は
//  MLXChatCore（判断）・MLXChatEngine（MLX）・MLXChatUpdater（更新）に委譲する。
//
//  外部アプリ連携: Info.plist の CFBundleURLTypes で mlxchat:// を宣言しており、
//    open "mlxchat://chat?prompt=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF"
//  だけで他アプリから生成を投げられる。同じ語彙が同梱の mlxchat-cli でも使える。
//

import SwiftUI

@main
struct MLXChatMacApp: App
{
	@StateObject private var chat = ChatViewModel()
	@StateObject private var updater = UpdaterViewModel()

	var body: some Scene
	{
		WindowGroup
		{
			RootView()
				.environmentObject(chat)
				.environmentObject(updater)
				.frame(minWidth: 760, minHeight: 520)
				.onOpenURL
				{ url in
					chat.handle(url: url)
				}
				.task
				{
					await updater.autoCheckOnLaunch()
				}
		}
		.commands
		{
			CommandGroup(replacing: .newItem)
			{
				Button("新しい会話")
				{
					chat.newConversation()
				}
				.keyboardShortcut("n")
			}
		}

		Settings
		{
			UpdaterSettingsView()
				.environmentObject(updater)
		}
	}
}
