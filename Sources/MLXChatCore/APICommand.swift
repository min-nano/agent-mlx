//
//  APICommand.swift
//
//  外部連携 API の唯一の定義。GUI アプリの URL スキーム（mlxchat://）と CLI の
//  引数列を、同じ規則でリクエストへ変換する純ロジック。
//
//  連携の入口は 3 つあるが、パラメータの名前と意味はここで 1 回だけ定義する
//  （入口ごとに解釈を散らさない）:
//
//    1. Swift ライブラリ  ChatRequest / BenchmarkRequest を直接組み立てる
//    2. CLI              mlxchat-cli chat  --model <id> --prompt <text> [...]
//                        mlxchat-cli bench --model <id> [--runs 3] [...]
//                        mlxchat-cli models
//    3. URL スキーム      mlxchat://chat?model=<id>&prompt=<text>[&temperature=…]
//                        mlxchat://bench?model=<id>&runs=3
//
//  CLI はサブコマンド名が無ければ chat として解釈する（`mlxchat-cli "こんにちは"` が
//  そのまま通る）。
//
//  ここはファイルシステムにもネットワークにも触れないし、モデルも読み込まない。
//  したがって単体テストは文字列だけで書ける。
//

import Foundation

/// 外部から受け取った 1 つの指示。
public enum APICommand: Equatable, Sendable
{
	/// 1 往復ぶんの生成。
	case chat(ChatRequest)
	/// 同じプロンプトを繰り返して速度を測る。
	case bench(BenchmarkRequest)
	/// 使えるモデルの一覧を出す（生成しない）。
	case models

	/// GUI アプリが Info.plist（CFBundleURLTypes）で宣言する URL スキーム。
	/// iOS / macOS で同じ文字列を使う。
	public static let urlScheme = "mlxchat"
	/// mlxchat://chat?... のホスト部 / CLI のサブコマンド名。
	public static let chatCommand = "chat"
	/// mlxchat://bench?... のホスト部 / CLI のサブコマンド名。
	public static let benchCommand = "bench"
	/// CLI のサブコマンド名（URL からは呼べない — 出力するものが無いため）。
	public static let modelsCommand = "models"

	/// CLI が受け付けるサブコマンド名。
	public static let commandNames = [chatCommand, benchCommand, modelsCommand]

	// -----------------------------------------------------------------
	// URL スキーム
	//   mlxchat://chat?prompt=<テキスト>[&model=<id>][&system=<テキスト>]
	//                 [&temperature=0.7][&topP=0.95][&maxTokens=512]
	//                 [&repetitionPenalty=1.1][&kvBits=8][&history=20]
	//   mlxchat://bench?[model=<id>][&prompt=<テキスト>][&runs=3][&warmup=1]
	//                  [&maxTokens=256][&temperature=0]
	// 値はパーセントエンコードしておくこと。
	// -----------------------------------------------------------------
	public static func parse(url: URL) throws -> APICommand
	{
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			components.scheme == urlScheme
		else
		{
			throw APICommandError.unsupportedCommand(url.absoluteString)
		}
		let command = components.host ?? ""
		// コマンド名を先に確かめる。パラメータの不足より「そもそも知らない
		// コマンド」のほうが呼び出し側にとって有用な情報なので順序を保つ。
		guard command == chatCommand || command == benchCommand
		else
		{
			throw APICommandError.unsupportedCommand(command)
		}

		var parameters: [String: String] = [:]
		for item in components.queryItems ?? []
		{
			parameters[item.name] = item.value ?? ""
		}

		switch command
		{
			case chatCommand:
				guard let prompt = parameters["prompt"], !prompt.isEmpty
				else
				{
					throw APICommandError.missingParameter("prompt")
				}
				var request = ChatRequest(prompt: prompt)
				if let model = parameters["model"], !model.isEmpty
				{
					request.modelID = model
				}
				if let system = parameters["system"]
				{
					request.systemPrompt = system
				}
				request.parameters = try generationParameters(
					from: parameters, base: request.parameters)
				return .chat(request)

			default:
				var request = BenchmarkRequest()
				if let model = parameters["model"], !model.isEmpty
				{
					request.modelID = model
				}
				if let prompt = parameters["prompt"], !prompt.isEmpty
				{
					request.prompt = prompt
				}
				if let raw = parameters["runs"]
				{
					request.runs = try intValue(raw, parameter: "runs")
				}
				if let raw = parameters["warmup"]
				{
					request.warmupRuns = try intValue(raw, parameter: "warmup")
				}
				request.parameters = try generationParameters(
					from: parameters, base: request.parameters)
				return .bench(request)
		}
	}

