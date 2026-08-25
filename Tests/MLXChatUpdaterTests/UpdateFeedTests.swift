//
//  UpdateFeedTests.swift
//
//  リリース JSON → チャンネル一覧の解釈。build.yml が作るリリースの形式
//  （タグ・notes の key=value・アセット名）と**対**になっているので、
//  片方を変えるときは必ず両方＋このテストを更新すること。
//

import XCTest

@testable import MLXChatUpdater

final class UpdateFeedTests: XCTestCase
{
	private func releasesJSON(_ body: String) -> Data
	{
		Data(body.utf8)
	}

	private let feed = """
		[
		  {
		    "tag_name": "dev-claude-my-branch",
		    "name": "Dev: claude/my-branch (abc1234)",
		    "prerelease": true,
		    "target_commitish": "abc1234def",
		    "body": "channel=dev\\nbranch=claude/my-branch\\ncommit=abc1234def5678\\nbuilt=2026-08-20T00:00:00Z",
		    "assets": [
		      {"name": "MLXChat.app.zip",
		       "browser_download_url": "https://example.com/dev/MLXChat.app.zip"},
		      {"name": "MLXChat.ipa",
		       "browser_download_url": "https://example.com/dev/MLXChat.ipa"}
		    ]
		  },
		  {
		    "tag_name": "stable",
		    "name": "Stable (1234567)",
		    "prerelease": false,
		    "target_commitish": "1234567aaa",
		    "body": "channel=stable\\nbranch=main\\ncommit=1234567aaa\\nbuilt=2026-08-19T00:00:00Z",
		    "assets": [
		      {"name": "MLXChat.app.zip",
		       "browser_download_url": "https://example.com/stable/MLXChat.app.zip"},
		      {"name": "MLXChat.ipa",
		       "browser_download_url": "https://example.com/stable/MLXChat.ipa"}
		    ]
		  }
		]
		"""

	func testChannelsAreParsedAndStableComesFirst() throws
	{
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(feed))
		XCTAssertEqual(channels.map(\.branch), ["main", "claude/my-branch"])

		let stable = channels[0]
		XCTAssertEqual(stable.tag, "stable")
		XCTAssertFalse(stable.isPrerelease)
		XCTAssertEqual(stable.commit, "1234567")
		XCTAssertEqual(stable.builtAt, "2026-08-19T00:00:00Z")
		XCTAssertEqual(
			stable.appAssetURL?.absoluteString,
			"https://example.com/stable/MLXChat.app.zip")
		XCTAssertEqual(
			stable.ipaAssetURL?.absoluteString, "https://example.com/stable/MLXChat.ipa")
		XCTAssertEqual(stable.title, "Stable (1234567)")
		XCTAssertEqual(stable.displayName, "main（安定版）")

