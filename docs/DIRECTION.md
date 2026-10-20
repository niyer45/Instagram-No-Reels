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
  App/            AppDelegate/SceneDelegate (UIKit lifecycle), AppEnvironment
  Shell/          RootTabBarController, TabItem, InstagramTabBar (styling, avatar item)
  Navigation/     Router (URL -> PageKind -> presentation), PageKind, link interception
  Pages/          WebPageViewController (one per page), per-kind header views,
                  HomeHeaderView, StoriesTrayHost, SkeletonView(s)
  Web/            WebPageFactory (WKWebView construction, shared config), WebBridge
                  (typed messages), UserScripts (loads Resources/*.js|css)
  Filter/         FollowingPolicy.swift (unchanged), filter status model
  Support/        Haptics, Theme (colors, hairline), Diagnostics (DEBUG only)
Resources/
  FeedFilter.js   post filtering (observe-only), status messages
  Bridge.js       route/scroll/ready/avatar/story-viewer messages to native
  NativeSkin.css  hides web chrome, native parity styling of web content
Tests/            node tests (.cjs) for JS; Swift checks compiled with swiftc
```

### 3.1 Tabs

`RootTabBarController: UITabBarController`. Each tab is a `UINavigationController`
(system navigation bar hidden; pages draw their own native headers) whose root is a
`WebPageViewController` for the tab's route.

Default tabs, in Instagram's native order with the Reels slot removed:

| Tab | Route | Notes |
| --- | --- | --- |
| Home | `/?variant=following` | Native header + stories tray; filtered feed |
| Search | `/explore/` | Account search only; idle "caught up" state rendered natively |
| Create | web "new post" flow | Investigate m-web's create entry point. If no reliable entry exists, replace with Notifications (`/accounts/activity/`). Record the finding here. |
| Profile | `/<own username>/` | Avatar glyph; tapping the selected tab scrolls to top, second tap reloads |

Notifications and Messages live in the Home header (native parity) and push onto the Home
stack. Tapping the selected tab scrolls that tab's page to top (native behaviour); tapping
again at top pops to root / reloads where documented.

### 3.2 Pages

`WebPageViewController` owns exactly one `WKWebView`, a native header appropriate to its
`PageKind`, a skeleton overlay shown until the page reports `ready`, a `UIRefreshControl`
where the kind supports refresh, and status handling from the bridge.

`PageKind` (derive from URL path in `Router`; keep the table in one place):
`home, search, profile(own), profile(other), post, comments, likes, inbox, thread,
activity, stories, settings, login, create, other`.

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
- Caught-up card: style the injected card to match native (gradient ring check mark,
  "You're all caught up", secondary text) using CSS in `NativeSkin.css`.

### 3.4 Bridge protocol (`Bridge.js` <-> `WebBridge.swift`)

One message handler name per direction, `instagram` (page -> native). Every message is
`{type, ...}`. Native only accepts messages from the main frame at `https://instagram.com`
or `https://www.instagram.com`. Keep the Swift decoding strict (ignore unknown fields,
drop malformed messages).

| type | payload | when |
| --- | --- | --- |
| `route` | `{path, search}` | on load and on every pushState/replaceState/popstate |
| `navigate` | `{url}` | a link/history change that the Router must perform natively |
| `ready` | `{kind}` | first meaningful content of this PageKind is painted (remove skeleton) |
| `scroll` | `{y, dy}` | throttled to animation frames, for header collapse |
| `status` | existing FeedFilter payload | filter counts and state (unchanged) |
| `theme` | `{backgroundRGB}` | page background to match native surfaces |
| `avatar` | `{url, username}` | own profile avatar for the Profile tab icon |
| `storyViewer` | `{open}` | story viewer opened/closed |
| `storiesTray` | `{height, items}` | tray measured (stories web view only) |
| `openControls` | `{}` | user chose the filter settings entry |

Native -> page uses `window.__instagram.policy(json)` and `window.__instagram.refresh()`;
expose both from `Bridge.js`. Replace the ad-hoc `following-policy-change` event and the
many `followingXxx` handler names with this protocol. Update tests accordingly.

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
swiftc -module-cache-path "$TMPDIR/ig-mc" Sources/Filter/FollowingPolicy.swift Tests/PolicyTests.swift -o "$TMPDIR/ig-policy" && "$TMPDIR/ig-policy"
xcodebuild -project Following.xcodeproj -scheme Following -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$TMPDIR/ig-build" CODE_SIGNING_ALLOWED=NO build
```

Simulator smoke (a booted iPhone simulator is available via `xcrun simctl`): install the
Debug build, launch, take a screenshot of the login page inside the native shell and of
each tab's skeleton. Agents cannot sign in to Instagram; signed-in flows are validated by
the owner on device, so log what needs device validation in `docs/DEVICE-CHECKLIST.md`.

## 6. Phases

1. **Foundation** — native shell, pages, router, bridge, skin, skeletons, Home header and
   stories hosting, filter preserved. One architect agent.
2. **Fidelity (parallel)** — Home feed polish; navigation and transitions; Search and
   Profile tabs; hardening and tests.
3. **Integration review** — director review, simplification pass, device checklist, PR.
