import WebKit

/// Builds the document-start user scripts for a web view from the bundled resources:
/// boot values, NativeSkin.css, Bridge.js and (for pages) FeedFilter.js.
@MainActor
enum UserScripts {
    /// Per-web-view values Bridge.js and FeedFilter.js read at document start.
    struct Boot: Equatable {
        var role: RouteDecision.Role
        var headerHeight: CGFloat = 0
        var hideChrome = true
        var storiesSlot = false
        var storiesHeight: CGFloat = 0
        /// A refresh reload is held behind a snapshot: the reloading document stays invisible until native clears this.
        var refreshing = false
    }

    private static let bridgeSource = resource("Bridge", "js")
    private static let filterSource = resource("FeedFilter", "js")
    private static let skinSource = resource("NativeSkin", "css")

    static func scripts(boot: Boot, policy: [String: Any]) -> [WKUserScript] {
        let values: [String: Any] = ["role": boot.role.rawValue, "headerHeight": Double(boot.headerHeight), "hideChrome": boot.hideChrome, "storiesSlot": boot.storiesSlot, "storiesHeight": Double(boot.storiesHeight), "refreshing": boot.refreshing, "policy": policy]
        var sources = ["window.__instagramBoot=Object.freeze(\(json(values)));", skinInstaller(), bridgeSource]
        if boot.role == .page { sources.append(filterSource) }
        return sources.map { WKUserScript(source: $0, injectionTime: .atDocumentStart, forMainFrameOnly: true) }
    }

    static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func skinInstaller() -> String {
        let css = json(["css": skinSource])
        return """
        (function(){const css=(\(css)).css;function add(){const root=document.documentElement;if(!root)return false;if(document.getElementById('native-skin'))return true;const style=document.createElement('style');style.id='native-skin';style.textContent=css;root.appendChild(style);return true;}if(!add())new MutationObserver(function(records,observer){if(add())observer.disconnect();}).observe(document,{childList:true});})();
        """
    }

    private static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing bundled resource \(name).\(ext); rebuild the app with Resources/ included.")
        }
        return text
    }
}
