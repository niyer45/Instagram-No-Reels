# Instagram No Reels — Program Direction

This document is the single source of truth for the native-shell program. Every agent
working on this repository reads it first and keeps its code consistent with it. If a
decision here turns out to be wrong in practice, change the code *and* this document in
the same commit, with a one-line rationale.

## 1. Goal

Make the app look and feel like Instagram's native iOS app, not like a web page in a
wrapper. Reels, ads and suggested posts stay removed. Instagram's own mobile website keeps
supplying the *content*; the app supplies all *chrome* and *navigation* natively.

Concretely, a user must never see:

- Instagram's HTML bottom navigation or HTML top header.
- Instagram's website splash screen, loading spinners or white/grey flashes.
- Instant page swaps. Moving between pages is a native push/pop with the interactive
  swipe-back gesture, or a native modal presentation.
- Web artifacts: tap highlights, long-press link callouts, text selection on non-text UI,
  rubber-banding into unstyled background, mis-placed safe-area padding.

And must get:

- A native tab bar styled like Instagram's (opaque, hairline top border, Instagram glyphs,
  the user's avatar in the Profile tab).
- A native Home header (Instagram wordmark, notifications heart, Messenger icon) that
  scrolls away and returns like the native app.
- Native pull-to-refresh, skeleton (shimmer) loading placeholders, light haptics on tab
  changes and pushes.
- Retained tab state: every tab keeps its page and scroll position while you visit others.

## 2. Non-goals and constraints

- **No reconstruction of Instagram's native client.** We do not call Instagram's private
  API ourselves or render the feed from scraped JSON. FeedFilter.js only *observes*
  responses the page already made. Keep this policy.
- **No credential handling.** Login is Instagram's own page inside a web view, in the
  default persistent `WKWebsiteDataStore`. Never read cookies or passwords.
- **Keep the filter.** `Resources/FeedFilter.js` and its 53 node tests are the proven
  core. Change its DOM-chrome handling (bottom nav, messages link, web header tricks) only
  to *remove* it when native chrome replaces it. Filtering logic changes need new tests.
- iOS 17+, Swift 5, Xcode 27. Bundle id `com.local.following`, target/scheme `Following`,
  display name "Instagram". Do not change these.
- Portrait iPhone first. iPad must not crash but is not a design target.
- Dark appearance is the primary design target (matches the shipped icon and splash);
  light must still work because Instagram's page may render light.

## 3. Architecture

Shell is UIKit. SwiftUI is allowed for leaf views (settings sheet, skeletons, small
overlays) hosted in `UIHostingController` / `UIHostingConfiguration`.

```
Sources/
  App/            AppDelegate/SceneDelegate (UIKit lifecycle), AppEnvironment, AccountStore
  Shell/          RootTabBarController, TabItem, InstagramTabBar (styling, avatar item),
                  SplashView
  Navigation/     Router (URL -> Route -> presentation), RouteClassifier, RouteDecision,
                  PageNavigationController
  Pages/          WebPageViewController (one per page), HomePageViewController,
                  PageHeaderView, HomeHeaderView, Wordmark*, StoriesTrayHost,
                  StoryViewerController, SkeletonView, LoadFailureView, SearchIdleView
  Web/            WebPageFactory (WKWebView construction, shared config), WebBridge
                  + BridgeMessage (typed messages), UserScripts (loads Resources/*.js|css)
  Filter/         FollowingPolicy.swift (unchanged), FollowingStore, FilterStatus(+Payload),
                  ContentFilterSettingsView
  Support/        Haptics, Theme (colors, hairline), Glyphs + SVGPath, Diagnostics,
                  DebugLaunchOptions (DEBUG only)
Resources/
  FeedFilter.js   post filtering (observe-only), status messages
  Bridge.js       route/navigate/ready/theme/avatar/story-viewer/tray messages to native
  NativeSkin.css  hides web chrome, native parity styling of web content
Tests/            node tests (.cjs) for JS; Swift checks compiled with swiftc
```

