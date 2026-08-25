//
//  MLXChatIOSApp.swift
//
//  iOS 版のエントリポイント。GUI はロジックを持たない薄いシェルで、実処理は
//  MLXChatCore（判断）と MLXChatEngine（MLX）に委譲する。
//
//  自動アップデートは持たない。iOS ではアプリが自分自身を差し替えられないため
//  （新しいビルドは配布ページから入れ直す）。更新の有無の判定そのものは
//  MLXChatUpdater の UpdateFeed が持っていて macOS 版と共通だが、iOS 版はその
//  画面を出さない。
//
//  外部アプリ連携: Info.plist の CFBundleURLTypes で mlxchat:// を宣言しており、
//  onOpenURL 経由で APICommand（Core）が解釈する。ショートカットアプリから
//    mlxchat://chat?prompt=... で生成を投げられる。
//

import SwiftUI

@main
struct MLXChatIOSApp: App
{
	@StateObject private var chat = ChatViewModel()

	var body: some Scene
	{
		WindowGroup
		{
			RootView()
				.environmentObject(chat)
				.onOpenURL
				{ url in
					chat.handle(url: url)
				}
		}
	}
}
