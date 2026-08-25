//
//  ModelCatalog.swift
//
//  アプリが提示するモデルの一覧。**唯一の定義**で、GUI のモデル選択・CLI の
//  `models` サブコマンド・URL スキームの `model=` はすべてここを見る。
//
//  なぜ「一覧」を持つのか（Hugging Face の任意の id を打たせないのか）:
//    * mlx-community の量子化済みリポジトリでも、MLXLLM が対応していない
//      アーキテクチャは読み込み時に初めて失敗する。数 GB 落としたあとに
//      「非対応でした」は最悪の体験。
//    * iPhone は搭載メモリの半分ほどでアプリが落とされる（jetsam）。「入るか」の
//      判断には**サイズと必要メモリの数字**が要る。それはリポジトリ名からは分からない。
//  そのため id は MLXLLM の LLMRegistry に載っている（＝対応が確認できている）
//  ものだけを選び、サイズと必要メモリを添えてある。
//
//  数字は概算でよい（±10% は表示にしか効かない）。ただし requiredMemoryBytes は
//  DeviceProfile が「この端末で動くか」を判断する入力なので、**やや多めに**見積もる。
//  落ちるより「出さない」ほうがましだから。
//

import Foundation

/// 一覧に載っている 1 モデル。
public struct CatalogModel: Identifiable, Codable, Equatable, Sendable
{
	/// Hugging Face のリポジトリ id。これがそのままダウンロード元になる。
	public let id: String
	/// 画面に出す名前。
	public let displayName: String
	/// パラメータ数の表記（"1.7B" など）。
	public let parameters: String
	/// 量子化の種類（"4bit" など）。
	public let quantization: String
	/// ダウンロードサイズ（バイト・概算）。
	public let downloadBytes: Int64
	/// 実行に要るメモリ（バイト・概算。重み + KV キャッシュ + 余裕）。
	public let requiredMemoryBytes: Int64
	/// 学習時のコンテキスト長。
	public let contextWindow: Int
	/// 一言メモ（何が得意か・何に注意するか）。
	public let notes: String

	public init(
		id: String,
		displayName: String,
		parameters: String,
		quantization: String,
		downloadBytes: Int64,
		requiredMemoryBytes: Int64,
		contextWindow: Int,
		notes: String)
	{
		self.id = id
		self.displayName = displayName
		self.parameters = parameters
		self.quantization = quantization
		self.downloadBytes = downloadBytes
		self.requiredMemoryBytes = requiredMemoryBytes
		self.contextWindow = contextWindow
		self.notes = notes
	}

	/// 一覧の副題（"1.7B · 4bit · 1.0 GB"）。
	public var subtitle: String
	{
		"\(parameters) · \(quantization) · \(ByteCount.humanReadable(downloadBytes))"
	}
}

public enum ModelCatalog
{
	private static let gb: Int64 = 1024 * 1024 * 1024
	private static let mb: Int64 = 1024 * 1024

