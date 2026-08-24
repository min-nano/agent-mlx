//
//  ChatView.swift
//
//  チャット画面。iOS と macOS で同じものを使う（差が出るのは入れ物側 —
//  iOS は TabView、macOS は NavigationSplitView。RootView を参照）。
//

import SwiftUI

struct ChatView: View
{
	@EnvironmentObject private var model: ChatViewModel
	@FocusState private var inputFocused: Bool

	var body: some View
	{
		VStack(spacing: 0)
		{
			transcript
			Divider()
			status
			composer
		}
		.navigationTitle(model.conversation.derivedTitle)
		.toolbar
		{
			ToolbarItem
			{
				// 書き出しは Core（Transcript）が組み立てる。実測値つきの
				// Markdown なので、答えと「そのときの速度」を一緒に人へ渡せる。
				ShareLink(item: Transcript.markdown(model.conversation))
				{
					Label("書き出す", systemImage: "square.and.arrow.up")
				}
				.disabled(model.conversation.messages.isEmpty)
			}
			ToolbarItem
			{
				Button
				{
					model.newConversation()
				} label: {
					Label("新しい会話", systemImage: "square.and.pencil")
				}
				.disabled(model.isGenerating)
			}
		}
		.alert(
			"エラー",
			isPresented: Binding(
				get: { model.errorMessage != nil },
				set: { if !$0 { model.errorMessage = nil } }))
		{
			Button("OK", role: .cancel) { model.errorMessage = nil }
		} message: {
			Text(model.errorMessage ?? "")
		}
	}

	// -----------------------------------------------------------------

	private var transcript: some View
	{
		ScrollViewReader
		{ proxy in
			ScrollView
			{
				LazyVStack(alignment: .leading, spacing: 14)
				{
					if model.conversation.messages.isEmpty
					{
						emptyState
					}
					ForEach(model.conversation.messages)
					{ message in
						MessageRow(
							message: message,
							isStreaming: model.isGenerating
								&& message.id == model.conversation.messages.last?.id)
							.id(message.id)
					}
				}
				.padding()
			}
			// 答えを読もうとして履歴を指で引く動きが、そのままキーボードを
			// どかす操作になる。
			.scrollDismissesKeyboard(.interactively)
			// 生成中は届いたトークンを追って一番下へ寄せ続ける。長さの合計を
			// 見ているのは、推論モデルが**思考だけを伸ばしている間**（本文は空の
			// まま）もスクロールを追従させるため。
			.onChange(of: streamedLength)
			{
				guard let last = model.conversation.messages.last
				else
				{
					return
				}
				withAnimation(.easeOut(duration: 0.15))
				{
					proxy.scrollTo(last.id, anchor: .bottom)
				}
			}
		}
	}

	private var emptyState: some View
	{
		VStack(alignment: .leading, spacing: 8)
		{
			Text("ローカルで動く LLM です")
				.font(.headline)
			Text("最初の送信でモデル（\(currentModelName)）をダウンロードします。"
				+ "以降はオフラインでも動きます。")
				.font(.callout)
				.foregroundStyle(.secondary)
			if let warning = model.modelWarning
			{
				Label(warning, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.orange)
			}
		}
		.padding(.vertical, 24)
	}

	/// 生成中の発言の長さ（思考を含む）。スクロール追従の変化検知に使う。
	///
	/// 本文だけを見ると、推論モデルが思考を伸ばしている間（本文は空のまま）に
	/// 追従が止まってしまう。
	private var streamedLength: Int
	{
		guard let last = model.conversation.messages.last
		else
		{
			return 0
		}
		return last.text.count + (last.reasoning?.count ?? 0)
	}

	private var currentModelName: String
	{
		ModelCatalog.model(id: model.conversation.modelID)?.displayName
			?? model.conversation.modelID
	}

	// -----------------------------------------------------------------

	@ViewBuilder
	private var status: some View
	{
		if let phase = model.phase
		{
			HStack(spacing: 8)
			{
				if phase.hasDeterminateProgress
				{
					ProgressView(value: model.downloadProgress)
						.frame(maxWidth: 160)
				}
				else
				{
					ProgressView()
						.controlSize(.small)
				}
				Text(phase.description)
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button("停止", role: .destructive) { model.stop() }
					.buttonStyle(.borderless)
			}
			.padding(.horizontal)
			.padding(.vertical, 6)
		}
	}

	private var composer: some View
	{
		HStack(alignment: .bottom, spacing: 8)
		{
			TextField("メッセージ", text: $model.input, axis: .vertical)
				.lineLimit(1 ... 6)
				.textFieldStyle(.roundedBorder)
				.focused($inputFocused)
				.onSubmit
				{
					model.send()
					inputFocused = false
				}
			#if os(iOS)
				// キーボードを畳むボタンは**入力欄の並びに置く**。
				//
				// キーボード上のツールバー（ToolbarItemGroup(placement: .keyboard)）
				// でも畳めるが、あれはキーボードの上端に貼り付くので、下に固定して
				// ある送信ボタンとちょうど重なる。「畳まないと送信できない」という
				// 本末転倒になったので、この画面ではツールバーを使わない。
				// 入力欄のある他の画面（設定・ベンチマーク）は下に固定のボタンが
				// 無いのでツールバー方式のまま（KeyboardDismiss.swift）。
				if inputFocused
				{
					Button
					{
						inputFocused = false
					} label: {
						Label("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down")
							.labelStyle(.iconOnly)
							.font(.title2)
					}
					.buttonStyle(.borderless)
					.foregroundStyle(.secondary)
					.transition(.scale.combined(with: .opacity))
				}
			#endif
			Button
			{
				model.send()
				// 送ったあとは答えを読みたいので、キーボードは引っ込める。
				// iOS では畳まないと下タブが隠れたままになる。
				inputFocused = false
			} label: {
				Label("送信", systemImage: "arrow.up.circle.fill")
					.labelStyle(.iconOnly)
					.font(.title2)
			}
			.buttonStyle(.borderless)
			.disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				|| model.isGenerating)
		}
		.padding()
		.animation(.easeOut(duration: 0.15), value: inputFocused)
	}
}
