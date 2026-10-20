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
                  PageNavigationController, ModalContainerController
  Pages/          WebPageViewController (one per page), HomePageViewController,
                  SearchPageViewController, ProfilePageViewController (+ ProfileHeaderView),
                  PageHeaderView, HomeHeaderView, Wordmark*, StoriesTrayHost,
                  StoryViewerController, SkeletonView, LoadFailureView, OfflineBanner,
                  SearchIdleView, HomeDemo (DEBUG fixture harness)
  Web/            WebPageFactory (WKWebView construction, shared config), WebBridge
                  + BridgeMessage (typed messages), UserScripts (loads Resources/*.js|css)
  Filter/         FollowingPolicy.swift (unchanged), FollowingStore, FilterStatus(+Payload),
                  ContentFilterSettingsView
  Support/        Haptics, Theme (colors, hairline), Glyphs + SVGPath, Diagnostics,
                  Connectivity, DebugLaunchOptions (DEBUG only)
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
| Messages | `/direct/inbox/` | Messenger glyph; title is the signed-in username; threads and the composer hide the tab bar; replaces Create (decision below) |
| Profile | `/<own username>/` | Avatar glyph; tapping the selected tab scrolls to top, second tap reloads |

**Create tab decision (Phase 1): replaced by Messages.** Notifications moved to the Home header only (owner's choice, cycle 1). m-web has no URL entry
point for creating a post. Its "New post" control is a button in the web bottom nav that
opens a native file picker from JavaScript; the follow-up steps (`/create/style/`,
`/create/details/`) only work with that in-memory selection. Logged-out probes (Oct 2026):
`/create/select/` resolves to the profile of a user named "create", and `/create/style/`
302-redirects to login. Because the web nav is hidden and no route opens the flow, a
native Create tab could only work by script-clicking a hidden control, which is not
reliable. The Router still classifies `/create/...` as `create` and presents it full screen
if Instagram's own content ever navigates there. Revisit if m-web gains a create route.

Notifications lives in the Home header heart (it pushes on the Home stack and carries the
unread dot); the header Messenger icon switches to the Messages tab. Tapping the selected tab: (1) if its page is scrolled down, scroll to top;
(2) otherwise, if pages are pushed, pop to root; (3) otherwise Home, Messages and
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
`/<user>/reels/`) is an extra kind that the Router refuses silently. Keyword search results
(`/explore/search/keyword/`), Discover people (`/explore/people/`), hashtag and location pages
are `other` (pushed), not the Search tab. Native titles come from one table,
`Route.title(query:webTitle:ownUsername:)`, fixture-checked like the kinds. A page whose content is
Instagram's login (password form or the logged-out landing) is treated as `login`: root
pages hide their native header over it; pushed pages keep the back chevron.

Headers: non-Home pages place the web view below the native header (no CSS reservation
needed); only Home overlays its header on the web view, because it collapses with scroll.

Link interception rule: a navigation inside a page that changes `PageKind`, or targets a
different post/profile than the current page, is cancelled in the web view and performed
natively: **push** for content pages (post, profile, comments, likes, activity, settings,
other), **go to the Messages tab** for inbox (tab switch to its root) and thread and other
`/direct/` pages (push on the Messages stack, switching to it first), **present full-screen** for `stories` and `create`, **replace
root** for `login`. Same-page interactions (like, follow, open comment composer, expand
caption, variant toggles) stay in the web view. Links are decided in the window's capturing
click phase, before Instagram's own handlers.

Phase 2 decisions (changed with the code; rationale in each line):

- Full-screen pages are presented **over the current page** through `ModalContainerController`
  (`Sources/Navigation/ModalContainerController.swift`): status bar and home indicator hidden,
  a downward swipe that follows the finger dismisses, and Instagram's own close control
  dismisses through its route change. The page underneath never leaves the hierarchy, so it is
  not reloaded. Home's story viewer uses the same container (§3.3), so there is one modal
  mechanism.
- **External links** (other sites) open in `SFSafariViewController` over the current page, as
  in the native app; Instagram's `l.instagram.com` link shim is unwrapped to its target;
  `mailto:`/`tel:` go to the system; App Store, `instagram://` and other app redirects and
  scripted redirects are dropped silently. Facebook sign-in from the login page shows one
  explanation (it cannot sign this app in).
- **Reels are dropped silently** everywhere (links, the profile Reels tab, history changes);
  the Phase 1 "Reels are disabled" and "External links … disabled" alerts are gone, because
  the native app has no such alerts and they interrupted ordinary taps.
- Message threads and the new-message composer hide the shared tab bar while they are in the
  stack (like `hidesBottomBarWhenPushed`); `RootTabBarController.tabBar` is the one reference.
- Sign-in is evidence-based (`SessionEvidence`): a ready signed-in-only page, the avatar or the
  filtered feed marks the session signed in; only actual sign-in routes (`/accounts/login`,
  `emailsignup`, `signup`, `password/reset`, `onetap`, `logout`, `/challenge`, `/checkpoint`,
  `/consent`, `/oauth`, `/two_factor`) count as login, in Bridge.js, RouteClassifier and
  FeedFilter alike, so Notifications (`/accounts/activity/`) and settings keep their headers.

Back: interactive pop from the left screen edge only (iOS 26's full-width content swipe is
off, so it cannot fight carousels or the Stories tray) and a native back chevron in the page
header. Web `allowsBackForwardNavigationGestures` is off; history is the navigation stack.

### 3.3 Home specifics

- Header: native `HomeHeaderView` (wordmark, heart, messenger). It collapses on scroll
  down and reappears on scroll up by observing the web view's `scrollView.contentOffset`.
- Stories tray: the Following feed page does not render the tray; today the app overlays a
  separate `storiesWebView` showing the home-variant page's tray with heavy clipping. Keep
  a dedicated stories web view but host it as a proper native component
  (`StoriesTrayHost`) placed under the header and above the feed. The feed page reserves
  room with the existing `[data-instagram-stories-slot]` element. Opening a story presents
  `StoryViewerController` (hosting the tray web view) inside `ModalContainerController`
  (§3.2); the container's downward swipe and the viewer's left-edge swipe call Bridge.js
  `window.__instagramTray.closeViewer()`, which clicks Instagram's Close control (else
  `history.back()`), and the page's `storyViewer` closed message dismisses it; closing
  returns to the tray.
- Pull-to-refresh: native `UIRefreshControl`. Keep the current hold-until-ready behaviour
  (header, tray and posts settle together) but implement it inside the page controller.
  Implemented in `WebPageViewController` for Home, Profile, Notifications and Messages: on
  release, a snapshot of the content below the spinner stays up while the document
  reloads; on `ready` the spinner ends and the snapshot (and the Home header) slide up by
  the held distance together, then the snapshot fades. While pulling, the Home header stays
  put and the spinner shows in the gap below it. The reloading document is never visible
  before `ready`: native sets boot/layout `refreshing` before `reload()`, `NativeSkin.css`
  makes `html[data-native-refreshing] body` transparent (the page colour still paints; a
  25 s failsafe in `Bridge.js` clears it), and native clears it on `ready` (and on every
  cancel path) before the settle starts. The live tray host is hidden (alpha 0) while the
  snapshot shows the previous tray, and returns at settle. Instagram's own stories row in
  the feed document (`data-native-stories-row`) is hidden whenever the native tray is active
  (`html[data-native-stories="tray"]`), so there is never a second row (Phase 2: the native app does this; the
  Phase 1 header sliding down under the spinner did not match).
- Tray placement: `StoriesTrayHost` is a subview of the feed web view's `scrollView` at the
  document position FeedFilter reports for the slot (`storiesSlot`), so it scrolls with
  the posts without per-frame bridge messages. The tray web view keeps a full viewport and
  the host clips it to the measured tray height. The slot's height follows the
  `--native-stories-height` CSS variable set from native.
- Wordmark: the Home header draws Instagram's own wordmark vector, captured from
  `svg[aria-label="Instagram"]` by the tray web view and cached; a text fallback shows
  until the first capture.
- Caught-up card: style the injected card to match native (gradient ring check mark,
  "You're all caught up", secondary text, blue "View older posts") in the `/* === Home === */`
  block of `NativeSkin.css`, which also skins approved Following-feed post cards.

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
`window.__instagram.layout({headerHeight, storiesHeight, hideChrome, refreshing})` (CSS variables,
whether web chrome is hidden, and whether the reloading document is held invisible for a
refresh), all exposed from `Bridge.js`. Per-web-view values that must
exist at document start (role `page`/`tray`, header height, stories slot and height, `refreshing`, policy) are in
`window.__instagramBoot`. Phase 2 adds `window.__instagramTray.closeViewer()` (tray web view)
and `window.__instagramTabs` (`switchAccount`, `unread`, `cancelSearch`, `hasSearchField`) for
the Home story viewer and the Search, Notifications and Profile tabs; no new message types.
The ad-hoc `following-policy-change` event and the
`followingXxx` handler names are gone.

### 3.5 Web content skin (`NativeSkin.css`)

Injected at document start in every page web view. Responsibilities:

- Hide Instagram's HTML header, bottom nav, splash (`#splash-screen`), cookie/app banners
  ("Open in app", "Use the app"), and the Following/For-you variant switcher when the native
  header provides it.
- `-webkit-tap-highlight-color: transparent`, `-webkit-touch-callout: none`,
  `user-select: none` except in inputs/textareas/contenteditable.
- Background colours identical to native surfaces: the page's colour is sampled and sent
  through `theme`, and native surfaces and the window style follow it. The page's own colour
  scheme (`prefers-color-scheme`) is never derived from that sample: every web view's
  `overrideUserInterfaceStyle` is the app appearance the scene reports (Dark via Info.plist),
  because inheriting the window style made one light sample keep Instagram light (Phase 2
  integration).
- Native-parity spacing/sizes for post cards where cheap and robust. Prefer attribute and
  structural selectors over Instagram's hashed class names, which change.
- Reserve top space equal to the native header height via a CSS variable the native side
  sets (`--native-header-height`), rather than `contentInset`, so the web layout is stable.
  Only Home needs it (§3.2 Headers); other pages set it to 0. Instagram's own reservation for
  its fixed top bar (padding-top on the element after it) is collapsed when the bar is hidden.
- Web chrome is found structurally by `Bridge.js` and marked `data-native-hidden`; the CSS
  hides marked nodes. Every selector and its fallback is in `docs/DOM-NOTES.md`.

### 3.6 Loading and readiness

Each kind has a skeleton (feed cards, profile header+grid, search bar+list, inbox rows).
Show it immediately, hide with a short cross-fade on `ready`, and never let the web view
show its own spinner during that time. Timeouts and failures: after 20 s, or when the load
fails, show a native failure view worded like Instagram's ("Couldn't refresh feed" on Home,
"Couldn't load profile" / "Couldn't load …" elsewhere, saying when the device is offline) with
a blue **Retry** button (Phase 2: replaces "Couldn't load, tap to retry"). While offline a
"No internet connection" banner slides in under the header, and failed or waiting pages retry
by themselves on reconnect. Web content process termination reloads the page with the
skeleton up. Only the top four pages of a stack keep their documents; deeper pages, and pages
off screen at a memory warning, unload behind a snapshot and reload when shown.

