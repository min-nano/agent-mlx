//
//  ErrorDetails.swift
//
//  失敗を「利用者が次に何をすればいいか」まで含めた日本語に翻訳する。
//
//  ローカル LLM は失敗の仕方が特徴的で、しかも生の文言が英語の技術メッセージ
//  （"Insufficient Memory"、"unsupported model type"、NSURLError の -1009 など）に
//  なりがち。そのまま出しても打つ手が分からないので、**種類を見分けて対処を
//  添える**ところまでを Core の仕事にする。
//
//  見分けはエラーの文字列に対する純ロジックなので、実機も MLX も要らずテスト
//  できる。GUI・CLI はここが返した文言を出すだけで、独自の解釈を持たない。
//

import Foundation

public enum ErrorDetails
{
	/// 失敗の種類。対処の分岐はこれだけで決まる。
	public enum Kind: String, CaseIterable, Sendable, Equatable
	{
		/// メモリ不足（重みが載らない・生成中に落ちた）。
		case outOfMemory
		/// ネットワークに繋がらない（初回ダウンロード時）。
		case offline
		/// 保存容量が足りない。
		case diskFull
		/// MLXLLM が対応していないモデル形式。
		case unsupportedModel
		/// チャットテンプレートが会話を受け付けなかった。
		case chatTemplate
		/// 利用者が停止した。
		case cancelled
		/// 上記のいずれでもない。
		case unknown
	}

	/// エラーの説明文から種類を見分ける。
	///
	/// 文字列マッチにしているのは、MLX / Metal / Hub のどの層から来るかで
	/// エラーの型が違ううえ、多くが NSError や単なる文言だから。型で分けようと
	/// すると層ごとに分岐が増え、しかも MLX のバージョンで壊れる。
	public static func classify(_ description: String) -> Kind
	{
		let text = description.lowercased()
		// 「キャンセル」を最初に見る。中断すると下位層が二次的なエラー
		// （メモリ解放中の失敗など）を吐くことがあり、そちらを拾うと
		// 「止めただけなのにメモリ不足と言われる」ことになる。
		if text.contains("cancel")
		{
			return .cancelled
		}
		// テンプレートの拒否はメモリ判定より先に見る。文言に "model" を含む
		// ことがあり、後ろに置くと unsupportedModel に吸われる。
		if text.contains("templateexception") || text.contains("roles must alternate")
			|| text.contains("role not supported") || text.contains("jinja")
		{
			return .chatTemplate
		}
		if text.contains("out of memory") || text.contains("insufficient memory")
			|| text.contains("memory limit") || text.contains("failed to allocate")
		{
			return .outOfMemory
		}
		if text.contains("offline") || text.contains("not connected to the internet")
			|| text.contains("network connection was lost")
			|| text.contains("could not connect to the server")
		{
			return .offline
		}
		if text.contains("no space left") || text.contains("disk full")
			|| text.contains("not enough space")
		{
			return .diskFull
		}
		if text.contains("unsupported model") || text.contains("model type")
			|| text.contains("no model factory")
		{
			return .unsupportedModel
		}
		return .unknown
	}

	/// 種類ごとの対処。model が分かっていれば具体名を出す。
	public static func advice(for kind: Kind, modelID: String?) -> String
	{
		let modelName = modelID.flatMap { ModelCatalog.model(id: $0)?.displayName } ?? modelID
		switch kind
		{
			case .outOfMemory:
				var text = "メモリが足りません。"
				if let modelName
				{
					text += "\(modelName) はこの端末には大きすぎる可能性があります。"
				}
				return text
					+ "より小さいモデルを選ぶか、設定の「KV キャッシュ量子化」を 8bit / 4bit にするか、"
					+ "履歴の上限を減らしてみてください。他のアプリを終了させるのも有効です。"
			case .offline:
				return "ネットワークに繋がりませんでした。モデルの初回利用にはダウンロードが要ります"
					+ "（一度落としてしまえば以降はオフラインで動きます）。"
			case .diskFull:
				return "保存容量が足りません。設定画面の「ダウンロード済みモデル」から"
					+ "使っていないモデルを削除してください。"
			case .unsupportedModel:
				return "このモデル形式には対応していません。一覧（`models`）にあるモデルを選んでください。"
			case .chatTemplate:
				var text = ""
				if let modelName
				{
					text += "\(modelName) の"
				}
				return text
					+ "チャット書式に、渡した会話が合いませんでした。"
					+ "モデルによっては「発言が user と assistant で交互に並んでいること」や"
					+ "「system 指示を使わないこと」を要求します。"
					+ "「新しい会話」を作り直すか、設定の「システム指示」を空にしてみてください。"
			case .cancelled:
				return "生成を停止しました。"
			case .unknown:
				return "予期しないエラーです。"
		}
	}

	/// 画面・CLI に出す最終的な文言（対処 + 元のメッセージ）。
	///
	/// 元のメッセージも必ず残す。翻訳しきれない失敗を握りつぶすと、報告を
	/// 受けても原因に辿り着けなくなるため。
	public static func message(for error: Error, modelID: String? = nil) -> String
	{
		let raw = (error as? LocalizedError)?.errorDescription ?? "\(error)"
		return message(rawDescription: raw, modelID: modelID)
	}

	/// 文字列から組み立てる版（テスト・別プロセスからの文言用）。
	public static func message(rawDescription raw: String, modelID: String? = nil) -> String
	{
		let kind = classify(raw)
		if kind == .cancelled
		{
			// 停止は失敗ではないので、技術的な原文は出さない。
			return advice(for: kind, modelID: modelID)
		}
		return advice(for: kind, modelID: modelID) + "\n（詳細: \(raw)）"
	}
}
