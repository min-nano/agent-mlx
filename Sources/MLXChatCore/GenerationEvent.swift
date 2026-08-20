//
//  GenerationEvent.swift
//
//  エンジン（MLXChatEngine）から呼び出し側（GUI / CLI）へ流れる出来事。
//  MLX に依存しない値だけで構成してあるので、GUI も CLI も同じ列を同じ順で
//  受け取り、同じ文言で表示できる。
//
//  「いま何をしているか」の文言（GenerationPhase.description）は純ロジックなので
//  テストできる。GUI はこれを映すだけで、状態から文言を作る判断を持たない。
//

import Foundation

/// 生成中に起きること。時系列で流れる。
public enum GenerationEvent: Sendable, Equatable
{
	/// 段階が変わった。
	case phase(GenerationPhase)
	/// モデルのダウンロードが進んだ（0.0 ... 1.0）。
	case downloadProgress(Double)
	/// モデルの読み込みが終わった（かかった秒数）。
	case modelReady(seconds: Double)
	/// 生成されたテキストの断片。到着順に継ぎ足す。
	case token(String)
	/// 生成が終わった（実測値つき）。
	case finished(GenerationStats)
	/// 失敗した。文言は ErrorDetails が組み立てたもの。
	case failed(String)
}

/// 生成の段階。画面の進捗表示と CLI の進捗行がこれを共有する。
public enum GenerationPhase: String, CaseIterable, Sendable, Equatable
{
	/// モデルの重みをダウンロード中（初回のみ・数百 MB〜数 GB）。
	case downloading
	/// 重みをメモリへ読み込み中。
	case loading
	/// プロンプト（会話履歴を含む）を処理中。最初のトークンが出るまでの待ち。
	case prefill
	/// トークンを生成中。
	case generating
	/// 終わった。
	case finished

	/// 画面・CLI に出す説明。
	public var description: String
	{
		switch self
		{
			case .downloading:
				return "モデルをダウンロードしています…"
			case .loading:
				return "モデルを読み込んでいます…"
			case .prefill:
				return "プロンプトを処理しています…"
			case .generating:
				return "生成中…"
			case .finished:
				return "完了"
		}
	}

	/// 進捗バーを出すべき段階か。ダウンロードだけが割合を持ち、他は
	/// 「終わりが読めない」ので不定表示にする（偽の進捗を出さない）。
	public var hasDeterminateProgress: Bool
	{
		self == .downloading
	}
}