## 4. Conventions

- Swift: `@MainActor` for anything touching WebKit or UIKit. No force unwraps outside
  `Bundle` resource loading. Small files, one type per file, doc comment on each type.
- JS: ES2020, no build step, no dependencies. Every JS behaviour change has a node test in
  `Tests/`. Keep `FeedFilter.js` exporting its pure functions for tests.
- Selectors: document every Instagram DOM assumption in `docs/DOM-NOTES.md` with the
  selector, what it finds, and the fallback when it fails.
- Diagnostics: DEBUG only, counts and enumerated reasons only. Never log usernames, post
  content, cookies, or request bodies. DEBUG builds also write sanitized Home page
  outlines (`Library/Caches/page-outline-<capture>-<n>.json`, last 6; captures `ready`,
  `ready-3s`, `refresh-start`, `refresh-loading`, `refresh-end`, `scrolled`) with structure only:
  tags, roles, allowlisted ARIA labels, our data-* names, positions, rects and href shapes; no
  text, URLs or usernames (`hrefShape`, `outlineTree` in Bridge.js, tested in `Tests/outline.test.cjs`).
- Commits: small, imperative subject, body says *why*. Run the checks in §5 before every
  commit.

## 5. Checks (run before every commit)

```sh
CHECK_TMP=<scratch dir> Tools/check.sh
```

