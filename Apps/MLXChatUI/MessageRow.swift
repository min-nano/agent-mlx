//
//  MessageRow.swift
//
//  発言 1 つの表示。実測値（tok/s）を吹き出しの下に添えるのがこのアプリの肝で、
//  「答えの良さ」と「出るまでの速さ」を同じ画面で見比べられるようにしてある。
//
//  推論モデル（Qwen3 / SmolLM3 など）の思考は答えの上に**畳んで**出す。切り分け
//  そのものは Core（ReasoningSplitter）が済ませていて、ここは開閉するだけ。
//

import SwiftUI

struct MessageRow: View
{
	let message: ChatMessage
	/// 生成中の発言（本文がまだ増えている途中）か。
	let isStreaming: Bool

	/// 利用者が開閉を操作したか（nil なら自動）。
	///
	/// 既定の挙動を「考えている間は開く・答えが出たら畳む」にしておくと、待ち時間に
	/// 何が起きているかが見えて、読むときには邪魔にならない。ただし一度でも手で
	/// 操作したらそちらを優先する — 勝手に閉じられるのは煩わしいため。
	@State private var expandedByUser: Bool?

	var body: some View
	{
		VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4)
		{
			if message.hasReasoning
			{
				reasoning
			}
			bubble
			if let stats = message.stats
			{
				Text(stats.summaryLine)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			else if isStreaming
			{
				Text(message.hasReasoning && message.text.isEmpty ? "考えています…" : "生成中…")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.frame(
			maxWidth: .infinity,
			alignment: message.role == .user ? .trailing : .leading)
		.textSelection(.enabled)
	}

	// -----------------------------------------------------------------

	private var isExpanded: Binding<Bool>
	{
		Binding(
			get: { expandedByUser ?? (isStreaming && message.text.isEmpty) },
			set: { expandedByUser = $0 })
	}

	@ViewBuilder
	private var reasoning: some View
	{
		DisclosureGroup(isExpanded: isExpanded)
		{
			Text(message.reasoning ?? "")
				.font(.callout)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.top, 4)
		} label: {
			Label(reasoningLabel, systemImage: "brain")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(Color.gray.opacity(0.08))
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.frame(maxWidth: 620, alignment: .leading)
	}

	private var reasoningLabel: String
	{
		guard let reasoning = message.reasoning
		else
		{
			return "考えた過程"
		}
		if isStreaming, message.text.isEmpty
		{
			return "考えています…（\(reasoning.count) 文字）"
		}
		return "考えた過程（\(reasoning.count) 文字）"
	}

	private var bubble: some View
	{
		// 空文字だと吹き出しの高さが潰れるので、空白 1 つで枠を保つ
		// （生成が始まる前の「答えの枠」として見せたい）。
		Text(message.displayText.isEmpty ? " " : message.displayText)
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
