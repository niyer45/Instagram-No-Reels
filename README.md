# Instagram No Reels

A personal iOS app that uses Instagram’s original mobile website, with a quieter Home feed and no recognized Reels, ads, or suggested posts.

Sign in with your existing Instagram account through Instagram’s own page. This is a native UIKit/WebKit companion, not a modified Instagram IPA or a reconstruction of its native app. It is an unofficial project and is not affiliated with Instagram or Meta.

## Features

- **Native shell:** Instagram-style native tab bar, headers, push navigation with swipe-back, skeleton loading and pull-to-refresh around Instagram’s own pages.
- **Following-first Home:** native Home header with Instagram’s wordmark, and Instagram’s Stories tray above posts from followed accounts.
- **Local content filters:** hides recognized Reels, ads, suggestions, and Home posts without followed-account evidence.
- **Stories and Messages:** Instagram’s signed-in story viewer opens full screen; Notifications push from the Home header heart (with an unread dot).
- **Account search:** preserves Instagram’s search bar and account results while hiding the Explore media grid. A native caught-up state appears only while Search is idle and disappears on interaction or focus.
- **Retained tabs:** Home, Search, Messages and your Profile keep their pages and scroll positions during tab visits. Tapping the selected tab scrolls to top, then pops to its root, then reloads.
- **Stable refresh:** pull-to-refresh holds the released pull distance until the replacement feed is ready, then settles the header, Stories, and posts together.
- **Fast start:** Home’s web view starts loading before the interface is built; the branded splash waits only for Home and is never shown again during navigation. Instagram’s website splash is suppressed.
- **Offline and failures:** a native “No internet connection” banner slides in under the header while offline; a page that fails shows Instagram-style “Couldn’t refresh feed” / “Couldn’t load …” text with Retry, and retries by itself when the connection returns.
- **Foreground refresh:** returning after 30 minutes or more refreshes Home like the native app; shorter visits leave every page and scroll position as they were.
- **Light on memory:** only the top four pages of a stack keep their web documents, and pages that are off screen unload on a memory warning; both come back from a snapshot when shown again, Home at its previous scroll position where possible.
- **Dark appearance:** original dark app icon, launch graphics, and backgrounds matched to Instagram’s page.

Home initially filters recognized posts older than two days. An inline caught-up message can reveal older followed-account content, and downward scrolling near the cutoff can continue into older posts. Intentional profile and post-detail browsing does not apply Home’s following-membership or two-day restriction.

## Requirements

- macOS and Xcode with an iOS 17 or newer SDK.
- An iPhone running iOS 17 or later for device installation.
- An Apple signing team configured in Xcode.
- Node.js 18 or newer for the JavaScript checks.

No Instagram API key or separate backend is required. The app uses the signed-in website and its existing page responses.

## Run on your iPhone

```sh
git clone https://github.com/niyer45/Instagram-No-Reels.git
cd Instagram-No-Reels
open Following.xcodeproj
```

1. Select the **Following** target and open **Signing & Capabilities**.
2. Choose your signing team. The repository intentionally leaves the development team unset.
3. For a new installation, choose an appropriate unique bundle identifier if your signing configuration requires one.
4. Select your connected iPhone and run the **Following** scheme.
5. Sign in directly on Instagram’s page inside the app.

The internal target and scheme are named `Following`; the installed app displays as **Instagram**. If you are updating the existing personal build, keep its signing team and `com.local.following` bundle identifier to preserve the same installation and WebKit login storage.

## How it works

The shell is UIKit; Instagram’s mobile website supplies only the content. Each page is a `WebPageViewController` that owns one `WKWebView` (all sharing the persistent default website data store) plus native chrome:

| Part | Purpose |
| --- | --- |
| Tab shell | Home, Search, Messages and Profile, each a navigation stack retained for the session, with a native Instagram-style tab bar showing your avatar. |
| Router | Classifies every URL (`Sources/Navigation/RouteClassifier.swift`, mirrored in `Resources/Bridge.js`) and pushes content pages, presents Stories full screen, switches tabs, replaces the root with Instagram’s login page, or blocks Reels. |
| Pages | Native headers (back chevron and title, or Home’s wordmark and heart), skeletons until the page is ready, a retry state after a failed load or 20 seconds, the offline banner, and pull-to-refresh that holds until the new page is ready. |
| Launch | `AppDelegate` creates the shared `AppEnvironment` and starts Home’s web view and request before the scene connects; Home’s page adopts that web view. Debug builds record launch milestones (`Tools/launch-timing.sh`). |
| Recovery | `Connectivity` (`NWPathMonitor`) drives the offline banner and automatic retry; a terminated web-content process reloads behind the skeleton; deep or hidden pages unload behind a snapshot and reload when shown. |
| Home | A collapsing native header, Instagram’s Stories tray hosted from a dedicated web view inside the feed’s scroll view, and the story viewer presented full screen. |
| Bridge | `Resources/Bridge.js` reports routes, readiness, theme, avatar and tray geometry through one `instagram` message handler; native accepts messages only from Instagram’s main frame and decodes them strictly. |
| Skin | `Resources/NativeSkin.css` hides Instagram’s web header, bottom nav, website splash and app banners, and removes tap highlights and long-press callouts. |

`Resources/FeedFilter.js` runs at document start. It observes Instagram’s initial JSON and existing fetch/XHR responses, associates post cards with author and follow-state evidence, and filters individual cards. It does not construct guessed private API requests or read passwords or session cookies.

