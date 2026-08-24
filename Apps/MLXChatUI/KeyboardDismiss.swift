//
//  KeyboardDismiss.swift
//
//  iOS でキーボードを畳む手段を足す修飾子。
//
//  なぜ要るか（実機で詰まった）
//  ----------------------------
//  iOS はキーボードが出ている間、TabView の下タブを隠す。文字入力のある画面で
//  畳む手段を用意しないと、**一度キーボードを出したら他の画面へ移れなくなる**。
//  「入力欄があるのに送信するまで抜けられない」という行き止まりで、これは
//  機能の欠落ではなく操作不能なので、必ず塞ぐ。
//
//  手段は 2 つ重ねてある。
//    * キーボード上の「閉じる」ボタン … 明示的で、探さなくても目に入る
//    * フォームを指で引き下げる        … 読もうとする動きがそのまま
//                                        「どかす」操作になる
//  ボタンだけだと画面が狭くなり、引き下げだけだと気づけないので両方置く。
//
//  **画面の下端にボタンを固定している画面には使わないこと。** キーボード上の
//  ツールバーはキーボードの上端に貼り付くので、固定したボタンと重なる。実際、
//  チャット画面ではこれが送信ボタンとちょうど重なり「畳まないと送信できない」
//  という本末転倒になった。そちらは畳むボタンを入力欄の並びに置いてある
//  （ChatView.composer を参照）。この修飾子が向くのは、下端に固定物が無い
//  フォーム系の画面（設定・ベンチマーク）。
//
//  入力欄ごとの @FocusState には触れない（修飾子は誰がフォーカスを持っているか
//  を知らない）。UIKit のレスポンダチェーンへ resignFirstResponder を投げる形に
//  してあるので、どの入力欄が対象でも同じように閉じられる。
//
//  macOS では何もしない。キーボードは常に出ているわけではなく、隠れる UI も
//  無いため。
//

import SwiftUI

#if os(iOS)
	import UIKit
#endif

extension View
{
	/// iOS でキーボードを畳めるようにする（macOS では何もしない）。
	///
	/// 文字入力のある画面には**必ず付ける**こと。付け忘れると、その画面は
	/// キーボードを出した時点でタブを移動できなくなる。
	func dismissibleKeyboard() -> some View
	{
		modifier(DismissibleKeyboard())
	}
}

struct DismissibleKeyboard: ViewModifier
{
	func body(content: Content) -> some View
	{
		#if os(iOS)
			content
				.scrollDismissesKeyboard(.interactively)
				.toolbar
				{
					ToolbarItemGroup(placement: .keyboard)
					{
						Spacer()
						Button("閉じる", systemImage: "keyboard.chevron.compact.down")
						{
							DismissibleKeyboard.dismiss()
						}
					}
				}
		#else
			content
		#endif
	}

	#if os(iOS)
		/// いま第一応答者になっている入力欄を降ろす。
		static func dismiss()
		{
			UIApplication.shared.sendAction(
				#selector(UIResponder.resignFirstResponder),
				to: nil, from: nil, for: nil)
		}
	#endif
}