	// -----------------------------------------------------------------
	// CLI 引数
	//   [chat] [<プロンプト>] [--model id] [--system text] [--temperature t]
	//          [--top-p p] [--max-tokens n] [--repetition-penalty r]
	//          [--kv-bits n] [--history n] [--output file]
	//   bench  [--model id] [--prompt text] [--runs n] [--warmup n] [...]
	//   models
	//
	// プロンプトは位置引数でも --prompt でも渡せる。どちらも無ければ空のままで、
	// CLI 側が標準入力から読む（パイプで流し込む使い方のため）。
	// -----------------------------------------------------------------
	public static func parse(arguments: [String]) throws -> APICommand
	{
		guard let first = arguments.first, commandNames.contains(first)
		else
		{
			return .chat(try parseChat(arguments: arguments))
		}
		let rest = Array(arguments.dropFirst())
		switch first
		{
			case benchCommand:
				return .bench(try parseBench(arguments: rest))
			case modelsCommand:
				guard rest.isEmpty
				else
				{
					throw APICommandError.unknownOption(rest[0])
				}
				return .models
			default:
				return .chat(try parseChat(arguments: rest))
		}
	}

	static func parseChat(arguments: [String]) throws -> ChatRequest
	{
		var request = ChatRequest()
		var positionals: [String] = []
		var index = 0
		while index < arguments.count
		{
			let argument = arguments[index]
			switch argument
			{
				case "--model", "-m":
					request.modelID = try optionValue(arguments, at: index, name: argument)
					index += 2
				case "--prompt", "-p":
					request.prompt = try optionValue(arguments, at: index, name: argument)
					index += 2
				case "--system", "-s":
					request.systemPrompt = try optionValue(arguments, at: index, name: argument)
					index += 2
				case "--output", "-o":
					request.outputFile = URL(
						fileURLWithPath: try optionValue(arguments, at: index, name: argument))
					index += 2
				default:
					if let consumed = try applyGenerationOption(
						arguments, at: index, into: &request.parameters)
					{
						index += consumed
					}
					else if argument.hasPrefix("-")
					{
						throw APICommandError.unknownOption(argument)
					}
					else
					{
						positionals.append(argument)
						index += 1
					}
			}
		}
		// 位置引数はプロンプト 1 つだけ。--prompt と両方あるとどちらが本物か
		// 分からないので、その場合は位置引数を優先せず誤りとして扱う。
		guard positionals.count <= 1
		else
		{
			throw APICommandError.tooManyArguments
		}
		if let positional = positionals.first
		{
			guard request.prompt.isEmpty
			else
			{
				throw APICommandError.duplicatePrompt
			}
			request.prompt = positional
		}
		return request
	}

	static func parseBench(arguments: [String]) throws -> BenchmarkRequest
	{
		var request = BenchmarkRequest()
		var index = 0
		while index < arguments.count
		{
			let argument = arguments[index]
			switch argument
			{
				case "--model", "-m":
					request.modelID = try optionValue(arguments, at: index, name: argument)
					index += 2
				case "--prompt", "-p":
					request.prompt = try optionValue(arguments, at: index, name: argument)
					index += 2
				case "--runs", "-n":
					request.runs = try intValue(
						optionValue(arguments, at: index, name: argument), parameter: argument)
					index += 2
				case "--warmup":
					request.warmupRuns = try intValue(
						optionValue(arguments, at: index, name: argument), parameter: argument)
					index += 2
				default:
					if let consumed = try applyGenerationOption(
						arguments, at: index, into: &request.parameters)
					{
						index += consumed
					}
					else
					{
						throw APICommandError.unknownOption(argument)
					}
			}
		}
		return request
	}

	/// 生成のつまみ（chat と bench で共通のオプション）を 1 か所で解釈する。
	/// 該当したら消費した引数の数を返し、該当しなければ nil を返す。
	static func applyGenerationOption(
		_ arguments: [String], at index: Int, into parameters: inout GenerationParameters)
		throws -> Int?
	{
		let argument = arguments[index]
		switch argument
		{
			case "--temperature", "-t":
				parameters.temperature = try floatValue(
					optionValue(arguments, at: index, name: argument), parameter: argument)
				return 2
			case "--top-p":
				parameters.topP = try floatValue(
					optionValue(arguments, at: index, name: argument), parameter: argument)
				return 2
			case "--max-tokens":
				parameters.maxTokens = try intValue(
					optionValue(arguments, at: index, name: argument), parameter: argument)
				return 2
			case "--repetition-penalty":
				parameters.repetitionPenalty = try floatValue(
					optionValue(arguments, at: index, name: argument), parameter: argument)
				return 2
			case "--kv-bits":
				parameters.kvBits = try intValue(
					optionValue(arguments, at: index, name: argument), parameter: argument)
				return 2
			case "--history":
				parameters.historyMessageLimit = try intValue(
					optionValue(arguments, at: index, name: argument), parameter: argument)
				return 2
			default:
				return nil
		}
	}

