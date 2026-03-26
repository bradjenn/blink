import SwiftUI

// MARK: - Block model

enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case codeBlock(language: String?, code: String)
    case bulletList([String])

    var id: String {
        switch self {
        case .heading(_, let t): return "h-\(t.hashValue)"
        case .paragraph(let t): return "p-\(t.hashValue)"
        case .codeBlock(_, let c): return "cb-\(c.hashValue)"
        case .bulletList(let items): return "bl-\(items.hashValue)"
        }
    }
}

// MARK: - Parser

func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Headings
        if let level = headingLevel(line) {
            let content = String(line.drop(while: { $0 == "#" || $0 == " " }))
            blocks.append(.heading(level: level, text: content))
            i += 1
            continue
        }

        // Fenced code blocks
        if line.hasPrefix("```") {
            let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var code: [String] = []
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                code.append(lines[i])
                i += 1
            }
            i += 1 // skip closing fence
            blocks.append(.codeBlock(
                language: lang.isEmpty ? nil : lang,
                code: code.joined(separator: "\n")
            ))
            continue
        }

        // Bullet lists
        if isBullet(line) {
            var items: [String] = []
            while i < lines.count && isBullet(lines[i]) {
                items.append(stripBullet(lines[i]))
                i += 1
            }
            blocks.append(.bulletList(items))
            continue
        }

        // Blank lines — skip
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            i += 1
            continue
        }

        // Paragraph — collect consecutive non-blank, non-special lines
        var para: [String] = []
        while i < lines.count {
            let l = lines[i]
            if l.trimmingCharacters(in: .whitespaces).isEmpty
                || headingLevel(l) != nil
                || l.hasPrefix("```")
                || isBullet(l) {
                break
            }
            para.append(l)
            i += 1
        }
        if !para.isEmpty {
            blocks.append(.paragraph(para.joined(separator: "\n")))
        }
    }

    return blocks
}

private func headingLevel(_ line: String) -> Int? {
    if line.hasPrefix("### ") { return 3 }
    if line.hasPrefix("## ") { return 2 }
    if line.hasPrefix("# ") { return 1 }
    return nil
}

private func isBullet(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
}

private func stripBullet(_ line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
    if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
    return trimmed
}

// MARK: - View

struct MarkdownText: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let content: String
    let project: Project?

    private var blocks: [MarkdownBlock] {
        parseMarkdownBlocks(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(Fonts.primary(
                    size: level == 1 ? 18 : level == 2 ? 16 : 14,
                    weight: .bold,
                    family: store.uiFontFamily
                ))
                .foregroundStyle(theme.text)

        case .paragraph(let text):
            inlineMarkdownText(text)
                .padding(.bottom, 4)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(theme.textMuted)
                        inlineMarkdownText(item)
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }

    private func inlineMarkdownText(_ text: String) -> some View {
        Group {
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(Fonts.primary(size: 13, family: store.uiFontFamily))
        .lineSpacing(2)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.openURL, OpenURLAction { url in
            handleOpenURL(url)
        })
    }

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language {
                HStack {
                    Spacer()
                    Text(lang)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
            }

            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        guard let project,
              let filePath = resolvedFilePath(from: url) else {
            return .systemAction(url)
        }

        let command = nvimCommand(for: filePath, line: resolvedLineNumber(from: url))
        let label = URL(fileURLWithPath: filePath).lastPathComponent
        store.openTab(projectId: project.id, command: command, label: label)
        return .handled
    }

    private func resolvedFilePath(from url: URL) -> String? {
        if url.isFileURL {
            return url.path.isEmpty ? nil : url.path
        }

        guard url.scheme == nil else {
            return nil
        }

        let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            return nil
        }

        return path
    }

    private func resolvedLineNumber(from url: URL) -> Int? {
        if let fragment = url.fragment,
           let line = parseLineNumber(from: fragment) {
            return line
        }

        return parseLineNumber(from: url.lastPathComponent)
    }

    private func parseLineNumber(from value: String) -> Int? {
        if let match = value.range(of: #"L(\d+)"#, options: .regularExpression) {
            let digits = value[match].drop(while: { !$0.isNumber })
            return Int(digits)
        }

        if let match = value.range(of: #":(\d+)(?::\d+)?$"#, options: .regularExpression) {
            let digits = value[match]
                .dropFirst()
                .prefix(while: \.isNumber)
            return Int(digits)
        }

        return nil
    }

    private func nvimCommand(for path: String, line: Int?) -> String {
        var components = ["env", "EDITOR=nvim", "VISUAL=nvim", "nvim"]

        if let line {
            components.append("+\(line)")
        }

        components.append(shellQuote(path))
        return components.joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
