//
//  DeviceProfile.swift
//
//  「この端末でどのモデルまで動くか」を決める純ロジック。
//
//  ここが独立した型になっているのは、判断の根拠が **端末ごとに違う 1 つの数字
//  （搭載メモリ）と、OS ごとに違う 1 つの係数**だけで表せるからで、そうしておけば
//  実機なしでテストできる。GUI は結果（使えるモデルの一覧・警告）を映すだけで、
//  自分では判断を持たない。
//
//  なぜ「搭載メモリの全部」を使えないのか:
//    * iOS はアプリごとにメモリ上限があり、超えると警告なしに終了させられる
//      （jetsam）。上限は機種と状況で変わるが、実測では概ね搭載量の 50〜60%。
//      MLX の重みは GPU から見えるメモリ（Unified Memory）に載るので、この上限に
//      そのまま数えられる。
//    * macOS はスワップがあるので即死はしないが、重みがスワップに落ちると
//      生成速度が桁で落ちる（＝実質使えない）。OS と他アプリのぶんを残す。
//

import Foundation

/// 端末 1 台の「モデルを載せられる量」。
public struct DeviceProfile: Equatable, Sendable
{
	/// 動作している OS。係数がこれで決まる。
	public enum Platform: String, CaseIterable, Sendable
	{
		case iOS
		case macOS
	}

	/// 搭載メモリ（バイト）。ProcessInfo.physicalMemory を写したもの。
	public let physicalMemoryBytes: Int64
	public let platform: Platform

	public init(physicalMemoryBytes: Int64, platform: Platform)
	{
		self.physicalMemoryBytes = max(0, physicalMemoryBytes)
		self.platform = platform
	}

	/// モデルに割り当ててよいメモリの上限（バイト）。
	///
	/// 係数の根拠:
	///   iOS 0.50   … jetsam の実測下限側に寄せる。落ちるより小さいモデルを
	///                 勧めるほうがましなので、楽観側には振らない。
	///   macOS 0.70 … 残り 30% を OS と他アプリに残す。ここを欲張るとスワップに
	///                 落ちて「動くけれど使い物にならない」状態になる。
	public var memoryBudgetBytes: Int64
	{
		let ratio: Double = platform == .iOS ? 0.50 : 0.70
		return Int64(Double(physicalMemoryBytes) * ratio)
	}

	/// この端末で動かせるモデル。
	public var availableModels: [CatalogModel]
	{
		ModelCatalog.models(fittingIn: memoryBudgetBytes)
	}

	/// 既定で選ぶモデル。カタログの既定が載るならそれを、載らないなら
	/// 予算に収まる最大のものを選ぶ。
	public var recommendedModel: CatalogModel
	{
		if let preferred = ModelCatalog.model(id: ModelCatalog.defaultModelID),
			preferred.requiredMemoryBytes <= memoryBudgetBytes
		{
			return preferred
		}
		return ModelCatalog.recommendedModel(forBudget: memoryBudgetBytes)
	}

	/// 指定のモデルがこの端末で動くと見込めるか。
	public func canRun(_ model: CatalogModel) -> Bool
	{
		model.requiredMemoryBytes <= memoryBudgetBytes
	}

	/// 動かないと見込まれるときに画面へ出す警告（動くなら nil）。
	///
	/// 「選べないようにする」のではなく警告に留めるのは、見積もりが概算だから。
	/// 実機のほうが強いこともあるので、最終的な判断は利用者に残す。
	public func warning(for model: CatalogModel) -> String?
	{
		guard !canRun(model)
		else
		{
			return nil
		}
		return "\(model.displayName) はおよそ \(ByteCount.humanReadable(model.requiredMemoryBytes)) を要します。"
			+ "この端末で使える見込みは \(ByteCount.humanReadable(memoryBudgetBytes)) "
			+ "（搭載 \(ByteCount.humanReadable(physicalMemoryBytes))）なので、"
			+ "生成の途中で強制終了する可能性があります。"
	}

	/// 実行中の端末のプロファイル。ProcessInfo に触れるのはここだけで、
	/// 判断そのもの（係数・比較）は上の純ロジックが持つ。
	public static func current() -> DeviceProfile
	{
		#if os(iOS)
			let platform = Platform.iOS
		#else
			let platform = Platform.macOS
		#endif
		return DeviceProfile(
			physicalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
			platform: platform)
	}
}
