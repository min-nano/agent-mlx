//
//  RootView.swift
//
//  画面の入れ物。中身（ChatView / ModelLibraryView / ParametersView /
//  BenchmarkView）は 2 つの OS で完全に共通で、**違うのはここだけ**にしてある。
//    iOS   … 下タブ（片手で切り替えられる）
//    macOS … サイドバー（会話の履歴を常に見せられる）
//

import SwiftUI

/// 表示する画面。iOS のタブと macOS のサイドバーで同じ列挙を共有する。
enum Pane: String, CaseIterable, Identifiable, Hashable
{
	case chat
	case models
	case benchmark
	case settings

	var id: String { rawValue }

	var title: String
	{
		switch self
		{
			case .chat:
				return "チャット"
			case .models:
				return "モデル"
			case .benchmark:
				return "ベンチマーク"
			case .settings:
				return "設定"
		}
	}

	var symbol: String
	{
		switch self
		{
			case .chat:
				return "bubble.left.and.bubble.right"
			case .models:
				return "shippingbox"
			case .benchmark:
				return "speedometer"
			case .settings:
				return "slider.horizontal.3"
		}
	}

	@ViewBuilder
	var content: some View
	{
		switch self
		{
			case .chat:
				ChatView()
			case .models:
				ModelLibraryView()
			case .benchmark:
				BenchmarkView()
			case .settings:
				ParametersView()
		}
	}
}

struct RootView: View
{
	@EnvironmentObject private var chat: ChatViewModel
	@State private var pane: Pane = .chat

	var body: some View
	{
		#if os(iOS)
			TabView(selection: $pane)
			{
				ForEach(Pane.allCases)
				{ pane in
					NavigationStack
					{
						pane.content
					}
					.tabItem
					{
						Label(pane.title, systemImage: pane.symbol)
					}
					.tag(pane)
				}
			}
		#else
			NavigationSplitView
			{
				sidebar
			} detail: {
				NavigationStack
				{
					pane.content
				}
			}
		#endif
	}

	#if os(macOS)
		private var sidebar: some View
		{
			List(selection: $pane)
			{
				Section
				{
					ForEach(Pane.allCases)
					{ pane in
						Label(pane.title, systemImage: pane.symbol).tag(pane)
					}
				}
				Section("履歴")
				{
					ForEach(chat.conversations)
					{ conversation in
						Button
						{
							chat.open(conversation)
							pane = .chat
						} label: {
							VStack(alignment: .leading, spacing: 2)
							{
								Text(conversation.derivedTitle)
									.lineLimit(1)
								Text(conversation.updatedAt, style: .date)
									.font(.caption2)
									.foregroundStyle(.secondary)
							}
						}
						.buttonStyle(.plain)
						.contextMenu
						{
							Button("削除", role: .destructive)
							{
								chat.delete(conversation)
							}
						}
					}
				}
			}
			.listStyle(.sidebar)
			.frame(minWidth: 220)
		}
	#endif
}