	/// URL のクエリから生成のつまみを組み立てる（chat と bench で共通）。
	static func generationParameters(
		from query: [String: String], base: GenerationParameters) throws -> GenerationParameters
	{
		var parameters = base
		if let raw = query["temperature"]
		{
			parameters.temperature = try floatValue(raw, parameter: "temperature")
		}
		if let raw = query["topP"]
		{
			parameters.topP = try floatValue(raw, parameter: "topP")
		}
		if let raw = query["maxTokens"]
		{
			parameters.maxTokens = try intValue(raw, parameter: "maxTokens")
		}
		if let raw = query["repetitionPenalty"]
		{
			parameters.repetitionPenalty = try floatValue(raw, parameter: "repetitionPenalty")
		}
		if let raw = query["kvBits"], !raw.isEmpty
		{
			parameters.kvBits = try intValue(raw, parameter: "kvBits")
		}
		if let raw = query["history"]
		{
			parameters.historyMessageLimit = try intValue(raw, parameter: "history")
		}
		return parameters
	}

	// -----------------------------------------------------------------
	// 逆変換（Request → CLI 引数）
	//
	// GUI が「いまの設定を CLI で再現するコマンド」を見せるために使う。語彙を
	// 1 か所に保ちたいので、組み立てもここに置く（往復はテストで固定している）。
	// -----------------------------------------------------------------

	public static func arguments(for request: ChatRequest) -> [String]
	{
		var result = [chatCommand, "--model", request.modelID]
		if !request.prompt.isEmpty
		{
			result += ["--prompt", request.prompt]
		}
		if !request.systemPrompt.isEmpty
		{
			result += ["--system", request.systemPrompt]
		}
		result += generationArguments(request.parameters)
		if let outputFile = request.outputFile
		{
			result += ["--output", outputFile.path]
		}
		return result
	}

	public static func arguments(for request: BenchmarkRequest) -> [String]
	{
		var result = [
			benchCommand,
			"--model", request.modelID,
			"--prompt", request.prompt,
			"--runs", String(request.runs),
			"--warmup", String(request.warmupRuns),
		]
		result += generationArguments(request.parameters)
		return result
	}

	static func generationArguments(_ parameters: GenerationParameters) -> [String]
	{
		var result = [
			"--temperature", format(parameters.temperature),
			"--top-p", format(parameters.topP),
			"--max-tokens", String(parameters.maxTokens),
			"--history", String(parameters.historyMessageLimit),
		]
		// 既定が「無効」のつまみは、指定されたときだけ出す（出すと「自動/無効」
		// という選択そのものが失われる）。
		if let penalty = parameters.repetitionPenalty
		{
			result += ["--repetition-penalty", format(penalty)]
		}
		if let bits = parameters.kvBits
		{
			result += ["--kv-bits", String(bits)]
		}
		return result
	}

	/// 小数の書式。ロケールに依存する "0,7" を出さないよう固定書式にする
	/// （そのまま貼って実行できるコマンドでなければ意味がない）。
	static func format(_ value: Float) -> String
	{
		String(format: "%g", value)
	}

	// -----------------------------------------------------------------
	// 内部ヘルパー
	// -----------------------------------------------------------------

	private static func optionValue(_ arguments: [String], at index: Int, name: String) throws
		-> String
	{
		guard index + 1 < arguments.count
		else
		{
			throw APICommandError.missingParameter(name)
		}
		return arguments[index + 1]
	}

	private static func intValue(_ raw: String, parameter: String) throws -> Int
	{
		guard let value = Int(raw)
		else
		{
			throw APICommandError.invalidValue(parameter: parameter, value: raw)
		}
		return value
	}

	private static func floatValue(_ raw: String, parameter: String) throws -> Float
	{
		guard let value = Float(raw), value.isFinite
		else
		{
			throw APICommandError.invalidValue(parameter: parameter, value: raw)
		}
		return value
	}
}

public enum APICommandError: Error, LocalizedError, Equatable
{
	case unsupportedCommand(String)
	case missingParameter(String)
	case invalidValue(parameter: String, value: String)
	case unknownOption(String)
	case tooManyArguments
	case duplicatePrompt

	public var errorDescription: String?
	{
		switch self
		{
			case .unsupportedCommand(let what):
				return "サポートされていないコマンドです: \(what)"
			case .missingParameter(let name):
				return "パラメータ \(name) が指定されていません。"
			case .invalidValue(let parameter, let value):
				return "\(parameter) の値が不正です: \(value)"
			case .unknownOption(let option):
				return "不明なオプションです: \(option)"
			case .tooManyArguments:
				return "引数が多すぎます（プロンプトは 1 つだけ指定できます）。"
			case .duplicatePrompt:
				return "プロンプトが二重に指定されています（位置引数と --prompt のどちらか一方にしてください）。"
		}
	}
}
