import SwiftUI
import AppKit

struct StartScreen: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var keyMonitor: Any?

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
                label: "Switch Workspace",
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

    var body: some View {
        ZStack {
            backgroundGlow

            VStack(spacing: 40) {
                StartScreenLogo()

                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        ForEach(actionItems) { item in
                            StartScreenActionRow(
                                icon: item.icon,
                                label: item.label,
                                keyHint: item.keyHint,
                                isEnabled: item.isEnabled,
                                action: item.action
                            )
                        }
                    }
                    .frame(width: 320)

                    Text("\(versionText) · \(workspaceCountText)")
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(theme.textDim)
                        .padding(.top, 8)
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear {
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
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
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

}