### 3.1 Tabs

`RootTabBarController` is a custom container view controller (not `UITabBarController`)
that draws `InstagramTabBar` itself. Rationale (Phase 1): since iOS 26 the system tab bar
is a floating Liquid Glass bar that cannot be made opaque with a hairline, and hiding it
changes child safe areas differently across iOS 17–27. Each tab is a
`PageNavigationController` (system navigation bar hidden; pages draw their own native
headers) whose root is a `WebPageViewController` for the tab's route. Every tab's stack is
retained for the session; only the selected one is in the view hierarchy.

Default tabs, in Instagram's native order with the Reels slot removed:

| Tab | Route | Notes |
| --- | --- | --- |
| Home | `/?variant=following` | Native header + stories tray; filtered feed |
| Search | `/explore/` | Account search only; idle "caught up" state rendered natively |
| Notifications | `/accounts/activity/` | Replaces Create (decision below) |
| Profile | `/<own username>/` | Avatar glyph; tapping the selected tab scrolls to top, second tap reloads |

**Create tab decision (Phase 1): replaced by Notifications.** m-web has no URL entry
point for creating a post. Its "New post" control is a button in the web bottom nav that
opens a native file picker from JavaScript; the follow-up steps (`/create/style/`,
`/create/details/`) only work with that in-memory selection. Logged-out probes (Oct 2026):
`/create/select/` resolves to the profile of a user named "create", and `/create/style/`
302-redirects to login. Because the web nav is hidden and no route opens the flow, a
native Create tab could only work by script-clicking a hidden control, which is not
reliable. The Router still classifies `/create/...` as `create` and presents it full screen
if Instagram's own content ever navigates there. Revisit if m-web gains a create route.

Notifications and Messages also live in the Home header (native parity) and push onto the
Home stack. Tapping the selected tab: (1) if its page is scrolled down, scroll to top;
(2) otherwise, if pages are pushed, pop to root; (3) otherwise Home, Notifications and
Profile reload with the skeleton (Home also reloads the Stories tray); Search does nothing
more. The Profile tab waits on a skeleton until the bridge reports the signed-in username
(cached between launches) and shows the login page when the session is signed out.

### 3.2 Pages

`WebPageViewController` owns exactly one `WKWebView`, a native header appropriate to its
`PageKind`, a skeleton overlay shown until the page reports `ready`, a `UIRefreshControl`
where the kind supports refresh, and status handling from the bridge.

`PageKind` (derive from URL path in `Router`; keep the table in one place):
`home, search, profile(own), profile(other), post, comments, likes, inbox, thread,
activity, stories, settings, login, create, other`.

Implementation: `RouteKind` + identity in `Sources/Navigation/RouteClassifier.swift`
mirrors `classify` in `Resources/Bridge.js`; both are checked against the single table in
`Tests/route-fixtures.json` (node and Swift checks). Own vs other profile is decided by
comparing the identity with the signed-in username. `blocked` (Reels routes, including
`/<user>/reels/`) is an extra kind that the Router refuses. A page whose content is
Instagram's login (password form or the logged-out landing) is treated as `login`: root
pages hide their native header over it; pushed pages keep the back chevron.

Headers: non-Home pages place the web view below the native header (no CSS reservation
needed); only Home overlays its header on the web view, because it collapses with scroll.

Link interception rule: a navigation inside a page that changes `PageKind`, or targets a
different post/profile than the current page, is cancelled in the web view and performed
natively: **push** for content pages (post, profile, comments, likes, activity, inbox,
thread, settings, other), **present full-screen** for `stories` and `create`, **replace
root** for `login`. Same-page interactions (like, follow, open comment composer, expand
caption, variant toggles) stay in the web view. Reels routes are blocked everywhere.

Back: interactive pop gesture and a native back chevron in the page header. Web
`allowsBackForwardNavigationGestures` is off; history is the navigation stack.

### 3.3 Home specifics

- Header: native `HomeHeaderView` (wordmark, heart, messenger). It collapses on scroll
  down and reappears on scroll up by observing the web view's `scrollView.contentOffset`.
