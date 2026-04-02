import AppKit
import Foundation

@MainActor
protocol BrowserHostController: AnyObject {
    var tabId: String { get }
    var session: BrowserSessionModel { get }
    var hostView: NSView { get }
    var onInteraction: (() -> Void)? { get set }
    var onOpenNewTabRequest: ((URL) -> Void)? { get set }

    func update(
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    )

    func navigate(to rawValue: String)
    func focusWebView()
    func focusAddressBar()
    func goBack()
    func goForward()
    func reload()
    func toggleDeveloperTools()
    func openInDefaultBrowser()
    func invalidate()
}
