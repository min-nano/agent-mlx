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
	///   - includeReasoning: 推論モデルの思考を `<details>` で畳んで添えるか
	///     （既定は false。読み手が欲しいのはたいてい答えのほうなので）
	public static func markdown(
		_ conversation: Conversation,
		includeStats: Bool = true,
		includeReasoning: Bool = false) -> String
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
			// 思考は答えより先に出す（時系列どおり）。GitHub / VS Code など
			// 多くの Markdown 表示は <details> をそのまま畳んでくれるので、
			// 画面の開閉と同じ体験になる。
			if includeReasoning, let reasoning = message.reasoning, message.hasReasoning
			{
				lines.append("<details><summary>考えた過程</summary>")
				lines.append("")
				lines.append(reasoning)
				lines.append("")
				lines.append("</details>")
				lines.append("")
			}
			lines.append(message.displayText)
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