It runs, each reported on one line, and exits non-zero if any fails:

- `node --test Tests/*.test.cjs`;
- the Swift checks: `swiftc` over the pure sources listed once at the top of `Tools/check.sh`
  plus `Tests/*.swift`, then the resulting binary;
- the Debug simulator build (`xcodebuild … -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO`),
  which fails on any compiler warning.

Logs, module cache and derived data go to `$CHECK_TMP` (default `$TMPDIR/ig-check`; pass an
explicit path where `$TMPDIR` is unavailable). `--no-build` skips the build. The script does
not use git.

Simulator smoke (a booted iPhone simulator is available via `xcrun simctl`):
`Tools/simshots.sh <udid> [dir]` installs the Debug build and captures every tab live and on its
skeleton, a pushed page, the failure state and the offline banner. DEBUG builds read `SHELL_TAB`,
`SHELL_SKELETON_PREVIEW=1`, `SHELL_FAILURE_PREVIEW=1`, `SHELL_OPEN_URL`, `SHELL_OPEN_URLS`,
`SHELL_OFFLINE`, `SHELL_MEMORY_WARNING`, `SHELL_STALE_AFTER`, `SHELL_POP`, `SHELL_PRESENT` and
Home's fixture harness `SHELL_HOME_FIXTURE`/`SHELL_HOME_DEMO` (passed as `SIMCTL_CHILD_…` to
`xcrun simctl launch`; `Sources/Support/DebugLaunchOptions.swift`). `Tools/sim-memory.sh <udid>` prints the app's and its
WebKit processes' resident memory (host RSS; compare runs on one machine only). `Tools/launch-timing.sh
<udid> [runs]` reinstalls the app and prints launch milestones for a fresh-install launch and
warm launches; the first launch after a fresh install spends several seconds starting WebKit,
and timings on a loaded machine vary widely, so compare builds in alternating runs. Agents
cannot sign in to Instagram; signed-in flows are validated by the owner on device, so log what
needs device validation in `docs/DEVICE-CHECKLIST.md`.

## 6. Phases

1. **Foundation** — native shell, pages, router, bridge, skin, skeletons, Home header and
   stories hosting, filter preserved. One architect agent.
2. **Fidelity (parallel)** — Home feed polish; navigation and transitions; Search and
   Profile tabs; hardening and tests.
3. **Integration review** — director review, simplification pass, device checklist, PR.
