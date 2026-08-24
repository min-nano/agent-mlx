//
//  ChatViewModel.swift
//
//  画面と Core / エンジンの間をつなぐ薄い層。**判断を持たないこと**が守るべき
//  規則で、ここにあってよいのは
//    * @Published なプロパティ（＝画面の状態）
//    * エンジンのイベントを受けてその状態を書き換えること
//    * Core の純ロジックを呼ぶこと
//  だけ。判断（履歴の切り詰め・パラメータの範囲・端末で動くか・エラーの文言）が
//  ここに生えてきたら、それは Core へ下ろすサイン。
//
//  そう決めているのは、GUI にしか無い機能を作らないため。CLI と URL スキームは
//  同じ Core を通るので、Core に判断がある限り 3 つの入口の挙動は必ず一致する。
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject
{
	// -----------------------------------------------------------------
	// 画面の状態
	// -----------------------------------------------------------------

	@Published var conversation: Conversation
	/// 保存済みの会話（新しい順）。
	@Published private(set) var conversations: [Conversation] = []
	@Published var parameters = GenerationParameters()
	/// 入力欄。
	@Published var input = ""
	/// いまの段階（生成していないときは nil）。
	@Published private(set) var phase: GenerationPhase?
	/// ダウンロードの進捗（0 ... 1）。
	@Published private(set) var downloadProgress: Double = 0
	/// 失敗の説明（ErrorDetails が組み立てたもの）。
	@Published var errorMessage: String?
	/// 端末の見立て。使えるモデルの一覧と警告はここから作る。
	@Published private(set) var device = DeviceProfile.current()
	/// ダウンロード済みモデル（設定画面の一覧）。
	@Published private(set) var downloadedModels: [DownloadedModel] = []
	/// 思考（<think>）を開いている発言。判断（既定は畳む・自動では開閉しない）は
	/// Core の ReasoningDisclosure が持ち、ここは覚えておく場所を用意するだけ。
	///
	/// 行（MessageRow）の @State にしないのは、LazyVStack が画面外の行の状態を
	/// 捨てることがあるため。捨てられると開いていた思考が勝手に畳まれ、履歴の
	/// 高さが一度に縮んでスクロール位置が内容より下へ飛ぶ（実機で踏んだ）。
	@Published var reasoningDisclosure = ReasoningDisclosure()

	var isGenerating: Bool { phase != nil }

	/// 選択中のモデルがこの端末で厳しいときの警告（無ければ nil）。
	var modelWarning: String?
	{
		guard let model = ModelCatalog.model(id: conversation.modelID)
		else
		{
			return nil
		}
		return device.warning(for: model)
	}

	/// いまの設定を CLI で再現するコマンド。設定を人に伝えるとき・不具合を
	/// 報告するときに、画面の状態を 1 行で写せるようにしてある。
	var equivalentCommand: String
	{
		let request = ChatRequest.next(
			in: conversation,
			prompt: input.isEmpty ? "…" : input,
			parameters: parameters)
		return (["mlxchat-cli"] + APICommand.arguments(for: request))
			.map { $0.contains(" ") ? "\"\($0)\"" : $0 }
			.joined(separator: " ")
	}

	// -----------------------------------------------------------------
	// 依存
	// -----------------------------------------------------------------

	private let engine: MLXChatEngine
	private let store: ConversationStore?
	private let storage: ModelStorage?
	private var generationTask: Task<Void, Never>?
	/// 届いたトークンを本文と思考へ振り分ける（生成ごとに作り直す）。
	/// 判断そのものは Core の ReasoningSplitter が持ち、ここは回すだけ。
	private var splitter = ReasoningSplitter()

	init()
	{
		let storage = try? ModelStorage(base: ModelStorage.defaultBase())
		self.storage = storage
		self.store = (try? ConversationStore.defaultDirectory()).map { ConversationStore(directory: $0) }
		self.engine = MLXChatEngine.shared

		let device = DeviceProfile.current()
		self.device = device
		self.conversation = Conversation(modelID: device.recommendedModel.id)

		MLXChatEngine.applyMemoryLimits(device)
		reloadConversations()
		refreshDownloadedModels()
	}

	// -----------------------------------------------------------------
	// 会話
	// -----------------------------------------------------------------

	func reloadConversations()
	{
		conversations = (try? store?.load()) ?? []
	}

	func newConversation()
	{
		stop()
		reasoningDisclosure.reset()
		conversation = Conversation(
			systemPrompt: conversation.systemPrompt,
			modelID: conversation.modelID)
	}

	func open(_ conversation: Conversation)
	{
		stop()
		reasoningDisclosure.reset()
		self.conversation = conversation
	}

	func delete(_ conversation: Conversation)
	{
		try? store?.delete(id: conversation.id)
		reloadConversations()
	}

	private func persist()
	{
		try? store?.save(conversation)
		reloadConversations()
	}

	// -----------------------------------------------------------------
	// 生成
	// -----------------------------------------------------------------

	/// 入力欄の内容を送る。
	func send()
	{
		let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !prompt.isEmpty, !isGenerating
		else
		{
			return
		}
		input = ""
		start(prompt: prompt)
	}

	/// プロンプトを 1 つ実行する（URL スキームからも呼ばれる）。
	func start(prompt: String)
	{
		errorMessage = nil
		let request = ChatRequest.next(
			in: conversation, prompt: prompt, parameters: parameters)
		do
		{
			try request.validate()
		}
		catch
		{
			errorMessage = ErrorDetails.message(for: error, modelID: request.modelID)
			return
		}

		conversation.append(ChatMessage(role: .user, text: prompt))
		// 空の assistant 発言を先に置き、届いたトークンをここへ継ぎ足す。
		// 画面には「答えの枠」が即座に出るので、モデル読み込みの数十秒でも
		// 「反応していない」ようには見えない。
		let answerID = UUID()
		conversation.append(ChatMessage(
			id: answerID, role: .assistant, text: "", modelID: request.modelID))
		phase = .downloading
		downloadProgress = 0
		splitter = ReasoningSplitter()

		let engine = self.engine
		generationTask = Task
		{ [weak self] in
			for await event in engine.events(for: request)
			{
				// エンジンのイベントはスレッドを跨ぐので、受け側で MainActor へ
				// 持ち上げる（@MainActor のメソッドを await で呼ぶ形にしてある）。
				await self?.apply(event, to: answerID)
			}
			await self?.finishGeneration()
		}
	}

	func stop()
	{
		generationTask?.cancel()
		generationTask = nil
		phase = nil
	}

	private func apply(_ event: GenerationEvent, to answerID: UUID)
	{
		switch event
		{
			case .phase(let phase):
				self.phase = phase == .finished ? nil : phase
			case .downloadProgress(let fraction):
				downloadProgress = fraction
			case .modelReady:
				refreshDownloadedModels()
			case .token(let text):
				append(splitter.consume(text), to: answerID)
			case .finished(let stats):
				// 保留されていた末尾（タグの途中に見えた文字列）を先に吐き出す。
				append(splitter.flush(), to: answerID)
				if let index = conversation.messages.firstIndex(where: { $0.id == answerID })
				{
					conversation.messages[index].stats = stats
				}
				phase = nil
				persist()
			case .failed(let message):
				append(splitter.flush(), to: answerID)
				errorMessage = message
				// 中身の無い応答が会話に残ると、次の生成でモデルへ空の
				// assistant 発言を渡すことになる。失敗したときは取り除く。
				conversation.messages.removeAll { $0.id == answerID && $0.text.isEmpty }
				phase = nil
		}
	}

	/// 切り分け済みの断片を、生成中の発言へ継ぎ足す。
	private func append(_ chunk: ReasoningText, to answerID: UUID)
	{
		guard !chunk.answer.isEmpty || !chunk.reasoning.isEmpty,
			let index = conversation.messages.firstIndex(where: { $0.id == answerID })
		else
		{
			return
		}
		conversation.messages[index].text += chunk.answer
		if !chunk.reasoning.isEmpty
		{
			conversation.messages[index].reasoning =
				(conversation.messages[index].reasoning ?? "") + chunk.reasoning
		}
	}

	private func finishGeneration()
	{
		generationTask = nil
		phase = nil
	}

	// -----------------------------------------------------------------
	// モデル
	// -----------------------------------------------------------------

	func refreshDownloadedModels()
	{
		downloadedModels = storage?.downloadedModels() ?? []
	}

	func isDownloaded(_ model: CatalogModel) -> Bool
	{
		downloadedModels.contains { $0.id == model.id }
	}

	func deleteDownloadedModel(_ model: DownloadedModel)
	{
		try? storage?.delete(model.id)
		refreshDownloadedModels()
	}

	var totalDownloadedBytes: Int64
	{
		downloadedModels.reduce(0) { $0 + $1.sizeBytes }
	}

	// -----------------------------------------------------------------
	// 外部アプリ連携（URL スキーム）
	// -----------------------------------------------------------------

	/// mlxchat:// を受けて実行する。解釈は APICommand（Core）が行い、ここは
	/// 結果を画面の状態へ移すだけ。
	func handle(url: URL)
	{
		do
		{
			switch try APICommand.parse(url: url)
			{
				case .chat(let request):
					conversation.modelID = request.modelID
					if !request.systemPrompt.isEmpty
					{
						conversation.systemPrompt = request.systemPrompt
					}
					parameters = request.parameters
					start(prompt: request.prompt)
				case .bench, .models:
					// ベンチマークとモデル一覧は画面が別なので、ここでは
					// 起動だけして利用者に切り替えてもらう（URL から画面を
					// 勝手に切り替えると、生成中の会話を壊しうる）。
					errorMessage = "この URL はベンチマーク画面から実行してください。"
			}
		}
		catch
		{
			errorMessage = ErrorDetails.message(for: error)
		}
	}
}
