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
			// 生成中は届いたトークンを追って一番下へ寄せ続ける。ここを
			// 「本文の長さ」ではなく最後の発言 id で見ているのは、長い応答で
			// 毎トークン再計算するのを避けるため。
			.onChange(of: model.conversation.messages.last?.text)
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
				.onSubmit { model.send() }
			Button
			{
				model.send()
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
	}
}