		let dev = channels[1]
		XCTAssertTrue(dev.isPrerelease)
		XCTAssertEqual(dev.commit, "abc1234")
		XCTAssertEqual(dev.displayName, "claude/my-branch（開発版）")
	}

	func testReleasesWithoutOurTagsAreIgnored() throws
	{
		let json = """
			[{"tag_name": "v1.0.0", "prerelease": false, "assets": [
			  {"name": "MLXChat.app.zip", "browser_download_url": "https://example.com/a.zip"}]}]
			"""
		XCTAssertTrue(try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json)).isEmpty)
	}

	func testReleasesWithoutAnyAppAssetAreIgnored() throws
	{
		let json = """
			[{"tag_name": "stable", "prerelease": false, "assets": [
			  {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"}]}]
			"""
		XCTAssertTrue(try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json)).isEmpty)
	}

	func testPartialAssetsAreKept() throws
	{
		// iOS だけビルドが通った、という状態でも一覧からは消さない。
		let json = """
			[{"tag_name": "stable", "prerelease": false, "assets": [
			  {"name": "MLXChat.ipa", "browser_download_url": "https://example.com/a.ipa"}]}]
			"""
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json))
		XCTAssertEqual(channels.count, 1)
		XCTAssertNil(channels[0].appAssetURL)
		XCTAssertNotNil(channels[0].ipaAssetURL)
	}

	func testBranchAndCommitFallBackWhenNotesMissing() throws
	{
		let json = """
			[{"tag_name": "dev-feature-x", "prerelease": true,
			  "target_commitish": "deadbeefcafe", "assets": [
			  {"name": "MLXChat.app.zip", "browser_download_url": "https://example.com/a.zip"}]}]
			"""
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json))
		XCTAssertEqual(channels[0].branch, "feature-x")
		XCTAssertEqual(channels[0].commit, "deadbee")
		XCTAssertNil(channels[0].builtAt)
		// name が無ければタグをタイトルにする。
		XCTAssertEqual(channels[0].title, "dev-feature-x")
	}

	func testStableFallsBackToMain() throws
	{
		let json = """
			[{"tag_name": "stable", "prerelease": false, "assets": [
			  {"name": "MLXChat.app.zip", "browser_download_url": "https://example.com/a.zip"}]}]
			"""
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json))
		XCTAssertEqual(channels[0].branch, "main")
		XCTAssertEqual(channels[0].commit, "")
	}

	func testDevChannelsAreSortedByBranch() throws
	{
		let json = """
			[{"tag_name": "dev-b", "prerelease": true, "body": "branch=b", "assets": [
			   {"name": "MLXChat.app.zip", "browser_download_url": "https://example.com/b.zip"}]},
			 {"tag_name": "dev-a", "prerelease": true, "body": "branch=a", "assets": [
			   {"name": "MLXChat.app.zip", "browser_download_url": "https://example.com/a.zip"}]},
			 {"tag_name": "stable", "prerelease": false, "body": "branch=main", "assets": [
			   {"name": "MLXChat.app.zip", "browser_download_url": "https://example.com/s.zip"}]}]
			"""
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json))
		XCTAssertEqual(channels.map(\.branch), ["main", "a", "b"])
	}

	func testInvalidAssetURLIsTreatedAsMissing() throws
	{
		let json = """
			[{"tag_name": "stable", "prerelease": false, "assets": [
			  {"name": "MLXChat.app.zip", "browser_download_url": ""}]}]
			"""
		XCTAssertTrue(try UpdateFeed.channels(fromReleasesJSON: releasesJSON(json)).isEmpty)
	}

	func testUpdateAvailableComparesCommits() throws
	{
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(feed))
		let stable = channels[0]
		XCTAssertFalse(UpdateFeed.updateAvailable(installed: "1234567", channel: stable))
		XCTAssertTrue(UpdateFeed.updateAvailable(installed: "9999999", channel: stable))
		// スタンプが無い（開発実行）ときは常に更新を提案する。
		XCTAssertTrue(UpdateFeed.updateAvailable(installed: nil, channel: stable))
		XCTAssertTrue(UpdateFeed.updateAvailable(installed: "", channel: stable))
		XCTAssertTrue(UpdateFeed.updateAvailable(installed: "unknown", channel: stable))
	}

	func testChannelLookupByBranch() throws
	{
		let channels = try UpdateFeed.channels(fromReleasesJSON: releasesJSON(feed))
		XCTAssertEqual(UpdateFeed.channel(named: "main", in: channels)?.tag, "stable")
		XCTAssertNil(UpdateFeed.channel(named: "nope", in: channels))
	}

	func testValueOfKeyInNotes()
	{
		let body = "channel=dev\n  branch = spaced \ncommit=abc"
		XCTAssertEqual(UpdateFeed.value(of: "channel", in: body), "dev")
		XCTAssertEqual(UpdateFeed.value(of: "commit", in: body), "abc")
		XCTAssertEqual(UpdateFeed.value(of: "missing", in: body), "")
	}

	func testAssetNamesMatchTheWorkflow()
	{
		// build.yml のアセット名と対。片方だけ変えると自動アップデートが
		// 「アセットの無いリリース」として黙って無視する。
		XCTAssertEqual(UpdateFeed.appAssetName, "MLXChat.app.zip")
		XCTAssertEqual(UpdateFeed.ipaAssetName, "MLXChat.ipa")
	}

	func testMalformedJSONThrows()
	{
		XCTAssertThrowsError(try UpdateFeed.channels(fromReleasesJSON: Data("nope".utf8)))
	}
}