- Stories tray: the Following feed page does not render the tray; today the app overlays a
  separate `storiesWebView` showing the home-variant page's tray with heavy clipping. Keep
  a dedicated stories web view but host it as a proper native component
  (`StoriesTrayHost`) placed under the header and above the feed. The feed page reserves
  room with the existing `[data-instagram-stories-slot]` element. Opening a story presents
  the viewer full-screen (native modal) on top; closing returns to the tray.
- Pull-to-refresh: native `UIRefreshControl`. Keep the current hold-until-ready behaviour
  (header, tray and posts settle together) but implement it inside the page controller.
  Implemented in `WebPageViewController` for Home, Profile, Notifications and Messages: on
  release, a snapshot of the content below the spinner stays up while the document
  reloads; on `ready` the spinner ends and the snapshot (and the Home header) slide up by
  the held distance together, then the snapshot fades. At the top, the Home header moves
  down with the pull so the spinner shows above it.
- Tray placement: `StoriesTrayHost` is a subview of the feed web view's `scrollView` at the
  document position FeedFilter reports for the slot (`storiesSlot`), so it scrolls with
  the posts without per-frame bridge messages. The tray web view keeps a full viewport and
  the host clips it to the measured tray height. The slot's height follows the
  `--native-stories-height` CSS variable set from native.
- Wordmark: the Home header draws Instagram's own wordmark vector, captured from
  `svg[aria-label="Instagram"]` by the tray web view and cached; a text fallback shows
  until the first capture.
- Caught-up card: style the injected card to match native (gradient ring check mark,
  "You're all caught up", secondary text) using CSS in `NativeSkin.css`.

### 3.4 Bridge protocol (`Bridge.js` <-> `WebBridge.swift`)

One message handler name per direction, `instagram` (page -> native). Every message is
`{type, ...}`. Native only accepts messages from the main frame at `https://instagram.com`
or `https://www.instagram.com`. Keep the Swift decoding strict (ignore unknown fields,
drop malformed messages).

