//
//  MLXChatEngine.swift
//
//  MLX（mlx-swift-lm）の**唯一のラッパー**。MLXLLM / MLXLMCommon / MLX の型が
//  出てくるのはこのファイルだけで、外へは MLXChatCore の値型（ChatRequest /
//  GenerationEvent / GenerationStats）しか漏らさない。
//
//  なぜこの線引きか（CLAUDE.md「アーキテクチャ」参照）:
//    * MLX の API は活発に変わる。変更の影響をこの 1 ファイルに閉じ込める。
//    * MLX を import した瞬間、そのターゲットは Apple Silicon + Metal でしか
//      ビルド・実行できなくなる。判断（履歴の切り詰め・パラメータの検査・
//      速度の集計）を Core 側の純ロジックに置いておけば、CI で秒単位でテストできる。
//
//  このファイルにはテストを書かない（GPU が要るため）。だから**ここに判断を
//  置かないこと**。ここにあってよいのは「MLX の型への写し替え」と「MLX の呼び出し」だけ。
//

import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon

/// モデルの読み込みと生成。読み込んだモデルはプロセス内に 1 つだけ保持する
/// （数 GB あるので、切り替えるときは必ず前のものを捨てる）。
actor MLXChatEngine
{
	/// 直近に読み込んだモデル。同じモデルへの連続した生成は読み込みを飛ばす。
	private var loadedModelID: String?
	private var container: ModelContainer?
	/// 重みの置き場所。ModelStorage と同じ base を使う（＝画面の「ダウンロード
	/// 済みモデル」と実体が必ず一致する）。
	private let hub: HubApi

	/// プロセスに 1 つだけ持つエンジン。
	///
	/// チャット画面とベンチマーク画面が別々にエンジンを持つと、同じモデルを
	/// 二重に読み込むことになる（数 GB × 2）。共有するのは節約ではなく必須。
	static let shared = MLXChatEngine(downloadBase: try? ModelStorage.defaultBase())

	init(downloadBase: URL? = nil)
	{
		if let downloadBase
		{
			self.hub = HubApi(downloadBase: downloadBase)
		}
		else
		{
			self.hub = HubApi(
				downloadBase: FileManager.default.urls(
					for: .cachesDirectory, in: .userDomainMask).first)
		}
	}

	// -----------------------------------------------------------------
	// メモリの上限
	// -----------------------------------------------------------------

	/// MLX のキャッシュ上限を端末に合わせる。
	///
	/// MLX は解放した GPU バッファを再利用のためキャッシュに残す。Mac では
	/// 速度に効く良い挙動だが、iOS では「使っていないのに OS からは使用中に
	/// 見えるメモリ」になり、jetsam を早める。予算の一部に抑えておく。
	/// 判断（予算）は DeviceProfile が持ち、ここは適用するだけ。
	static func applyMemoryLimits(_ profile: DeviceProfile)
	{
		// キャッシュは予算の 1/4 まで。残りは重みと KV キャッシュのために空けておく。
		MLX.GPU.set(cacheLimit: Int(profile.memoryBudgetBytes / 4))
	}

	/// いま GPU が確保しているメモリ（バイト）。画面の表示用。
	static var activeMemoryBytes: Int64
	{
		Int64(MLX.GPU.activeMemory)
	}

	// -----------------------------------------------------------------
	// モデルの読み込み
	// -----------------------------------------------------------------

	/// モデルを読み込む（必要ならダウンロードする）。
	///
	/// - Parameter onEvent: 進捗の報告先。ダウンロードは数 GB になり得るので、
	///   割合を必ず流す（無言で数分待たせない）。
	private func modelContainer(
		for modelID: String,
		onEvent: @escaping @Sendable (GenerationEvent) -> Void) async throws -> ModelContainer
	{
		if let container, loadedModelID == modelID
		{
			return container
		}
		// 別のモデルへ切り替えるときは、先に捨ててから読む。両方を同時に
		// 抱えると、その瞬間だけメモリが 2 倍要って落ちる。
		self.container = nil
		self.loadedModelID = nil
		MLX.GPU.clearCache()

		onEvent(.phase(.downloading))
		let started = Date()
		let loaded = try await loadModelContainer(hub: hub, id: modelID)
		{ progress in
			onEvent(.downloadProgress(progress.fractionCompleted))
		}
		onEvent(.phase(.loading))
		self.container = loaded
		self.loadedModelID = modelID
		onEvent(.modelReady(seconds: Date().timeIntervalSince(started)))
		return loaded
	}

	/// 読み込み済みのモデルを捨てる（メモリを返す）。
	func unload()
	{
		container = nil
		loadedModelID = nil
		MLX.GPU.clearCache()
	}

	// -----------------------------------------------------------------
	// 生成
	// -----------------------------------------------------------------

	/// 1 往復ぶんの生成を実行し、出来事を順に流す。
	///
	/// 呼び出し側はストリームを捨てるだけで中断できる（AsyncStream の
	/// onTermination がタスクを cancel し、MLX 側の生成ループもそれで止まる）。
	nonisolated func events(for request: ChatRequest) -> AsyncStream<GenerationEvent>
	{
		// 失敗もイベント（.failed）として流すので、ストリーム自体は throw しない。
		// こうしておくと呼び出し側（GUI / CLI）は for await 1 本で全部を受けられる。
		let (stream, continuation) = AsyncStream<GenerationEvent>.makeStream()
		let task = Task
		{
			let emit: @Sendable (GenerationEvent) -> Void = { continuation.yield($0) }
			do
			{
				let stats = try await self.run(request, onEvent: emit)
				emit(.finished(stats))
			}
			catch is CancellationError
			{
				emit(.failed(ErrorDetails.advice(for: .cancelled, modelID: request.modelID)))
			}
			catch
			{
				emit(.failed(ErrorDetails.message(for: error, modelID: request.modelID)))
			}
			continuation.finish()
		}
		continuation.onTermination =
		{ _ in
			task.cancel()
		}
		return stream
	}

	private func run(
		_ request: ChatRequest,
		onEvent: @escaping @Sendable (GenerationEvent) -> Void) async throws -> GenerationStats
	{
		let model = try await modelContainer(for: request.modelID, onEvent: onEvent)

		// ピークは「この生成で」どれだけ要ったかを見たいので、毎回リセットする。
		MLX.GPU.resetPeakMemory()

		let session = ChatSession(
			model,
			instructions: request.systemPrompt.isEmpty ? nil : request.systemPrompt,
			history: request.history.map(MLXChatEngine.message(from:)),
			generateParameters: MLXChatEngine.parameters(from: request.parameters))

		onEvent(.phase(.prefill))
		let started = Date()
		var timeToFirstToken: Double?
		var info: GenerateCompletionInfo?

		for try await generation in session.streamDetails(to: request.prompt, images: [], videos: [])
		{
			// 中断は例外ではなく「途中で止まる」形でも来る。ここで見ておかないと
			// 停止ボタンの直後に無駄な 1 トークンぶんの計算が走る。
			try Task.checkCancellation()
			switch generation
			{
				case .chunk(let text):
					if timeToFirstToken == nil
					{
						timeToFirstToken = Date().timeIntervalSince(started)
						onEvent(.phase(.generating))
					}
					onEvent(.token(text))
				case .info(let completion):
					info = completion
				case .toolCall:
					// このアプリはツール呼び出しを使わない（モデル側が勝手に
					// 出してきたら本文には混ぜず捨てる）。
					break
			}
		}

		onEvent(.phase(.finished))
		return MLXChatEngine.stats(
			from: info,
			timeToFirstToken: timeToFirstToken,
			peakMemoryBytes: Int64(MLX.GPU.peakMemory))
	}

	// -----------------------------------------------------------------
	// 変換表（MLX の型 ⇄ Core の値型）。このアプリで MLX の型に触れてよい
	// 唯一の場所。増やすときはここへ足すこと。
	// -----------------------------------------------------------------

	static func message(from message: ChatMessage) -> Chat.Message
	{
		switch message.role
		{
			case .system:
				return .system(message.text)
			case .user:
				return .user(message.text)
			case .assistant:
				return .assistant(message.text)
		}
	}

	static func parameters(from parameters: GenerationParameters) -> GenerateParameters
	{
		GenerateParameters(
			maxTokens: parameters.maxTokens,
			kvBits: parameters.kvBits,
			// KV キャッシュの量子化は最初から効かせない。冒頭（指示文）の
			// 精度は答え全体に効くので、そこだけは素のまま持つ。
			quantizedKVStart: parameters.kvBits == nil ? 0 : 512,
			temperature: parameters.temperature,
			topP: parameters.topP,
			repetitionPenalty: parameters.repetitionPenalty)
	}

	static func stats(
		from info: GenerateCompletionInfo?,
		timeToFirstToken: Double?,
		peakMemoryBytes: Int64) -> GenerationStats
	{
		guard let info
		else
		{
			// info が来ないのは中断されたときだけ。数字は無いが、止めたことは
			// 記録に残す（会話ログで「途中で止めた応答」だと分かるように）。
			return GenerationStats(
				timeToFirstTokenSeconds: timeToFirstToken,
				peakMemoryBytes: peakMemoryBytes,
				stopReason: .cancelled)
		}
		return GenerationStats(
			promptTokens: info.promptTokenCount,
			generatedTokens: info.generationTokenCount,
			promptSeconds: info.promptTime,
			generateSeconds: info.generateTime,
			timeToFirstTokenSeconds: timeToFirstToken,
			peakMemoryBytes: peakMemoryBytes,
			stopReason: stopReason(from: info.stopReason))
	}

	static func stopReason(from reason: GenerateStopReason) -> GenerationStats.StopReason
	{
		switch reason
		{
			case .stop:
				return .stop
			case .length:
				return .length
			case .cancelled:
				return .cancelled
		}
	}
}
