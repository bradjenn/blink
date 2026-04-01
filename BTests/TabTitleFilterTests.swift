import Testing
@testable import Blink_Dev

struct TabTitleFilterTests {
    @Test("maps AI terminal titles to friendly names")
    func aiTerminalTitles() {
        #expect(TabTitleFilter.displayName(for: "claude") == "Claude Code")
        #expect(TabTitleFilter.displayName(for: "claude --resume") == "Claude Code")
        #expect(TabTitleFilter.displayName(for: "codex") == "Codex")
        #expect(TabTitleFilter.displayName(for: "opencode --continue") == "OpenCode")
    }
}