	/// 提示するモデル（小さい順）。並びは「まず動かしてみる」から
	/// 「Mac の本気」までの順路そのものなので、サイズ順を保つこと。
	public static let all: [CatalogModel] = [
		CatalogModel(
			id: "mlx-community/SmolLM-135M-Instruct-4bit",
			displayName: "SmolLM 135M Instruct",
			parameters: "135M", quantization: "4bit",
			downloadBytes: 90 * mb, requiredMemoryBytes: 400 * mb,
			contextWindow: 2048,
			notes: "とにかく軽い。品質より「MLX が動いていること」を確かめる用。"),
		CatalogModel(
			id: "mlx-community/Qwen3-0.6B-4bit",
			displayName: "Qwen3 0.6B",
			parameters: "0.6B", quantization: "4bit",
			downloadBytes: 350 * mb, requiredMemoryBytes: 900 * mb,
			contextWindow: 32768,
			notes: "iPhone でも余裕。日本語もそこそこ通じる最小構成。"),
		CatalogModel(
			id: "mlx-community/gemma-3-1b-it-qat-4bit",
			displayName: "Gemma 3 1B IT (QAT)",
			parameters: "1B", quantization: "4bit",
			downloadBytes: 700 * mb, requiredMemoryBytes: 1500 * mb,
			contextWindow: 32768,
			notes: "量子化を前提に学習（QAT）してあり、このサイズでは品質が良い。"),
		CatalogModel(
			id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
			displayName: "Llama 3.2 1B Instruct",
			parameters: "1B", quantization: "4bit",
			downloadBytes: 730 * mb, requiredMemoryBytes: 1600 * mb,
			contextWindow: 131072,
			notes: "英語中心。長文コンテキストの実験に。"),
		CatalogModel(
			id: "mlx-community/Qwen3-1.7B-4bit",
			displayName: "Qwen3 1.7B",
			parameters: "1.7B", quantization: "4bit",
			downloadBytes: 1000 * mb, requiredMemoryBytes: 2200 * mb,
			contextWindow: 32768,
			notes: "iPhone での常用候補。速度と日本語品質の釣り合いが良い。"),
		CatalogModel(
			id: "mlx-community/SmolLM3-3B-4bit",
			displayName: "SmolLM3 3B",
			parameters: "3B", quantization: "4bit",
			downloadBytes: 1700 * mb, requiredMemoryBytes: 3500 * mb,
			contextWindow: 65536,
			notes: "小型ながら推論が素直。iPhone は 8GB 機推奨。"),
		CatalogModel(
			id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
			displayName: "Llama 3.2 3B Instruct",
			parameters: "3B", quantization: "4bit",
			downloadBytes: 1800 * mb, requiredMemoryBytes: 3600 * mb,
			contextWindow: 131072,
			notes: "3B 級の定番。Mac なら余裕、iPhone は 8GB 機で。"),
		CatalogModel(
			id: "mlx-community/Qwen3-4B-4bit",
			displayName: "Qwen3 4B",
			parameters: "4B", quantization: "4bit",
			downloadBytes: 2300 * mb, requiredMemoryBytes: 4600 * mb,
			contextWindow: 32768,
			notes: "日本語の実用ライン。M シリーズ Mac の入門的な本命。"),
		CatalogModel(
			id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
			displayName: "Mistral 7B Instruct v0.3",
			parameters: "7B", quantization: "4bit",
			downloadBytes: 4100 * mb, requiredMemoryBytes: 7 * gb,
			contextWindow: 32768,
			notes: "7B 級の比較対象。16GB Mac 向け。"),
		CatalogModel(
			id: "mlx-community/Qwen3-8B-4bit",
			displayName: "Qwen3 8B",
			parameters: "8B", quantization: "4bit",
			downloadBytes: 4600 * mb, requiredMemoryBytes: 8 * gb,
			contextWindow: 32768,
			notes: "16GB Mac の常用上限あたり。品質は目に見えて上がる。"),
		CatalogModel(
			id: "mlx-community/gemma-2-9b-it-4bit",
			displayName: "Gemma 2 9B IT",
			parameters: "9B", quantization: "4bit",
			downloadBytes: 5200 * mb, requiredMemoryBytes: 9 * gb,
			contextWindow: 8192,
			notes: "日本語が得意。コンテキストは短め。"),
		CatalogModel(
			id: "mlx-community/Qwen3-30B-A3B-4bit",
			displayName: "Qwen3 30B A3B (MoE)",
			parameters: "30B(A3B)", quantization: "4bit",
			downloadBytes: 17 * gb, requiredMemoryBytes: 20 * gb,
			contextWindow: 32768,
			notes: "MoE。重みは 30B ぶんだが 1 トークンあたり 3B しか使わないので、"
				+ "メモリさえ足りれば驚くほど速い。32GB 以上の Mac 向け。"),
	]

	/// 何も選ばれていないときの既定。iPhone でも Mac でも通る大きさにする
	/// （初回起動で 5GB を落とし始めるアプリにはしない）。
	public static let defaultModelID = "mlx-community/Qwen3-1.7B-4bit"

	/// id からモデルを引く。一覧に無ければ nil。
	public static func model(id: String) -> CatalogModel?
	{
		all.first { $0.id == id }
	}

	/// 一覧に載っている id か。ChatRequest.validate が使う。
	public static func contains(id: String) -> Bool
	{
		model(id: id) != nil
	}

	/// 与えられたメモリ予算（バイト）に収まるモデルだけを返す。
	/// 予算の作り方は DeviceProfile が持つ（ここは判断ではなく絞り込み）。
	public static func models(fittingIn budgetBytes: Int64) -> [CatalogModel]
	{
		all.filter { $0.requiredMemoryBytes <= budgetBytes }
	}

	/// 予算に収まるもののうち最大のモデル。1 つも収まらなければ一覧の最小を返す
	/// （「候補ゼロ」にすると画面が空になり、何もできなくなるため）。
	public static func recommendedModel(forBudget budgetBytes: Int64) -> CatalogModel
	{
		models(fittingIn: budgetBytes).last ?? all[0]
	}
}
