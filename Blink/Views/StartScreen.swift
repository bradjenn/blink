import SwiftUI
import AppKit

struct StartScreen: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    @State private var keyMonitor: Any?
    @State private var displayedBannerFontSize: CGFloat?

    private static let terminalWorkspaceId = "__start_screen__"
    private static let terminalWorkspaceName = "Blink"
    private static let terminalPrefix = "start-screen-"
    private static let bannerPaddingRows = 4
    private static let preferredBannerFontSize: CGFloat = 13
    private static let minimumBannerFontSize: CGFloat = 11
    private static let bannerCellWidthMultiplier: CGFloat = 0.9
    private static let bannerRowHeightMultiplier: CGFloat = 1.32
    private static let contentPadding: CGFloat = 96
    private static let estimatedMenuHeight: CGFloat = 320
    private static let menuWidth: CGFloat = 540
    private static let bannerResizeDebounceNanoseconds: UInt64 = 180_000_000

    private struct ActionItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let keyHint: String
        let isEnabled: Bool
        let action: () -> Void
    }

    private var actionItems: [ActionItem] {
        var items = [
            ActionItem(
                id: "scratch",
                icon: "~",
                label: "Open Scratch Space",
                keyHint: "c",
                isEnabled: true,
                action: { store.openScratchSpace() }
            ),
            ActionItem(
                id: "add",
                icon: "+",
                label: "New Workspace",
                keyHint: "a",
                isEnabled: true,
                action: { store.presentWorkspaceOnboarding() }
            ),
            ActionItem(
                id: "switch",
                icon: "\u{2318}",
                label: "Open Workspace",
                keyHint: "p",
                isEnabled: !store.workspaces.isEmpty,
                action: { store.presentWorkspaceSwitcher() }
            ),
        ]

        if store.lastSelectedWorkspace != nil {
            items.append(
                ActionItem(
                    id: "resume",
                    icon: "\u{21A9}",
                    label: "Resume Last Session",
                    keyHint: "r",
                    isEnabled: true,
                    action: { store.resumeLastWorkspaceSession() }
                )
            )
        }

        items.append(contentsOf: [
            ActionItem(
                id: "settings",
                icon: "\u{2699}",
                label: "Settings",
                keyHint: "s",
                isEnabled: true,
                action: { store.setActiveView(.settings) }
            ),
            ActionItem(
                id: "quit",
                icon: "\u{23FB}",
                label: "Quit",
                keyHint: "q",
                isEnabled: true,
                action: { NSApp.terminate(nil) }
            ),
        ])

        return items
    }

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(shortVersion ?? "0.1.0")"
    }

    private var workspaceCountText: String {
        "\(store.workspaces.count) workspace\(store.workspaces.count == 1 ? "" : "s")"
    }

    private var dashboardLogoLines: [String] {
        let logo = [
            "██████╗ ██╗     ██╗███╗   ██╗██╗  ██╗",
            "██╔══██╗██║     ██║████╗  ██║██║ ██╔╝",
            "██████╔╝██║     ██║██╔██╗ ██║█████╔╝ ",
            "██╔══██╗██║     ██║██║╚██╗██║██╔═██╗ ",
            "██████╔╝███████╗██║██║ ╚████║██║  ██╗",
            "╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝",
        ]
        let blockWidth = logo.map(\.count).max() ?? 0

        return logo.map { Self.centeredLine($0, width: blockWidth) }
    }

    private var dashboardCommand: String {
        Self.dashboardCommand(lines: dashboardLogoLines)
    }

    private func dashboardTabId(for bannerFontSize: CGFloat) -> String {
        "\(Self.terminalPrefix)\(abs(dashboardCommand.hashValue))-\(Int(bannerFontSize.rounded()))"
    }

    private func terminalRowHeight(for bannerFontSize: CGFloat) -> CGFloat {
        bannerFontSize * Self.bannerRowHeightMultiplier
    }

    private func bannerHeight(for bannerFontSize: CGFloat) -> CGFloat {
        CGFloat(dashboardLogoLines.count + Self.bannerPaddingRows) * terminalRowHeight(for: bannerFontSize)
    }

    private func bannerFontSize(for size: CGSize) -> CGFloat {
        let blockWidth = CGFloat(dashboardLogoLines.map(\.count).max() ?? 37)
        let blockHeight = CGFloat(dashboardLogoLines.count + Self.bannerPaddingRows)

        let availableWidth = max(280, min(size.width - Self.contentPadding, size.width * 0.58))
        let availableHeight = max(220, size.height - Self.estimatedMenuHeight)

        let widthLimitedFont = availableWidth / (blockWidth * Self.bannerCellWidthMultiplier)
        let heightLimitedFont = availableHeight / (blockHeight * Self.bannerRowHeightMultiplier)
        let clampedFont = min(Self.preferredBannerFontSize, widthLimitedFont, heightLimitedFont)

        return max(Self.minimumBannerFontSize, clampedFont)
    }

    var body: some View {
        GeometryReader { geometry in
            let targetBannerFontSize = CGFloat(Int(bannerFontSize(for: geometry.size).rounded()))
            let resolvedBannerFontSize = displayedBannerFontSize ?? targetBannerFontSize
            let dashboardTabId = dashboardTabId(for: resolvedBannerFontSize)
            let bannerHeight = bannerHeight(for: resolvedBannerFontSize)

            ZStack {
                backgroundGlow

                VStack(spacing: 28) {
                    TerminalView(
                        tabId: dashboardTabId,
                        paneId: dashboardTabId,
                        ghosttyApp: ghosttyApp,
                        surfaceManager: surfaceManager,
                        workspaceId: Self.terminalWorkspaceId,
                        workspaceName: Self.terminalWorkspaceName,
                        workingDirectory: NSHomeDirectory(),
                        isFocused: false,
                        command: dashboardCommand,
                        autoFocusOnReady: false,
                        shellPathOverride: "/bin/sh",
                        usesLoginShell: false,
                        shellIntegrationEnabled: false,
                        fontSizeOverride: resolvedBannerFontSize,
                        allowsPointerPassthrough: true
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: bannerHeight)
                    .accessibilityHidden(true)

                    menuContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(32)
            .onAppear {
                displayedBannerFontSize = targetBannerFontSize
                installKeyMonitor()
                destroyStaleStartScreenSurfaces(keeping: dashboardTabId)
            }
            .onDisappear {
                removeKeyMonitor()
                destroyAllStartScreenSurfaces()
            }
            .task(id: targetBannerFontSize) {
                guard displayedBannerFontSize != nil else { return }
                if displayedBannerFontSize == targetBannerFontSize {
                    return
                }

                try? await Task.sleep(nanoseconds: Self.bannerResizeDebounceNanoseconds)
                guard !Task.isCancelled else { return }
                displayedBannerFontSize = targetBannerFontSize
            }
            .onChange(of: dashboardTabId, initial: false) { oldValue, newValue in
                surfaceManager.destroySurface(tabId: oldValue)
                destroyStaleStartScreenSurfaces(keeping: newValue)
            }
        }
    }

    private var menuContent: some View {
        VStack(spacing: 12) {
            ForEach(actionItems) { item in
                StartScreenActionRow(
                    icon: item.icon,
                    label: item.label,
                    keyHint: item.keyHint,
                    isEnabled: item.isEnabled,
                    action: item.action
                )
                .frame(width: Self.menuWidth)
            }

            Text("\(versionText) · \(workspaceCountText)")
                .font(Fonts.primary(size: 11))
                .foregroundStyle(theme.textDim)
                .padding(.top, 14)
        }
        .frame(width: Self.menuWidth)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard !store.showWorkspaceSwitcher,
                  !store.showWorkspaceOnboarding,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] else {
                return event
            }
            let key = event.characters?.lowercased() ?? ""
            guard let item = actionItems.first(where: { $0.keyHint == key }),
                  item.isEnabled else {
                return event
            }
            item.action()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func destroyAllStartScreenSurfaces() {
        let tabIds = surfaceManager.surfaces.keys.filter { $0.hasPrefix(Self.terminalPrefix) }
        for tabId in tabIds {
            surfaceManager.destroySurface(tabId: tabId)
        }
    }

    private func destroyStaleStartScreenSurfaces(keeping activeTabId: String) {
        let staleTabIds = surfaceManager.surfaces.keys.filter {
            $0.hasPrefix(Self.terminalPrefix) && $0 != activeTabId
        }
        for tabId in staleTabIds {
            surfaceManager.destroySurface(tabId: tabId)
        }
    }

    private var backgroundGlow: some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(store.hasWallpaper ? 0.18 : 0.1))
                .frame(width: 360, height: 360)
                .blur(radius: 130)
                .offset(x: -110, y: -70)

            Circle()
                .fill(theme.accent2.opacity(store.hasWallpaper ? 0.16 : 0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 150)
                .offset(x: 130, y: 30)
        }
        .allowsHitTesting(false)
    }

    private static func dashboardCommand(lines: [String]) -> String {
        let topPadding = max(0, lines.count)
        let blockWidth = lines.map(\.count).max() ?? 0
        let renderedLines = lines.map { "print_line \(shellLiteral($0))" }.joined(separator: "\n")

        return """
        cols=0
        rows=0
        last_size=""
        stable_size=""
        stable_count=0

        read_size() {
          size="$(stty size 2>/dev/null)"
          rows="$(printf '%s' "$size" | awk '{print $1}')"
          cols="$(printf '%s' "$size" | awk '{print $2}')"
        }

        has_real_size() {
          [ -n "$cols" ] && [ -n "$rows" ] && [ "$cols" -gt 0 ] && [ "$rows" -gt 0 ]
        }

        wait_for_stable_size() {
          attempts=0
          while [ "$attempts" -lt 30 ]; do
            read_size
            if has_real_size; then
              size_key="${rows}x${cols}"
              if [ "$size_key" = "$stable_size" ]; then
                stable_count=$((stable_count + 1))
              else
                stable_size="$size_key"
                stable_count=1
              fi

              if [ "$stable_count" -ge 3 ]; then
                return
              fi
            fi

            attempts=$((attempts + 1))
            sleep 0.05
          done

          [ -n "$cols" ] || cols=120
          [ -n "$rows" ] || rows=40
        }

        print_line() {
          printf '%*s%s\\n' "$left_pad" '' "$1"
        }

        redraw() {
          read_size
          left_pad=$(( (cols - \(blockWidth) + 1) / 2 ))
          [ "$left_pad" -lt 0 ] && left_pad=0
          top=$(( (rows - \(topPadding)) / 2 ))
          [ "$top" -lt 0 ] && top=0

          printf '\\033[2J\\033[H\\033[?25l'
          i=0
          while [ "$i" -lt "$top" ]; do
            printf '\\n'
            i=$((i + 1))
          done

          \(renderedLines)
        }

        cleanup() {
          printf '\\033[?25h'
        }

        trap redraw WINCH
        trap cleanup EXIT INT TERM
        wait_for_stable_size
        redraw

        while :; do
          read_size
          if has_real_size; then
            size_key="${rows}x${cols}"
          else
            size_key="$last_size"
          fi
          if [ -n "$size_key" ] && [ "$size_key" != "$last_size" ]; then
            redraw
            last_size="$size_key"
          fi
          sleep 0.1
        done
        """
    }

    private static func shellLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func centeredLine(_ value: String, width: Int) -> String {
        guard value.count < width else { return value }
        let leftPadding = max(0, (width - value.count) / 2)
        let centered = String(repeating: " ", count: leftPadding) + value
        return centered.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
