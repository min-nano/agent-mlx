// swift-tools-version:5.9
//
// MLX Chat — Apple Silicon の Mac と iPhone で MLX（Apple の機械学習フレームワーク）の
// 実力を確かめるためのローカル LLM チャットアプリ。
//
// このパッケージが持つのは **純ロジックだけ** で、MLX にも SwiftUI にも依存しない。
// MLX を叩く層（MLXChatEngine）と画面（MLXChatUI）とアプリ本体は Apps/ 以下にあり、
// Xcode プロジェクト（project.yml → XcodeGen）がビルドする。理由は 2 つ:
//
//   1. iOS の .app は SwiftPM だけでは作れない（xcodebuild が要る）。
//   2. mlx-swift は MLX の C++/Metal を丸ごとソースからビルドするため、依存に
//      入れるだけでテストが数十分になる。テスト（swift test）を「秒で終わる
//      純ロジックの検査」に保つには、MLX をこのパッケージの依存グラフから
//      外しておく必要がある。
//
// ターゲット構成（依存の向きを厳守する。CLAUDE.md「アーキテクチャ」参照）:
//
//   MLXChatCore     ロジック本体。MLX / SwiftUI / UIKit / AppKit に依存しない。
//                   会話・モデル一覧・生成パラメータ・外部連携 API の定義。
//   MLXChatUpdater  自動アップデート（macOS 用）。リリース情報の解釈（UpdateFeed）は
//                   純ロジックで、ネットワークにも GUI にも依存しない。
//
import PackageDescription

let package = Package(
	name: "MLXChat",
	defaultLocalization: "ja",
	platforms: [.macOS(.v14), .iOS(.v17)],
	products: [
		.library(name: "MLXChatCore", targets: ["MLXChatCore"]),
		.library(name: "MLXChatUpdater", targets: ["MLXChatUpdater"]),
	],
	targets: [
		.target(name: "MLXChatCore"),
		.target(name: "MLXChatUpdater"),
		.testTarget(
			name: "MLXChatCoreTests",
			dependencies: ["MLXChatCore"]
		),
		.testTarget(
			name: "MLXChatUpdaterTests",
			dependencies: ["MLXChatUpdater"]
		),
	]
)
