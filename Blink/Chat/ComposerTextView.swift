import SwiftUI
import AppKit

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var placeholderString: String
    var placeholderColor: NSColor
    var maxHeight: CGFloat
    var onCommit: (() -> Void)?
    @Binding var dynamicHeight: CGFloat
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PlaceholderTextView.scrollableTextView()
        let textView = scrollView.documentView as! PlaceholderTextView

        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = textColor
        textView.string = text
        textView.insertionPointColor = textColor

        // Zero out internal padding so SwiftUI .padding() is the only source
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0

        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        textView.placeholderString = placeholderString
        textView.placeholderColor = placeholderColor
        textView.placeholderFont = font

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        context.coordinator.textView = textView

        textView.onFocusChange = { focused in
            DispatchQueue.main.async {
                context.coordinator.parent.isFocused = focused
            }
        }

        DispatchQueue.main.async {
            context.coordinator.recalcHeight()
            scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight()
        }

        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.placeholderString = placeholderString
        textView.placeholderColor = placeholderColor
        textView.placeholderFont = font
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: PlaceholderTextView?

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            recalcHeight()
        }

        func recalcHeight() {
            guard let textView else { return }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)

            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset
            let contentHeight = usedRect.height + inset.height * 2
            let minHeight = (textView.font?.boundingRectForFont.height ?? 20)
                + inset.height * 2

            let newHeight = min(max(contentHeight, minHeight), parent.maxHeight)

            if abs(parent.dynamicHeight - newHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = newHeight
                }
            }
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            // Cmd+Return sends; plain Return inserts newline (default)
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.command) {
                    parent.onCommit?()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - NSTextView subclass with placeholder

class PlaceholderTextView: NSTextView {
    var placeholderString: String = ""
    var placeholderColor: NSColor = .placeholderTextColor
    var placeholderFont: NSFont?
    var onFocusChange: ((Bool) -> Void)?

    override class var defaultMenu: NSMenu? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: placeholderColor,
                .font: placeholderFont ?? font ?? NSFont.systemFont(ofSize: 15),
            ]
            let padding = textContainer?.lineFragmentPadding ?? 0
            let rect = NSRect(
                x: textContainerInset.width + padding,
                y: textContainerInset.height,
                width: bounds.width - (textContainerInset.width + padding) * 2,
                height: bounds.height - textContainerInset.height * 2
            )
            NSString(string: placeholderString).draw(in: rect, withAttributes: attrs)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        needsDisplay = true
        return result
    }

    // Return a properly configured scrollable text view using this subclass
    override class func scrollableTextView() -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PlaceholderTextView()

        textView.autoresizingMask = [.width]
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        return scrollView
    }
}
