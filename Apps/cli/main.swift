//
//  main.swift
//
//  mlxchat-cli — macOS 版に同梱するコマンドラインフロントエンド。
//
//  ここは**整形だけ**を行う。引数の解釈は APICommand、検査は各 Request、生成は
//  MLXChatEngine、集計は BenchmarkSummary が持つ。GUI と同じ部品を同じ順に
//  呼ぶので、CLI にしか無い挙動・GUI にしか無い挙動が生まれない。
//
//  使い方:
//    mlxchat-cli "こんにちは"                       … 既定モデルで 1 往復
//    mlxchat-cli chat --model <id> --prompt <text>
//    echo "要約して" | mlxchat-cli chat --model <id>  … プロンプトは標準入力からも
//    mlxchat-cli bench --model <id> --runs 5
//    mlxchat-cli models
//

import Foundation

// 出力の使い分け: 生成された本文だけを標準出力へ、進捗・実測値・エラーは
// 標準エラーへ出す。こうしておくと `mlxchat-cli "..." > answer.txt` が
// そのまま使える（パイプで次の道具へ渡せる）。
func note(_ text: String)
{
	FileHandle.standardError.write(Data((text + "\n").utf8))
}

func emit(_ text: String)
{
	FileHandle.standardOutput.write(Data(text.utf8))
}

// 使い方の文言は関数にしてある。async な main.swift のトップレベル変数は
// 暗黙に MainActor 隔離になり、nonisolated な関数から読めないため
// （グローバルにせず、呼ばれたときに組み立てる）。
func usageText() -> String
{
	"""
	mlxchat-cli — MLX でローカル LLM を動かす

	  mlxchat-cli [chat] [<プロンプト>] [オプション]
	  mlxchat-cli bench [オプション]
	  mlxchat-cli models

	共通のオプション:
	  -m, --model <id>            使うモデル（models で一覧）
	  -t, --temperature <float>   温度（0〜2）
	      --top-p <float>         top-p（0〜1）
	      --max-tokens <int>      生成トークン数の上限
	      --repetition-penalty <float>
	      --kv-bits <4|8>         KV キャッシュ量子化
	      --history <int>         モデルへ渡す発言数の上限

	chat のオプション:
	  -p, --prompt <text>         プロンプト（省略時は標準入力から読む）
	  -s, --system <text>         システム指示
	  -o, --output <file>         応答をファイルへも書き出す

	bench のオプション:
	  -n, --runs <int>            実行回数（既定 3）
	      --warmup <int>          捨てる先頭の回数（既定 1）
	"""
}

/// 引数を解釈する。誤りは使い方を出して終了（＝呼び出し側は成功だけを扱えばよい）。
func parseCommand(_ arguments: [String]) -> APICommand
{
	do
	{
		return try APICommand.parse(arguments: arguments)
	}
	catch
	{
		note("error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
		note("")
		note(usageText())
		exit(2)
	}
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help")
{
	print(usageText())
	exit(0)
}

let command = parseCommand(arguments)

let device = DeviceProfile.current()
MLXChatEngine.applyMemoryLimits(device)

switch command
{
	case .models:
		// 一覧は「この端末で動くか」まで含めて出す。動かないモデルを勧めない
		// ための判断は DeviceProfile が持っていて、GUI と同じ規則。
		note("この端末: 搭載 \(ByteCount.humanReadable(device.physicalMemoryBytes))"
			+ " / モデルに使える見込み \(ByteCount.humanReadable(device.memoryBudgetBytes))")
		let storage = try? ModelStorage(base: ModelStorage.defaultBase())
		for entry in ModelCatalog.all
		{
			let marks = [
				storage?.isDownloaded(entry.id) == true ? "済" : "  ",
				device.canRun(entry) ? "  " : "大",
			].joined()
			print("\(marks) \(entry.id)")
			print("      \(entry.displayName) — \(entry.subtitle) / ctx \(entry.contextWindow)")
		}
		print("")
		print("凡例: 「済」= ダウンロード済み、「大」= この端末には大きい可能性あり")
		exit(0)

	case .chat(var request):
		// プロンプト未指定なら標準入力から読む（パイプで流し込む使い方）。
		if request.prompt.isEmpty
		{
			let data = FileHandle.standardInput.readDataToEndOfFile()
			request.prompt = String(decoding: data, as: UTF8.self)
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		do
		{
			try request.validate()
		}
		catch
		{
			note("error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
			exit(2)
		}

		var answer = ""
		var failed = false
		for await event in MLXChatEngine.shared.events(for: request)
		{
			switch event
			{
				case .phase(let phase):
					if phase != .finished
					{
						note(phase.description)
					}
				case .downloadProgress(let fraction):
					// 端末に出しっぱなしにならないよう 10% 刻みだけ出す。
					let percent = Int(fraction * 100)
					if percent % 10 == 0, percent > 0
					{
						note("  \(percent)%")
					}
				case .modelReady(let seconds):
					note(String(format: "モデル読み込み: %.1fs", seconds))
				case .token(let text):
					answer += text
					emit(text)
				case .finished(let stats):
					emit("\n")
					note(stats.summaryLine)
				case .failed(let message):
					note("error: \(message)")
					failed = true
			}
		}
		if let outputFile = request.outputFile, !answer.isEmpty
		{
			try? answer.write(to: outputFile, atomically: true, encoding: .utf8)
		}
		exit(failed ? 1 : 0)

	case .bench(let request):
		do
		{
			try request.validate()
		}
		catch
		{
			note("error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
			exit(2)
		}
		var failed = false
		for await event in BenchmarkRunner(engine: .shared).events(for: request)
		{
			switch event
			{
				case .runStarted(let index, let total, let isWarmup):
					note("[\(index + 1)/\(total)] \(isWarmup ? "ウォームアップ" : "計測")")
				case .runFinished(let stats, _):
					note("  " + stats.summaryLine)
				case .completed(let summary):
					print(summary.report())
				case .failed(let message):
					note("error: \(message)")
					failed = true
				case .generation:
					break
			}
		}
		exit(failed ? 1 : 0)
}