| type | payload | when |
| --- | --- | --- |
| `route` | `{path, search, title}` | on load and on every pushState/replaceState/popstate; `title` is the hidden web header's heading (or document title), used for thread/settings titles |
| `navigate` | `{url}` | a link/history change that the Router must perform natively |
| `ready` | `{kind}` | first meaningful content of this PageKind is painted (remove skeleton); `kind` is `login` whenever the content is Instagram's login, whatever the route |
| `status` | existing FeedFilter payload | filter counts and state (unchanged, minus `backgroundRGB`, which moved to `theme`) |
| `theme` | `{backgroundRGB}` | page background to match native surfaces (only the visible page's is applied) |
| `avatar` | `{url, username}` | own profile avatar for the Profile tab icon (CDN URLs only) |
| `storyViewer` | `{open}` | story viewer opened/closed (stories web view only) |
| `storiesTray` | `{height, items}` | tray measured (stories web view only) |
| `storiesSlot` | `{top}` | document position of FeedFilter's stories spacer (Following feed) |
| `searchIdle` | `{idle, top}` | Search is idle (no focus/query); native shows the caught-up state below `top` |
| `wordmark` | `{viewBox, paths}` | Instagram wordmark vector captured for the native Home header (stories web view only) |
| `openControls` | `{}` | user chose the filter settings entry |

Removed (Phase 1): `scroll {y, dy}`. Native observes the web view's
`scrollView.contentOffset` directly (§3.3), which is synchronous and frame-exact, so a
bridge scroll stream would only add latency and message traffic.

Native -> page uses `window.__instagram.policy(json)`, `window.__instagram.refresh()` and
`window.__instagram.layout({headerHeight, storiesHeight, hideChrome})` (CSS variables and
whether web chrome is hidden), all exposed from `Bridge.js`. Per-web-view values that must
exist at document start (role `page`/`tray`, header height, stories slot, policy) are in
`window.__instagramBoot`. The ad-hoc `following-policy-change` event and the
`followingXxx` handler names are gone.

### 3.5 Web content skin (`NativeSkin.css`)

Injected at document start in every page web view. Responsibilities:

- Hide Instagram's HTML header, bottom nav, splash (`#splash-screen`), cookie/app banners
  ("Open in app", "Use the app"), and the Following/For-you variant switcher when the native
  header provides it.
- `-webkit-tap-highlight-color: transparent`, `-webkit-touch-callout: none`,
  `user-select: none` except in inputs/textareas/contenteditable.
- Background colours identical to native surfaces (read from the page and mirrored both
  ways through `theme`).
- Native-parity spacing/sizes for post cards where cheap and robust. Prefer attribute and
  structural selectors over Instagram's hashed class names, which change.
- Reserve top space equal to the native header height via a CSS variable the native side
  sets (`--native-header-height`), rather than `contentInset`, so the web layout is stable.
  Only Home needs it (§3.2 Headers); other pages set it to 0.
- Web chrome is found structurally by `Bridge.js` and marked `data-native-hidden`; the CSS
  hides marked nodes. Every selector and its fallback is in `docs/DOM-NOTES.md`.

### 3.6 Loading and readiness

Each kind has a skeleton (feed cards, profile header+grid, search bar+list, inbox rows).
Show it immediately, hide with a short cross-fade on `ready`, and never let the web view
show its own spinner during that time. Timeouts: show a native "Couldn't load, tap to
retry" state after 20 s. Web content process termination reloads the page with the skeleton
up.

## 4. Conventions

- Swift: `@MainActor` for anything touching WebKit or UIKit. No force unwraps outside
  `Bundle` resource loading. Small files, one type per file, doc comment on each type.
- JS: ES2020, no build step, no dependencies. Every JS behaviour change has a node test in
  `Tests/`. Keep `FeedFilter.js` exporting its pure functions for tests.
- Selectors: document every Instagram DOM assumption in `docs/DOM-NOTES.md` with the
  selector, what it finds, and the fallback when it fails.
- Diagnostics: DEBUG only, counts and enumerated reasons only. Never log usernames, post
  content, cookies, or request bodies.
- Commits: small, imperative subject, body says *why*. Run the checks in §5 before every
  commit.

## 5. Checks (run before every commit)

```sh
node --test Tests/*.test.cjs
swiftc -module-cache-path "$TMPDIR/ig-mc" Sources/Filter/FollowingPolicy.swift Sources/Navigation/RouteClassifier.swift \
  Sources/Navigation/RouteDecision.swift Sources/Support/SVGPath.swift Tests/*.swift -o "$TMPDIR/ig-policy" && "$TMPDIR/ig-policy"
xcodebuild -project Following.xcodeproj -scheme Following -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$TMPDIR/ig-build" CODE_SIGNING_ALLOWED=NO build
```

Simulator smoke (a booted iPhone simulator is available via `xcrun simctl`): install the
Debug build, launch, take a screenshot of the login page inside the native shell and of
each tab's skeleton. DEBUG builds read `SHELL_TAB`, `SHELL_SKELETON_PREVIEW=1` and
`SHELL_OPEN_URL` (pass as `SIMCTL_CHILD_…` to `xcrun simctl launch`) to start on a tab,
hold every page on its skeleton, or open a URL through the Router
(`Sources/Support/DebugLaunchOptions.swift`). The first launch after a fresh install
spends several seconds starting WebKit before the first navigation; measure timing on a
second launch. Agents cannot sign in to Instagram; signed-in flows are validated by
the owner on device, so log what needs device validation in `docs/DEVICE-CHECKLIST.md`.

## 6. Phases

1. **Foundation** — native shell, pages, router, bridge, skin, skeletons, Home header and
   stories hosting, filter preserved. One architect agent.
2. **Fidelity (parallel)** — Home feed polish; navigation and transitions; Search and
   Profile tabs; hardening and tests.
3. **Integration review** — director review, simplification pass, device checklist, PR.
