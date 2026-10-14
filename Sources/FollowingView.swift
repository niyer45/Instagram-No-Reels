import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Instagram renders its own interface. Native UI appears only for filtering
/// attention, file import, or a network error; there is no replacement chrome.
struct FollowingView: View {
    @EnvironmentObject private var session: InstagramSession
    @State private var importer = false

    var body: some View {
        ZStack(alignment: .top) {
            InstagramWebView(webView: session.webView)
                .opacity(session.browsing ? 0 : 1)
                .allowsHitTesting(!session.browsing)
            InstagramWebView(webView: session.browsingWebView)
                .opacity(session.browsing && !session.profileActive && !session.searchActive ? 1 : 0)
                .allowsHitTesting(session.browsing && !session.profileActive && !session.searchActive)
            InstagramWebView(webView: session.profileWebView)
                .opacity(session.profileActive ? 1 : 0)
                .allowsHitTesting(session.profileActive)
            InstagramWebView(webView: session.searchWebView)
                .opacity(session.searchActive ? 1 : 0)
                .allowsHitTesting(session.searchActive)
            if session.isHomeFeed && !session.storyViewerOpen {
                Color(uiColor: session.backgroundColor)
                    .frame(height: session.homeHeaderHeight + session.pullOffset)
                    .allowsHitTesting(false)
                    .zIndex(1)
            }
            if session.isHomeFeed || session.storyViewerOpen {
                StoriesViewport(webView: session.storiesWebView, contentHeight: session.webView.bounds.height > 0 ? session.webView.bounds.height : 800)
                    .frame(height: session.storyViewerOpen ? session.webView.bounds.height : max(session.homeHeaderHeight, session.storiesTop + session.storiesHeight), alignment: .top)
                    .clipped()
                    .contentShape(Rectangle())
                    .opacity(session.storiesHeight > 0 || session.storyViewerOpen ? 1 : 0)
                    .allowsHitTesting(session.storiesHeight > 0 || session.storyViewerOpen)
                    .offset(y: session.pullOffset)
                    .zIndex(2)
            }
            if session.isInitialLaunch {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image("InstagramLaunchLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                    VStack {
                        Spacer()
                        Image("InstagramLaunchBranding").resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 76, height: 38).padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)
                .accessibilityLabel("Instagram")
            }

        }
        .background(Color(uiColor: session.backgroundColor).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $session.controlsPresented) { controls }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { session.importFollowing(from: url) }
            case .failure(let error): session.error = error.localizedDescription
            }
        }
        .alert("Instagram", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
    }

    private var controls: some View {
        NavigationStack {
            List {
                Section("Content") {
                    Label("Reels disabled", systemImage: "video.slash")
                    Label("Ads and suggested posts hidden", systemImage: "line.3.horizontal.decrease")
                    Label("Posts require followed-account evidence", systemImage: "person.crop.circle.badge.checkmark")
                }
                Section {
                    Text(session.message).font(.subheadline)
                    LabeledContent("Visible posts", value: "\(session.shown)")
                    LabeledContent("Hidden posts", value: "\(session.hidden)")
                    LabeledContent("Post records recognized", value: "\(session.metadataRecords)")
                    Button("Reload Instagram") { session.controlsPresented = false; session.refresh() }
                } header: { Text("Feed status") } footer: {
                    Text("Instagram’s page can provide follow status for its loaded posts. When it does not, those posts stay hidden until you import your following list. The rest of Instagram’s interface stays available.")
                }
                Section {
                    LabeledContent("Imported accounts", value: "\(session.snapshot.handles.count)")
                    if !session.snapshot.handles.isEmpty {
                        LabeledContent("Imported", value: session.snapshot.importedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button("Import following.json") { session.controlsPresented = false; importer = true }
                    if !session.snapshot.handles.isEmpty {
                        Button("Remove imported list", role: .destructive) { session.clearFollowing() }
                    }
                } header: { Text("Optional following-list fallback") } footer: {
                    Text("Use the JSON following list from your Instagram information export. Reimport it after following or unfollowing accounts. Fresh negative follow status from Instagram takes priority over an older imported list.")
                }
                Section("Account") {
                    Button("Sign in to Instagram") { session.controlsPresented = false; session.showLogin() }
                    Button("Sign out on this device", role: .destructive) { session.controlsPresented = false; session.signOut() }
                }
            }
            .navigationTitle("Content filters")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.controlsPresented = false } } }
        }
    }
}

private struct InstagramWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct StoriesViewport: UIViewRepresentable {
    let webView: WKWebView
    let contentHeight: CGFloat
    func makeUIView(context: Context) -> ClippedStoriesContainer {
        let container = ClippedStoriesContainer()
        container.clipsToBounds = true
        container.webView = webView
        container.contentHeight = contentHeight
        container.addSubview(webView)
        return container
    }
    func updateUIView(_ container: ClippedStoriesContainer, context: Context) {
        container.contentHeight = contentHeight
        if webView.superview !== container { container.addSubview(webView) }
        container.setNeedsLayout()
    }
}

private final class ClippedStoriesContainer: UIView {
    weak var webView: WKWebView?
    var contentHeight: CGFloat = 800
    override func layoutSubviews() {
        super.layoutSubviews()
        webView?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, contentHeight))
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
