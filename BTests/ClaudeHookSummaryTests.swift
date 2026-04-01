import XCTest
@testable import Blink

final class ClaudeHookSummaryTests: XCTestCase {
    func testPromptTitleUsesPlainTextInput() {
        let title = ClaudeHookSummary.promptTitle(rawInput: "Add Gemini CLI to Blink")

        XCTAssertEqual(title, "Add Gemini CLI to Blink")
    }

    func testPromptTitleUsesJSONMessageField() {
        let rawInput = #"{"message":"Add Gemini CLI to Blink with settings UI"}"#

        let title = ClaudeHookSummary.promptTitle(rawInput: rawInput)

        XCTAssertEqual(title, "Add Gemini CLI to Blink with settings UI")
    }

    func testNotificationSummaryClassifiesPermissionRequests() {
        let rawInput = #"{"event":"notification","message":"Approval needed to run npm install"}"#

        let summary = ClaudeHookSummary.notificationSummary(rawInput: rawInput)

        XCTAssertEqual(summary.subtitle, "Permission")
        XCTAssertEqual(summary.body, "Approval needed to run npm install")
    }

    func testNotificationSummaryFallsBackForEmptyInput() {
        let summary = ClaudeHookSummary.notificationSummary(rawInput: "")

        XCTAssertEqual(summary.subtitle, "Waiting")
        XCTAssertEqual(summary.body, "Claude is waiting for your input")
    }

    func testCompletionSummaryUsesTranscriptAssistantMessage() throws {
        let transcriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-hook-transcript-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: transcriptURL) }

        let transcript = """
        {"message":{"role":"assistant","content":"Implemented the sidebar badge and notification flow."}}
        """
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let rawInput = #"{"cwd":"/Users/bradley/Code/blink","transcript_path":"\#(transcriptURL.path)"}"#
        let parsed = ClaudeHookSummary.parse(rawInput: rawInput)
        let summary = ClaudeHookSummary.completionSummary(from: parsed)

        XCTAssertEqual(summary?.subtitle, "Completed in blink")
        XCTAssertEqual(summary?.body, "Implemented the sidebar badge and notification flow.")
    }
}
