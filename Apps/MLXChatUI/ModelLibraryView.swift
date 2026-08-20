//
//  ModelLibraryView.swift
//
//  モデルの選択と、ダウンロード済みモデルの管理。
//
//  「この端末で動くか」は DeviceProfile（Core）が判断し、この画面はそれを
//  映すだけ。動かない見込みのモデルも選べるようにしてあるのは、見積もりが
//  概算で、実機のほうが強いことがあるため（警告は出す）。
//

import SwiftUI

struct ModelLibraryView: View
{
	@EnvironmentObject private var model: ChatViewModel

	var body: some View
	{
		List
		{
			Section("モデルを選ぶ")
			{
				ForEach(ModelCatalog.all)
				{ entry in
					row(for: entry)
				}
			}

			Section
			{
				if model.downloadedModels.isEmpty
				{
					Text("まだありません。最初の送信でダウンロードされます。")
						.foregroundStyle(.secondary)
				}
				ForEach(model.downloadedModels)
				{ downloaded in
					HStack
					{
						VStack(alignment: .leading)
						{
							Text(downloaded.displayName)
							Text(downloaded.id)
								.font(.caption2)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Text(ByteCount.humanReadable(downloaded.sizeBytes))
							.foregroundStyle(.secondary)
						Button(role: .destructive)
						{
							model.deleteDownloadedModel(downloaded)
						} label: {
							Label("削除", systemImage: "trash")
								.labelStyle(.iconOnly)
						}
						.buttonStyle(.borderless)
					}
				}
			} header: {
				Text("ダウンロード済み（合計 \(ByteCount.humanReadable(model.totalDownloadedBytes))）")
			} footer: {
				Text("重みはキャッシュ領域に置いてあります。容量が逼迫すると OS が"
					+ "消すことがありますが、次に使うときに再ダウンロードされます。")
			}

			Section("この端末")
			{
				LabeledContent("搭載メモリ",
					value: ByteCount.humanReadable(model.device.physicalMemoryBytes))
				LabeledContent("モデルに使える見込み",
					value: ByteCount.humanReadable(model.device.memoryBudgetBytes))
			}
		}
		.navigationTitle("モデル")
		.onAppear { model.refreshDownloadedModels() }
	}

	private func row(for entry: CatalogModel) -> some View
	{
		Button
		{
			model.conversation.modelID = entry.id
		} label: {
			HStack(alignment: .top)
			{
				VStack(alignment: .leading, spacing: 2)
				{
					HStack(spacing: 6)
					{
						Text(entry.displayName)
							.fontWeight(model.conversation.modelID == entry.id ? .semibold : .regular)
						if model.isDownloaded(entry)
						{
							Image(systemName: "arrow.down.circle.fill")
								.foregroundStyle(.secondary)
								.font(.caption)
						}
					}
					Text(entry.subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
					Text(entry.notes)
						.font(.caption2)
						.foregroundStyle(.secondary)
					if !model.device.canRun(entry)
					{
						Label("この端末には大きい可能性があります", systemImage: "exclamationmark.triangle")
							.font(.caption2)
							.foregroundStyle(.orange)
					}
				}
				Spacer()
				if model.conversation.modelID == entry.id
				{
					Image(systemName: "checkmark")
						.foregroundStyle(Color.accentColor)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
