//
//  Transcript.swift
//
//  会話の書き出し。純粋な文字列生成なのでテストできる。
//
//  ローカル LLM を「試す」用途では、出た答えと**そのときの速度・モデル**を
//  一緒に人へ渡したいことが多い（比較して初めて意味が出る数字なので）。
//  だから書き出しには実測値も載せる。
//

import Foundation

public enum Transcript
{
	/// 会話を Markdown にする。
	///
	/// - Parameters:
	///   - conversation: 対象の会話
	///   - includeStats: 各応答の実測値（tok/s など）を添えるか
	public static func markdown(_ conversation: Conversation, includeStats: Bool = true) -> String
	{
		var lines = ["# \(conversation.derivedTitle)", ""]
		let systemPrompt = conversation.systemPrompt
			.trimmingCharacters(in: .whitespacesAndNewlines)
		if !systemPrompt.isEmpty
		{
			lines += ["> システム指示: \(systemPrompt)", ""]
		}
		for message in conversation.messages
		{
			lines.append("## \(message.roleLabel)")
			lines.append("")
			lines.append(message.text)
			lines.append("")
			if includeStats, let stats = message.stats
			{
				let model = message.modelID ?? conversation.modelID
				lines.append("`\(model)` — \(stats.summaryLine)")
				lines.append("")
			}
		}
		return lines.joined(separator: "\n")
	}

	/// 会話を素のテキストにする（コピー用）。
	public static func plainText(_ conversation: Conversation) -> String
	{
		conversation.messages
			.map { "\($0.roleLabel): \($0.text)" }
			.joined(separator: "\n\n")
	}
}
