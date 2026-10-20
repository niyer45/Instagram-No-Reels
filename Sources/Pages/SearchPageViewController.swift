import UIKit
import SwiftUI

/// The Search tab root. Adds Search-only behaviour on top of `WebPageViewController`:
/// the native caught-up state fills the space below Instagram's search field while Search is
/// idle (fading in and out like the native app) and never shows over login content, and
/// scrolling the results dismisses the keyboard. The field, Cancel control and result rows are
/// skinned in the page (NativeSkin.css `Search`, Bridge.js `Tabs`).
@MainActor
final class SearchPageViewController: WebPageViewController {
    private var idleHost: UIHostingController<SearchIdleView>?
    private var idleTop: CGFloat = 0
    private var idleRequested = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Native Search dismisses the keyboard as soon as the results are dragged.
        webView.scrollView.keyboardDismissMode = .onDrag
        #if DEBUG
        onReady = { [weak self] in self?.searchReady() }
        #endif
    }

    /// Search configures its web view's scroll view once (keyboard dismissal above); a web view
    /// recreated after unloading would lose that, so unloading only blanks the document.
    override var releasesWebViewWhenUnloaded: Bool { false }

    override func layoutPage() {
        super.layoutPage()
        guard let idle = idleHost?.view else { return }
        let top = webView.frame.minY + idleTop
        idle.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: max(webView.frame.maxY - top, 0))
    }

    override func bridge(didReceive message: BridgeMessage) {
        #if DEBUG
        if case .searchFocus = message { searchFocused(); return }
        #endif
        guard case .searchIdle(let idle, let top) = message else {
            super.bridge(didReceive: message)
            return
        }
        idleRequested = idle
        idleTop = top
        updateIdle()
    }

    override func setLoginContent(_ login: Bool) {
        super.setLoginContent(login)
        updateIdle()
    }

    /// Idle only on Instagram's own Search page: not over login content, and only when the page
    /// has Instagram's search field (the logged-out /explore/ "popular" page has none).
    private func updateIdle() {
        let show = idleRequested && route.kind == .search && !isLoginContent
        if show, idleHost == nil {
            webView.evaluateJavaScript("window.__instagramTabs?window.__instagramTabs.hasSearchField():false") { [weak self] result, _ in
                guard let self, result as? Bool == true, self.idleRequested, self.route.kind == .search, !self.isLoginContent else { return }
                self.showIdle()
            }
        } else if !show, let host = idleHost {
            idleHost = nil
            UIView.animate(withDuration: 0.15, animations: { host.view.alpha = 0 }, completion: { _ in
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            })
        } else {
            view.setNeedsLayout()
        }
    }

    private func showIdle() {
        if idleHost == nil {
            let host = UIHostingController(rootView: SearchIdleView())
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.alpha = 0
            addChild(host)
            view.insertSubview(host.view, aboveSubview: webView)
            host.didMove(toParent: self)
            idleHost = host
            view.setNeedsLayout()
            view.layoutIfNeeded()
            UIView.animate(withDuration: 0.2) { host.view.alpha = 1 }
        }
    }

    #if DEBUG
    /// Outline capture state: bumped at each ready so delayed captures of an older page are skipped.
    private var outlineGeneration = 0

    private func searchReady() {
        outlineGeneration += 1
        let generation = outlineGeneration
        captureOutline("search-ready")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.outlineGeneration == generation else { return }
            self.captureOutline("search-ready-3s")
        }
    }

    /// The search field gained focus: capture one second later (keyboard and Cancel settled).
    private func searchFocused() {
        let generation = outlineGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.outlineGeneration == generation else { return }
            self.captureOutline("search-focus")
        }
    }

    /// Writes a sanitized page outline (structure only, including the `searchField` section) plus native frame numbers.
    private func captureOutline(_ capture: String) {
        guard !isLoginContent, route.kind == .search else { return }
        let script = "window.__instagram&&window.__instagram.outline?window.__instagram.outline():null"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let outline = result as? [String: Any] else { return }
            Task { @MainActor in
                guard let self else { return }
                let native: [String: Any] = [
                    "webViewFrame": Self.ints(self.webView.frame),
                    "adjustedInsetTop": Int(self.webView.scrollView.adjustedContentInset.top.rounded()),
                    "isReady": self.isReady,
                    "idleShown": self.idleHost != nil,
                    "idleRequested": self.idleRequested,
                ]
                Diagnostics.writeOutline(outline, native: native, capture: capture)
            }
        }
    }

    /// Shows the idle state over the skeleton without a page (simulator screenshots; `SHELL_PRESENT=search-idle`).
    func debugShowIdle(top: CGFloat) {
        idleTop = top
        showIdle()
        if let idle = idleHost?.view { idle.backgroundColor = environment.theme.background; view.bringSubviewToFront(idle) }
    }
    #endif
}
