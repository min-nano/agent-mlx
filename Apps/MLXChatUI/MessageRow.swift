//
//  MessageRow.swift
//
//  発言 1 つの表示。実測値（tok/s）を吹き出しの下に添えるのがこのアプリの肝で、
//  「答えの良さ」と「出るまでの速さ」を同じ画面で見比べられるようにしてある。
//

import SwiftUI

struct MessageRow: View
{
	let message: ChatMessage
	/// 生成中の発言（本文が空で、まだ増えている途中）か。
	let isStreaming: Bool

	var body: some View
	{
		VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4)
		{
			bubble
			if let stats = message.stats
			{
				Text(stats.summaryLine)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			else if isStreaming
			{
				Text("生成中…")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.frame(
			maxWidth: .infinity,
			alignment: message.role == .user ? .trailing : .leading)
		.textSelection(.enabled)
	}

	private var bubble: some View
	{
		Text(message.text.isEmpty ? " " : message.text)
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(background)
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.frame(maxWidth: 620, alignment: message.role == .user ? .trailing : .leading)
	}

	private var background: Color
	{
		switch message.role
		{
			case .user:
				return Color.accentColor.opacity(0.18)
			case .assistant:
				return Color.gray.opacity(0.15)
			case .system:
				return Color.orange.opacity(0.15)
		}
	}
}
