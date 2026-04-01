import SwiftUI

struct SidebarProjectItem: View {
    @Environment(\.theme) private var theme

    let project: Project
    let isActive: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let terminalCount: Int
    let hasUnread: Bool
    let claudeTabActivities: [String: ClaudeTabActivity]
    let shellDetectedAIPaneKinds: [String: ShellDetectedAIPaneKind]
    let tabs: [AppTab]
    let selectedTabId: String?
    let activeTabId: String?
    let onSelect: (Bool) -> Void
    let onToggleExpansion: () -> Void
    let onSelectTab: (String, Bool) -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var showContextMenu = false

    private var projectClaudeActivitySummary: (tabLabel: String, activity: ClaudeTabActivity)? {
        let candidates = tabs.compactMap { tab -> (String, ClaudeTabActivity)? in
            guard let activity = claudeTabActivities[tab.id] else { return nil }
            return (tab.label, activity)
        }

        if let needsInput = candidates
            .filter({ $0.1.kind == .needsInput })
            .max(by: { $0.1.updatedAt < $1.1.updatedAt }) {
            return needsInput
        }

        if let running = candidates
            .filter({ $0.1.kind == .running })
            .max(by: { $0.1.updatedAt < $1.1.updatedAt }) {
            return running
        }

        return candidates
            .filter { $0.1.kind == .completed }
            .max(by: { $0.1.updatedAt < $1.1.updatedAt })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Layout.sidebarItemGap) {
                Button(action: { onSelect(true) }) {
                    HStack(spacing: Layout.sidebarItemGap) {
                        ProjectFavicon(projectName: project.name, projectPath: project.path, size: 24)
                            .scaleEffect(isHovered ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: isHovered)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(Fonts.primary(size: 15, weight: .medium))
                                .foregroundStyle(isSelected ? theme.text : (isActive ? theme.text : theme.textMuted))
                                .lineLimit(1)

                            if !isExpanded,
                               let summary = projectClaudeActivitySummary {
                                ClaudeActivityLabel(
                                    activity: summary.activity,
                                    tabLabel: summary.tabLabel
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    if hasUnread {
                        PulseDot(color: theme.accent, glowColor: theme.accentGlow)
                    }

                    if !tabs.isEmpty {
                        Button(action: onToggleExpansion) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textDim)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
                .frame(minWidth: 14, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.sidebarItemPadding)
            .background(
                isSelected
                    ? theme.accent.opacity(0.10)
                    : (isActive ? theme.accent.opacity(0.04) : (isHovered ? theme.accent2.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.32) : Color.clear, lineWidth: 1)
                    .padding(.leading, Layout.sidebarItemBorderWidth + 6)
            )
            .contentShape(Rectangle())
            .background(
                SecondaryClickTrigger {
                    showContextMenu = true
                }
            )
            .backgroundPopover(isPresented: $showContextMenu) {
                SidebarProjectContextMenu {
                    showContextMenu = false
                    onRemove()
                }
            }

            if isExpanded && !tabs.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(theme.border.opacity(0.45))
                        .frame(width: 1)
                        .padding(.leading, 11)

                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(tabs) { tab in
                            SidebarProjectWindowItem(
                                tab: tab,
                                isActive: activeTabId == tab.id,
                                isSelected: selectedTabId == tab.id,
                                detectedAIKind: shellDetectedAIPaneKinds[tab.id],
                                claudeActivity: claudeTabActivities[tab.id],
                                onSelect: { onSelectTab(tab.id, true) }
                            )
                        }
                    }
                }
                .padding(.leading, 17)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
        }
        .clipped()
        .overlay(alignment: .leading) {
            theme.accent
                .frame(width: Layout.sidebarItemBorderWidth)
                .opacity(isActive || (activeTabId != nil && !isExpanded) ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

private struct SidebarProjectContextMenu: View {
    @Environment(\.theme) private var theme

    let onRemove: () -> Void

    @State private var isRemoveHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onRemove) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRemoveHovered ? theme.danger : theme.textDim)
                        .frame(width: 16)
                    Text("Remove Project")
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(isRemoveHovered ? theme.danger : theme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isRemoveHovered ? theme.danger.opacity(0.10) : Color.clear)
            .onHover { isRemoveHovered = $0 }
            .pointerCursor()
        }
        .frame(width: 180)
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
        .padding(.top, 4)
    }
}

private struct SecondaryClickTrigger: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSecondaryClick = onSecondaryClick
        context.coordinator.installIfNeeded(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSecondaryClick: onSecondaryClick)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onSecondaryClick: () -> Void
        weak var attachedView: NSView?
        var monitor: Any?

