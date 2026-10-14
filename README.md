# Instagram No Reels

A personal iOS app that uses Instagram’s original mobile website, with a quieter Home feed and no recognized Reels, ads, or suggested posts.

Sign in with your existing Instagram account through Instagram’s own page. This is a SwiftUI/WebKit companion, not a modified Instagram IPA or a reconstruction of its native app. It is an unofficial project and is not affiliated with Instagram or Meta.

## Features

- **Following-first Home:** Instagram’s original Home header and Stories above posts from followed accounts.
- **Local content filters:** hides recognized Reels, ads, suggestions, and Home posts without followed-account evidence.
- **Stories and Messages:** keeps the original signed-in interfaces available.
- **Account search:** preserves Instagram’s search bar and account results while hiding the Explore media grid. A static dark caught-up graphic appears only while Search is idle and disappears on interaction or focus.
- **Retained tabs:** Home, Search, and your Profile keep their live pages and scroll positions during tab visits. Tapping Profile again while it is already selected explicitly reloads it.
- **Stable refresh:** pull-to-refresh holds the released pull distance until the replacement feed is ready, then settles the header, Stories, and posts together.
- **Startup-only splash:** the branded splash is reserved for initial app loading; Instagram’s website splash is suppressed during navigation.
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

SwiftUI hosts persistent `WKWebView` instances with a shared website data store:

| View | Purpose |
| --- | --- |
| Home | Retains the Following feed, loaded posts, and scroll position. |
| Header and Stories | Presents the original Home header and signed-in Story viewer. |
| Search | Retains account search and waits for the original search bar to stabilize before its first reveal. |
| Profile | Retains your own Profile; a repeated active-tab tap reloads it. |
| Other browsing | Opens Messages, individual posts, other profiles, and account pages. |

`Resources/FeedFilter.js` runs at document start. It observes Instagram’s initial JSON and existing fetch/XHR responses, associates post cards with author and follow-state evidence, and filters individual cards. It does not construct guessed private API requests or read passwords or session cookies.

Follow evidence includes `friendship_status.following`, `is_following`, and `followed_by_viewer`. Follower counts and `follows_viewer` do not establish that you follow an account. If the page does not supply sufficient membership data, **Content filters** can import a `following.json` file from your Instagram information export as a fallback. Fresh negative follow evidence takes priority over an older import.

The login session remains in WebKit’s persistent website data store. There is no app-owned credential form or remote application backend.

## Checks

Run the JavaScript feed and Story-navigation checks:

```sh
node --test Tests/feed-filter.test.cjs Tests/story-navigation.test.cjs
```

Run the Swift import and navigation-policy checks:

```sh
swiftc -module-cache-path /tmp/instagram-module-cache \
  Sources/FollowingPolicy.swift Tests/PolicyTests.swift \
  -o /tmp/instagram-policy-tests
/tmp/instagram-policy-tests
```

Build an unsigned simulator version:

```sh
xcodebuild -project Following.xcodeproj -scheme Following \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/instagram-build \
  CODE_SIGNING_ALLOWED=NO build
```

Version **0.4.5** has **53 JavaScript checks** and **38 Swift policy checks**. Debug device and Release simulator builds were validated during development. Sanitized device results in [`Evidence/`](Evidence/) cover retained tabs, first-post preservation, Profile reloading, Search readiness, splash suppression, and refresh hold/settling.

Debug builds support optional `FOLLOWING_ROUTE_CHECK` and `FOLLOWING_REFRESH_CHECK` launch flags for device diagnostics. These checks navigate tabs and may save local UI snapshots and JSON results in the app’s cache. Normal launches do not run them; Release builds exclude the diagnostic runners.

## Limitations

- Instagram can change its website, markup, routing, and response schemas. Filtering and presentation may need updates.
- Recognition is evidence-based rather than a guarantee that every ad, Reel, or recommendation format is covered. Unrecognized posts and videos can be hidden conservatively.
- The caught-up feed marker requires dated eligible content. Missing timestamps or a network failure do not prove that all recent posts have loaded.
- Pagination uses Instagram’s existing page handlers and available content; it cannot guarantee an unlimited feed.
- Live tab state is retained within the running app session. A terminated web-content process may require a page to load again.

## Project layout

```text
Following.xcodeproj/   Xcode project and shared scheme
Sources/              SwiftUI views, WebKit session, navigation/import policy
Resources/            Feed filter, app configuration, icons and static Search image
Tests/                JavaScript and Swift regression checks
Evidence/             Sanitized device-check results and image-reference notes
```

The icon and launch graphics were extracted from the user-supplied Instagram IPA. The static Search graphic is a dark vector adaptation of the reference documented in [`Evidence/Search-image-reference.md`](Evidence/Search-image-reference.md). Instagram branding remains the property of its respective owners. The original IPA, encrypted native executable, signing credentials, account session, and local build output are not included.
