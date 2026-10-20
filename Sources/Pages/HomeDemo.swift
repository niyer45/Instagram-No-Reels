#if DEBUG
import UIKit

/// DEBUG-only Home harness for simulator screenshots, since agents cannot sign in or touch:
/// with `SHELL_SKELETON_PREVIEW=1` and `SHELL_HOME_FIXTURE=<absolute path to an HTML file>`
/// (for example `Tests/fixtures/home-feed.html`), Home loads that file as the Following feed
/// (Bridge.js, FeedFilter.js and NativeSkin.css run as on Instagram), and
/// `SHELL_HOME_DEMO=collapse|reveal|end|card|refresh|light|dark` drives the scroll view once it is ready.
/// Pass both with `SIMCTL_CHILD_` prefixes to `xcrun simctl launch`. Release builds exclude this.
@MainActor
enum HomeDemo {
    static func start(on page: HomePageViewController) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SHELL_SKELETON_PREVIEW"] == "1", let path = environment["SHELL_HOME_FIXTURE"],
              let html = try? String(contentsOfFile: path, encoding: .utf8),
              let base = URL(string: "https://www.instagram.com/?variant=following") else { return }
        page.webView.loadHTMLString(html, baseURL: base)
        let step = environment["SHELL_HOME_DEMO"] ?? ""
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak page] timer in
            MainActor.assumeIsolated {
                guard let page else { timer.invalidate(); return }
                guard page.isReady else { return }
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { run(step, on: page) }
            }
        }
    }

    private static func run(_ step: String, on page: HomePageViewController) {
        let scrollView = page.webView.scrollView
        switch step {
        case "collapse", "reveal":
            // Offsets change in small steps, like a drag, so the collapse logic sees each delta.
            for y in stride(from: 0, through: 400, by: 10) { scrollView.contentOffset.y = CGFloat(y) }
            if step == "reveal" {
                for y in stride(from: 400, through: 370, by: -2) { scrollView.contentOffset.y = CGFloat(y) }
            }
        case "end":
            let bottom = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
            for y in stride(from: 0, through: bottom, by: 10) { scrollView.contentOffset.y = y }
            scrollView.contentOffset.y = bottom
        case "card":
            // Scrolling near the card makes FeedFilter continue into older posts, so the card is
            // moved under the tray for its screenshot instead.
            page.webView.evaluateJavaScript("(function(){const c=document.querySelector('[data-instagram-caught-up]'),s=document.querySelector('[data-instagram-stories-slot]');if(c&&s)s.after(c);})()", completionHandler: nil)
        case "refresh":
            scrollView.refreshControl?.beginRefreshing()
            scrollView.contentOffset.y = -110
        case "light":
            page.environment.theme.update(rgb: [255, 255, 255])
        case "dark":
            // Restores Instagram dark after "light" (the theme colour persists between launches).
            page.environment.theme.update(rgb: [12, 16, 20])
        default:
            break
        }
    }
}
#endif