        init(onSecondaryClick: @escaping () -> Void) {
            self.onSecondaryClick = onSecondaryClick
        }

        func installIfNeeded(from anchorView: NSView) {
            DispatchQueue.main.async { [weak self, weak anchorView] in
                guard let self, let anchorView else { return }
                guard let hostView = anchorView.superview else { return }

                if self.attachedView !== hostView {
                    self.detach()
                    self.attachedView = hostView
                    self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                        guard let self,
                              let attachedView = self.attachedView,
                              event.window === attachedView.window else {
                            return event
                        }

                        let location = attachedView.convert(event.locationInWindow, from: nil)
                        guard attachedView.bounds.contains(location) else {
                            return event
                        }

                        self.onSecondaryClick()
                        return nil
                    }
                }
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            attachedView = nil
        }
    }
}

private struct SidebarProjectWindowItem: View {
    @Environment(\.theme) private var theme

    let tab: AppTab
    let isActive: Bool
    let isSelected: Bool
    let detectedAIKind: ShellDetectedAIPaneKind?
    let claudeActivity: ClaudeTabActivity?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                leadingIcon
                    .frame(width: 12, height: 12)

                Text(tab.label)
                    .font(Fonts.primary(size: 12.5))
                    .foregroundStyle(isSelected ? theme.text : (isActive ? theme.accent : (isHovered ? theme.textMuted : theme.textDim)))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let claudeActivity {
                    Image(systemName: statusIconName(for: claudeActivity.kind))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(statusColor(for: claudeActivity.kind))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.10) : (isActive ? theme.accent.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if tab.command == nil {
            if let detectedAIKind {
                aiIcon(for: detectedAIKind)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? theme.accent : theme.textDim)
            }
        } else {
            Image(systemName: "play.rectangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? theme.accent : theme.textDim)
        }
    }

    @ViewBuilder
    private func aiIcon(for kind: ShellDetectedAIPaneKind) -> some View {
        switch kind {
        case .claude:
            BundledSVGIcon(name: "claude-icon")
        case .codex:
            BundledSVGIcon(name: "codex-icon")
        case .opencode:
            BundledSVGIcon(name: "opencode-icon")
        }
    }

    private func statusIconName(for kind: ClaudeTabActivityKind) -> String {
        switch kind {
        case .running:
            return "bolt.fill"
        case .needsInput:
            return "bell.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private func statusColor(for kind: ClaudeTabActivityKind) -> Color {
        switch kind {
        case .running:
            return theme.accent
        case .needsInput:
            return theme.yellow
        case .completed:
            return theme.green
        }
    }
}

private struct ClaudeActivityLabel: View {
    @Environment(\.theme) private var theme

    let activity: ClaudeTabActivity
    let tabLabel: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIconName)
                .font(.system(size: 9, weight: .semibold))
            Text(statusText)
                .font(Fonts.primary(size: 10.5))
                .lineLimit(1)
        }
        .foregroundStyle(statusColor)
    }

    private var statusIconName: String {
        switch activity.kind {
        case .running:
            return "bolt.fill"
        case .needsInput:
            return "bell.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private var statusText: String {
        switch activity.kind {
        case .running:
            return "\(tabLabel) running"
        case .needsInput:
            return "\(tabLabel) needs input"
        case .completed:
            return "\(tabLabel) finished"
        }
    }

    private var statusColor: Color {
        switch activity.kind {
        case .running:
            return theme.accent
        case .needsInput:
            return theme.yellow
        case .completed:
            return theme.green
        }
    }
}

/// Animated pulsing dot indicating active terminals.
struct PulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let color: Color
    let glowColor: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: glowColor, radius: 4, x: 0, y: 0)
            .opacity(reduceMotion ? 1.0 : (isPulsing ? 0.4 : 1.0))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = !reduceMotion }
    }
}
