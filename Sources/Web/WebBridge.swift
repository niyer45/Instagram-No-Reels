import WebKit

/// Something that handles decoded bridge messages for one web view (a page or the Stories tray).
@MainActor
protocol WebBridgeReceiver: AnyObject {
    func bridge(didReceive message: BridgeMessage)
}

/// The single `instagram` script-message handler. Accepts messages only from the main frame
/// of https://instagram.com or https://www.instagram.com, decodes them strictly and forwards
/// them to the receiver registered for the sending web view.
@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "instagram"
    private let receivers = NSMapTable<WKWebView, AnyObject>.weakToWeakObjects()

    func register(_ receiver: WebBridgeReceiver, for webView: WKWebView) {
        receivers.setObject(receiver, forKey: webView)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName, Self.isTrusted(message.frameInfo),
              let webView = message.webView,
              let receiver = receivers.object(forKey: webView) as? WebBridgeReceiver,
              let decoded = BridgeMessage.decode(message.body) else { return }
        receiver.bridge(didReceive: decoded)
    }

    static func isTrusted(_ frame: WKFrameInfo) -> Bool {
        let origin = frame.securityOrigin
        return frame.isMainFrame && origin.protocol == "https"
            && ["instagram.com", "www.instagram.com"].contains(origin.host.lowercased())
            && (origin.port == 0 || origin.port == 443)
    }
}