Follow evidence includes `friendship_status.following`, `is_following`, and `followed_by_viewer`. Follower counts and `follows_viewer` do not establish that you follow an account. If the page does not supply sufficient membership data, **Content filters** (from Instagram’s settings menu or the Profile menu) can import a `following.json` file from your Instagram information export as a fallback. Fresh negative follow evidence takes priority over an older import.

The login session remains in WebKit’s persistent website data store. There is no app-owned credential form or remote application backend. Design rules and the bridge protocol are in [`docs/DIRECTION.md`](docs/DIRECTION.md); Instagram markup assumptions are in [`docs/DOM-NOTES.md`](docs/DOM-NOTES.md).

## Checks

One script runs every check and prints one line each, exiting non-zero on any failure:

```sh
Tools/check.sh             # node tests, Swift checks, unsigned Debug simulator build (no warnings allowed)
Tools/check.sh --no-build  # node tests and Swift checks only
```

- **node:** the JavaScript filter, bridge, theme-sampling, Story-navigation and Search/Notifications/Profile tab tests (`Tests/*.test.cjs`).
- **swift:** the import, navigation-policy, route-table and SVG-path checks, compiled with `swiftc` from the source list at the top of `Tools/check.sh`.
- **build:** `xcodebuild` Debug for the simulator with `CODE_SIGNING_ALLOWED=NO`.

Logs, the module cache and derived data go to `$CHECK_TMP` (default `$TMPDIR/ig-check`). The script needs only Node.js, `swiftc` and `xcodebuild`.

With a booted simulator, after `Tools/check.sh`:

```sh
Tools/simshots.sh <simulator-udid> [output-dir]    # every tab, its skeleton, a pushed page, failure and offline states
Tools/launch-timing.sh <simulator-udid> [runs]     # fresh-install and warm launch-to-ready timings
Tools/sim-memory.sh <simulator-udid>               # resident memory of the app and its WebKit processes
```

These use Debug-only launch environment values (`SHELL_TAB`, `SHELL_SKELETON_PREVIEW`, `SHELL_FAILURE_PREVIEW`, `SHELL_OPEN_URL(S)`, `SHELL_OFFLINE`, `SHELL_MEMORY_WARNING`, `SHELL_STALE_AFTER`, `SHELL_POP`, `SHELL_PRESENT`, and Home's fixture harness `SHELL_HOME_FIXTURE`/`SHELL_HOME_DEMO`; see `Sources/Support/DebugLaunchOptions.swift`); Release builds exclude them. Debug builds also keep local diagnostics files (filter events and launch milestones) with counts, timings and enumerated reasons only, plus sanitized Home page outlines (`page-outline-<capture>-<n>.json`, structure only, last 12) that you can pull from a device with `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer --domain-identifier com.local.following --source Library/Caches --destination <dir>`.

The simulator cannot sign in to Instagram, so signed-in behaviour is validated on device with [`docs/DEVICE-CHECKLIST.md`](docs/DEVICE-CHECKLIST.md). Sanitized results for 0.4.x in [`Evidence/`](Evidence/) cover the previous architecture.

## Limitations

- Instagram can change its website, markup, routing, and response schemas. Filtering and presentation may need updates.
- Recognition is evidence-based rather than a guarantee that every ad, Reel, or recommendation format is covered. Unrecognized posts and videos can be hidden conservatively.
- The caught-up feed marker requires dated eligible content. Missing timestamps or a network failure do not prove that all recent posts have loaded.
- Pagination uses Instagram’s existing page handlers and available content; it cannot guarantee an unlimited feed.
- Live tab state is retained within the running app session. A terminated web-content process reloads the page behind its skeleton, and a page unloaded to save memory reloads when shown; Instagram may then show newer content than before, and the scroll position is restored only as far as the reloaded page reaches.
- Instagram’s website has no create-post route, so the native Create tab is replaced by Messages.

## Project layout

```text
Following.xcodeproj/   Xcode project (folder-synchronized Sources/ and Resources/) and shared scheme
Sources/App/           UIKit app and scene delegates, shared environment, account store
Sources/Shell/         Tab container, tab bar, tabs, startup splash
Sources/Navigation/    Router, route classification and navigation decisions
Sources/Pages/         Page controllers, headers, Home, Stories tray, skeleton and state views
Sources/Web/           Web view factory, typed bridge, user scripts
Sources/Filter/        Following import/navigation policy, filter status, Content filters sheet
Sources/Support/       Theme, connectivity, glyphs, SVG path parser, haptics, diagnostics, DEBUG launch hooks
Resources/             Feed filter, bridge, native skin, app configuration, icons
Tests/                 JavaScript and Swift regression checks, shared route fixtures
Tools/                 check.sh (all checks), simshots.sh (simulator screenshots), launch-timing.sh, sim-memory.sh
docs/                  Program direction, DOM notes, device checklist
Evidence/              Sanitized device-check results from 0.4.x
```

The icon and launch graphics were extracted from the user-supplied Instagram IPA. The native Search caught-up state adapts the reference documented in [`Evidence/Search-image-reference.md`](Evidence/Search-image-reference.md). Instagram branding remains the property of its respective owners. The original IPA, encrypted native executable, signing credentials, account session, and local build output are not included.
