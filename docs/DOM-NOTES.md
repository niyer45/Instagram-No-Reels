# Instagram DOM notes

Every assumption the app makes about Instagram's mobile website (m-web) markup, what it
finds, and what happens when it stops matching. Instagram's class names are hashed and
change often, so nothing here depends on them; we rely on routes, ARIA labels, element
roles, text and geometry.

Status legend: **seen** = observed in this repository's simulator runs (logged-out pages
only, Oct 2026); **inherited** = relied on by the 0.4.x app on a signed-in device;
**assumed** = not yet observed, needs the device checklist.

## Web chrome hidden by `Bridge.js` + `NativeSkin.css`

| What | Selector / rule | Found | Fallback when it fails |
| --- | --- | --- | --- |
| Website splash | `#splash-screen` → `display:none` | inherited | Native skeleton still covers the page until `ready`. |
| Bottom tab bar | Seed `a[href="/explore/"]` (relative or absolute); climb ≤ 8 ancestors, keep the **outermost** one that is 0–130 px tall, starts below 60 % of the viewport, contains a link to `/` and no `main`/`article`. Marked `data-native-hidden="tabbar"`. | seen (logged-out landing: links `/?nb=l`, `/u/direct/`, `/reels/`, `/explore/`, `/u/profile/`); inherited (signed-in, from the old messages-link logic) | The web tab bar stays visible above the native one, and no avatar is reported, so Profile keeps its placeholder glyph and waits for a username. |
| Top bar | Seeds `svg[aria-label="Instagram"]`, `svg[aria-label="Back"]`, `[aria-label="Back"]`; climb ≤ 8 ancestors, keep the outermost one at `top ≤ 2`, ≥ 90 % wide, 30–90 px tall, not containing `main`, `article`, inputs, `[role="combobox"]` or story links. Marked `data-native-hidden="header"`. Skipped on login/stories/create pages. | inherited for the Home wordmark header; assumed for Back headers | A second (web) header shows under the native one. Search never matches because its bar contains an input. |
| Top bar spacer | The next element sibling of a hidden top bar whose computed `position` is `fixed`, when its computed `padding-top` is 30–120 px → `data-native-header-spacer`; the skin sets `padding-top: 0` while the bar stays hidden (`[data-native-hidden="header"] + [data-native-header-spacer]`). | seen (logged-out `/instagram/` in the app's WKWebView: the bar's next sibling has `padding-top: 60px`) | A blank strip about 60 pt tall stays under the native header. Home's own reservation (`body` padding = `--native-header-height`) is separate and unchanged. |
| Following feed top bar | Home only, while web chrome is hidden. Seeds: `span, h1, h2, p, div` with no element children whose trimmed text is exactly `Following`, and `[aria-label="Following"]`, skipping seeds inside `article`, `[data-following-approved]`, dialogs, menus and hidden nodes. Climb ≤ 8 ancestors (stop at `body` or at a node containing `main`, `article`, a rendered text field (`input`/`textarea` with a non-zero rect and not `display:none`/`visibility:hidden`; hidden or zero-size inputs do not block), `[role="combobox"]`, story links, `[data-following-approved]`, the stories slot, `img` or `video`); keep the outermost node ≥ 90 % wide, 30–90 px tall, with viewport top or document top within `[-2, headerHeight + 64]`. Structural nav seed (runs FIRST, before the label seed and the point fallback; any bar found or already marked by the label/point paths is upgraded to its ancestor nav that passes the same rules, so the in-flow 45 px placeholder does not stay as a blank strip): `nav` / `[role="navigation"]` not inside `article`, `[data-following-approved]`, dialogs or hidden nodes, followed among its parent's later element siblings by `main` or an element containing `main`, passing the same size/position test and containing none of the stop elements; the nav itself is marked. Structural fallback: `document.elementsFromPoint(width/2, 2)` and `(width/2, 20)`, climbing ≤ 8 ancestors for a computed `position: fixed/sticky` node of the same size (so a bar labelled otherwise is still caught); also re-run at most every 100 ms on `scroll`. Marked `data-native-hidden="following-bar"` (not `header`, which would stop the wordmark header being found), height stored in `data-native-bar-height`. If the marked node is replaced or loses the mark, the MutationObserver re-finds it synchronously. Spacer: the next sibling of a fixed bar with `padding-top` 30–120 px gets `data-native-header-spacer` (`[data-native-hidden="following-bar"] + [data-native-header-spacer]` zeroes it). | seen (signed-in iPhone outline, cycle 1): `section > nav` 402×45, relative, at document top 44 (in-flow placeholder), directly before `main`, holding `div > header` (position fixed, top 0, z-index 1, 402×44) with an h1 title link `a[href="/"]` (144×24, no text) and a right-hand group with an icon block plus a `display:none` div of two `form[role="presentation"] > input` (zero rects); the label seed did not match and the hidden inputs used to block every candidate (only rendered text fields block now). The fixed header sits under the opaque native header at rest. Scan throttle (300 ms) has one trailing retry. The app root also holds a hidden (`display:none`) `position: fixed; top: 0; z-index: 12` container whose purpose is unknown; the scroll probe hides it if it appears as a bar | The bar shows when the native header collapses (scroll) and in the refresh gap. |
| Following bar empty spacer | An element sibling (next or previous) of a hidden fixed/sticky following bar with no element children, empty trimmed text and a height within 2 px of the bar's → `data-native-hidden="following-spacer"`. | assumed | A blank strip the bar's height stays under the native header. |
| In-feed stories row | Home page role. Items `a[href^="/stories/"]`, `a[href^="https://www.instagram.com/stories/"]`, `button[aria-label*="story" i]`, `[role="button"][aria-label*="story" i]` outside `article`, `[data-following-approved]`, `[data-native-hidden]`, `[role="dialog"]`; climb ≤ 7 ancestors, keep the outermost 40–190 px tall, ≥ 60 % of the viewport wide, holding ≥ 2 items and no `article`, `a[href*="/p/"]`, `[data-following-approved]`, `[data-instagram-stories-slot]`, `main` → `data-native-stories-row`. Hidden by the skin only while `html[data-native-stories="tray"]` (native tray active). | assumed | A second stories row under the native tray (the outline's `marks.storiesRow` tells whether it was found). |
| Refresh hide | `html[data-native-refreshing] body { opacity: 0 }` while a pull-to-refresh reload is held behind its snapshot | n/a (our markup) | The failsafe clears the attribute 25 s after document start. |
| Page title | `h1, h2, [role="heading"]` inside the marked top bar; else `document.title` without "• Instagram". | assumed | Native default titles (Message, Settings, empty for other). |
| App banners | `a`, `button`, `[role="button"]` whose whole text is "Open app", "Open in app", "Use the app", "Get the app" or "Open Instagram", with a `position: fixed/sticky` ancestor within 6 levels that contains no `main`, `article` or password field. | assumed | The banner stays visible. The logged-out "See full profile in the app" dialog is **not** matched (it is a dialog, not fixed chrome). |
| App Store badges | `a[href*="apps.apple.com"]`, `a[href*="itunes.apple.com"]`, `a[href^="itms-apps:"]` | assumed | Badges show on login pages. |
| Web artifacts | `* { -webkit-tap-highlight-color: transparent }`, `-webkit-touch-callout: none`, `user-select: none` except inputs/textarea/contenteditable | n/a (CSS only) | — |
| Home top reservation | `html[data-native-chrome="hidden"] body { padding-top: var(--native-header-height) }` | assumed | If Instagram keeps an in-flow spacer for its (now hidden) fixed header, the feed starts lower than intended (gap under the native header). Device check. |

## Login detection (`Bridge.js` → `ready {kind:'login'}`)

| Signal | Found | Fallback |
| --- | --- | --- |
| `input[type="password"]`, `input[name="username"]` | seen (`/accounts/login/`) | — |
| Logged-out placeholder links `a[href="/u/profile/"]`, `a[href="/u/direct/"]` | seen (landing at `/` and `/?variant=following`) | Next rule. |
| `a[href^="/accounts/login"]` with no `article` on the page | assumed | Next rule. |
| A button whose whole text is "Log in", outside `[role="menu"]`/`[role="dialog"]` | seen (landing) | Readiness fallback reveals the page after 4–8 s; Home header and tray stay visible over Instagram's landing. |

FeedFilter's own `login` status also marks the page as login content: a sign-in route (the same
login sets as `classify`), an `input[type="password"]` outside signed-in `/accounts/` pages (so
`/accounts/password/change/` is not login), or no posts/records and `main a[href^="/accounts/login"]`.
Other `/accounts/` pages (`/accounts/activity/`, `/accounts/edit/`) are not login routes (Phase 2).

## Readiness probes (`Bridge.js`, held for 6 frames; Search 24 stable frames)

| Kind | Ready when | Fallback |
| --- | --- | --- |
| home | The first post card in document order (`[data-following-approved]`, skipping cards FeedFilter collapsed: approved `no` and pending `no`) is approved `yes`, and approved cards have a non-zero height; or `[data-instagram-caught-up]` | Document complete + 8 s |
| profile | `main header img`, `main header h1` or `main header h2`, and no loader | complete + 4 s |
| post / comments / likes | `main article` or `main img, main video`, and no loader | complete + 4 s |
| search | The search control (`input[placeholder*="Search" i]`, `input[aria-label*="Search" i]`, `input[type="search"]`, `[role="combobox"]`) visible with an unchanged rect for 24 frames, document complete | complete + 4 s |
| other kinds | `main` has text or media and no loader | complete + 4 s |
| loader | `main [role="progressbar"]`, `main [data-visualcompletion="loading-state"]`, `main svg[aria-label^="Loading"]` (visible) | — |

Native shows "Couldn't load" if nothing is ready after 20 s.

## Theme

`document.elementsFromPoint(viewportWidth / 2, 2)`, keeping full-width (≥ 90 %) elements,
then `body`, then `html`; the first opaque `background-color` wins. Before each node's own
background, its children that cover the sample point with `pointer-events: none` are
checked, because hit-testing skips them (seen: Meta's `/accounts/login/` paints its grey
`rgb(31, 31, 32)` surface with a full-viewport absolute `div` with `pointer-events: none`
under transparent wrappers, while `html`/`body` are `rgb(12, 16, 20)`). Sampled at `ready` and
0.3, 1 and 2.5 s after it; then on DOM changes at most once per 500 ms (a trailing sample
covers a burst), and at once on the first DOM change after a route change. Nothing is
sampled before `ready` (the skeleton covers the page). Tests: `Tests/bridge-theme.test.cjs`. Only the visible page's colour is applied.
Fallback: native keeps the last colour (persisted across launches).

Native applies the colour through `Theme.changes`, which fires after the colour is stored
(a `@Published` sink fires in `willSet` and made every native surface one colour behind;
that, not the sampling alone, is why earlier fixes for the login surface did not show).

The sampled colour sets the native surfaces and the window's interface style, but never the
page's own colour scheme: every web view's `overrideUserInterfaceStyle` is `Theme.webStyle`,
the app appearance reported by the window scene (Dark through Info.plist `UIUserInterfaceStyle`;
the system appearance if that key is removed; the scene's traits ignore the window override). Before, web views inherited the window
style, so one light sample (for example a light login surface) made Instagram render light,
which was sampled again, and the app stayed light until something dark was sampled.

## Stories tray (tray web view, `Bridge.js` role `tray`)

| What | Selector / rule | Found | Fallback |
| --- | --- | --- | --- |
| Tray items | `a[href^="/stories/"]`, `button[aria-label*="story" i]`, `[role="button"][aria-label*="story" i]` | inherited | No `storiesTray` message: the host keeps its placeholder rings, then the feed reveals after 1.5 s. |
| Tray container | Ancestor ≤ 7 levels of an item, 40–190 px tall, ≥ 60 % wide, not containing `article`, post links or the wordmark. Pinned `position: fixed; top: 0` with everything else hidden. | inherited | As above. |
| Signed-in confirm dialog | `[role="dialog"]` whose text matches "view … story … signed in"; clicks the button whose whole text is "View story", "View" or "Continue" (once per dialog) | inherited | The dialog shows inside the native story viewer; the user taps it. |
| Viewer state | `location.pathname` starts with `/stories/` | inherited | — |
| Wordmark | `svg[aria-label="Instagram"]`: `viewBox` plus `path`, `polygon`, `polyline`, `rect` children (≤ 12, converted to path data) | seen (logged-out landing: `viewBox="0 0 600 150"`, one `polygon` for the "I" + six `path`s) | Native header draws the bundled copy of that capture (`WordmarkShape.bundled`). Either is fitted by its ink bounds into 103×29 pt. |
| Viewer close control | `svg[aria-label="Close"]`, then its closest `button`, `[role="button"]` or `a[href]`, clicked by `__instagramTray.closeViewer()` for the native downward and left-edge swipes | assumed | `history.back()`; if the viewer is still open 1 s later, native reloads the tray, which reports the viewer closed. |
| Login landing | The tray document's route (navigation policy, commit, `route` and `navigate` messages) classifies as `login` (e.g. `/accounts/login/`, `/accounts/onetap/`) | assumed (review follow-up) | The tray hides itself (reports no items) and never navigates Home; the next feed reload retries it. |

## Avatar and username

The profile link inside the marked web tab bar (`a[href="/<username>/"]` containing an
`img`), image `currentSrc`/`src` on `*.cdninstagram.com` or `*.fbcdn.net` only.
Seen: logged-out bars use `/u/profile/` (classified `other`, never reported).
Inherited: signed-in bars link the own profile. Fallback: Profile tab waits on its
skeleton; the last username is cached between launches.

## FeedFilter.js assumptions (unchanged from 0.4.x; filtering logic not modified)

| What | Selector | Fallback |
| --- | --- | --- |
| Post candidates | `main` + top-level `article` containing `img, video, a[href*="/p/"]`; modern markup: climb from `main a[href*="/p/"]` to the smallest ancestor with media and one author | Posts without recognisable structure stay hidden (`unrecognized-posts`). |
| Author | `header a[href]`, `h2 a[href]`, `h3 a[href]`, or the first attribution row of profile links whose text equals the handle | Card hidden. |
| Ads / suggestions | Labels in `header`, `[data-testid="sponsored-label"]`, `[aria-label="Sponsored"]` | Response metadata (`is_ad`, `is_suggested`) still hides them. |
| Membership data | `script[type="application/json"]` and existing fetch/XHR JSON responses | Import `following.json`. |
| Reels | `a[href*="/reel/"]`, `a[href^="/reels"]`, `a[href^="/tv/"]`, `button[aria-label="Reels"]`, `product_type` clips/reels | Router and `InstagramNavigation` still block Reels routes. |
| Older posts | Controls whose text is "View older posts"/"See older posts" | Caught-up card's own button. |
| Controls entry | `[role="menu"]` whose text mentions "Settings" or "Your activity" gets a "Following filter settings" button → `openControls` | Profile header menu → Content filters. |
| Search idle | Search control (as above), `document.activeElement`, `[role="dialog"]` | Idle state hidden. |
| Stories spacer | `[data-instagram-stories-slot]` inserted before the first post's top-level branch under `main` on `?variant=following` | Tray sits directly under the header (y = header height). |

## Navigation (Phase 2B, `Bridge.js` interception region)

| What | Selector / rule | Found | Fallback when it fails |
| --- | --- | --- | --- |
| Link interception | `a[href]` (closest to the click target), decided on `window`'s **capturing** `click` phase, so it runs before Instagram's React handlers (React listens on its root container). Modified clicks and `#`/`javascript:` links are left alone. | inherited (links); assumed (capture order on device) | A link Instagram handles on an earlier window-capture listener of its own would route in place; the `pushState` interception below still catches it. |
| Route content signature | `main`, `main.firstElementChild`, `main header`, `main article` (element identity), recorded on `pointerdown`/`touchstart` (capture) and at a cancelled `pushState`/`replaceState`. If it differs two frames after the cancel, a `popstate` with the unchanged `history.state` is dispatched so Instagram's router renders the current location again. | assumed | If Instagram's router ignores the synthetic `popstate`, the page underneath a native push can show the pushed page's content after swipe-back (device checklist). If the signature misses an in-place render (page keeps `main` and its first child), same symptom. A false positive (content changed for another reason within two frames) re-renders the current page once. |
| Link shim | `https://l.instagram.com/?u=<encoded target>&e=…` on caption and bio links; native opens the decoded `u` target in Safari View Controller (or routes it if it is an instagram.com page) and never loads the shim. | inherited (shape of Instagram's outbound links) | Without `u` the tap is dropped silently. |
| Full-screen close control | Instagram's own close button in the story viewer / create flow (`svg[aria-label="Close"]` inside a button) changes the route away from `/stories/` or `/create/`; native dismisses on that route change or on the resulting `navigate`. Nothing selects the control itself. | seen (logged-out story viewer shows the close "X") | Swipe down or the left-edge swipe dismisses natively. |
| Settings password fields | `ready` reports `settings`, not `login`, on settings routes (e.g. `/accounts/password/change/`) even when `input[type="password"]` is present. | assumed | — |

## Search, Notifications and Profile (`Bridge.js` "Tabs" region + `NativeSkin.css` Search / Notifications / Profile)

Bridge.js marks nodes with `data-native-*` attributes on every chrome scan (one hook call, `scanTabs()`,
in the mutation handler); NativeSkin.css styles only those attributes. Native reaches the page through
`window.__instagramTabs` (`switchAccount()`, `unread()`, `cancelSearch()`, `hasSearchField()`).
Signed-in Search, Notifications and own-profile markup could not be observed here (logged out), so most
rows are **assumed**; the logged-out profile (`/instagram/`, Oct 2026, WKWebView and headless Chrome)
is **seen**.

| What | Selector / rule | Found | Fallback when it fails |
| --- | --- | --- | --- |
| Page kind | `html[data-native-page]` = `classify(location.pathname).kind` (same table as the Router) | n/a | Kind-scoped rules (profile buttons, headings) do not apply; the attribute-marked rules still do. |
| Search field | `input[placeholder*="Search" i]`, `input[aria-label*="Search" i]`, `input[type="search"]` → `data-native-search-input` | inherited (0.4.x device evidence: stable control) | Instagram's own field shows unskinned; no Cancel; native idle state stays hidden (`hasSearchField()` is false). |
| Search field box | Outermost ancestor (≤ 5 levels) 28–52 px tall, at least 16 px narrower than the viewport, containing only this input → `data-native-search-field` (36 px, radius 10, grey, magnifier background); its parent → `data-native-search-row` (flex) | assumed | Only the input is restyled (16 px text); no Cancel is inserted. |
| Instagram's overlay label | Leaf `span`/`div`/`label` inside the field box whose whole text is "Search" (not the input) → `data-native-search-label`, `display: none`. The input `placeholder` is the single visible "Search" (set to "Search" if Instagram left it empty). Our code adds no label text of its own (no pseudo-element, no native placeholder). | assumed (diagnosed from code; signed-in markup not observed) | "Search" shown twice (placeholder plus overlay). |
| Instagram's magnifier | `svg[aria-label="Search"]` inside the field box → hidden (ours is a background image) | assumed | Two magnifiers. |
| Cancel | Our `button[data-native-search-cancel]` inserted after the field box; shown while `html[data-native-search-active="yes"]` (input focused or non-empty). Tap: clears via the prototype `value` setter + `input` event (React state), blurs, and clicks Instagram's own Cancel. | n/a (ours) | — |
| Instagram's Cancel | `button` / `[role="button"]` whose whole text is "Cancel" with `top ≤ 160` → `data-native-hidden="search-cancel"` (only when ours exists) | assumed (FeedFilter already relied on a Cancel/Back control) | If Instagram uses a Back arrow instead, it stays visible next to ours. |
| Search results | `a[href]` to a single-segment profile path (`classify` = profile) containing an `img`, not in hidden chrome → `data-native-search-result`; avatar block (outermost ancestor ≤ 1.4× the picture) zoomed to 44 px; first leaf text equal to the handle → `data-native-search-username` (14 px semibold); next leaf text → `data-native-search-secondary` (grey). Badges (`svg[aria-label="Verified"]`) untouched. | assumed | Rows keep Instagram's own sizes; taps still reach the link (nothing is overlaid). |
| Keyboard dismissal | Native `keyboardDismissMode = .onDrag`, plus a document `touchmove` > 10 px outside the search row blurs the focused field | n/a | Keyboard stays up while scrolling results inside an inner scroller. |
| Activity rows | Under `main` (else `body`): a profile link containing an `img` → `data-native-activity-avatar` (zoomed to 44 px); its nearest full-width (≥ 85 %) ancestor 40–150 px tall → `data-native-activity-row`; in the row, `a[href*="/p/"|"/reel/"]` with an `img` → `data-native-activity-thumb` (44 px), text-only profile links → `data-native-activity-user` (bold), `time` → grey, controls whose whole text is Follow / Follow back / Following / Requested / Message → `data-native-follow-button` (`primary` blue for Follow, else grey) | assumed | Rows keep Instagram's own styling. |
| Unread activity | `a[href*="/accounts/activity"]`, `a[href^="/notifications"]` (in the Home page's hidden web header): an `aria-label` or text matching "unread", "new notification(s)" or "N notifications", or a descendant `div`/`span` with an opaque red background (r ≥ 200, g ≤ 90, b ≤ 110). Polled by native from the Home web view every 30 s and on tab changes; cleared while Notifications is selected. | assumed | No dot on the Notifications tab. |
| Profile header | First `header` containing `img[alt*="profile picture" i]` and `h1`/`h2` → `data-native-profile-header`; avatar block (outermost ancestor ≤ 4 levels and ≤ 1.4× the picture, so the story-ring canvas comes along) → `data-native-profile-avatar`, CSS `zoom` to 90 px | seen (logged-out: 96 px picture inside an `a` with a ring `canvas`) | Avatar keeps Instagram's size. |
| Profile buttons | In the header's parent: `button`, `a`, `[role="button"]` (outermost only, not in dialogs or the tab strip) whose whole text is Edit profile / Share profile / Follow / Follow back / Following / Requested / Message / Contact / Email / Call / View archive / Ad tools / Professional dashboard / Subscribe → `data-native-profile-button` (32 px, radius 8, equal width) | assumed (logged-out has none) | Instagram's own buttons. |
| Profile counts | In the header: innermost `a`/`li`/`span` whose text is "<number> posts / followers / following" → `data-native-profile-count`; nested number spans semibold | seen (logged-out "686M followers", "308 following") | Instagram's own type. |
| Profile tab strip | `[role="tablist"]` with 2–6 `a`/`[role="tab"]` → `data-native-profile-tabs`; a tab with `svg[aria-label="Reels"]`, an href ending `/reels/` or label "Reels" → its slot (sole-child wrapper) `data-native-hidden="reels-tab"`; others `data-native-profile-tab` (`selected` from `aria-selected="true"`) | seen (logged-out: Posts via `svg title`, Reels via `aria-label`, Tagged via `title`; all link to applink) | Reels tab icon stays visible (Reels links themselves are still blocked by the Router). |
| Profile grid | `a[href]` to `/p/`, `/reel/` or `applink.instagram.com` with an `img`, outside header/dialogs, whose parent's parent has 2–4 children holding such tiles → `data-native-grid-tile` / `-cell` / `-row` / row parent `data-native-grid`; the tile's padding-based ratio box (inline `padding-bottom: N%`, or computed padding with zero height) → `data-native-grid-ratio` (set to 3:4 portrait, `padding-bottom: 133.333%`, like native Instagram) | seen (logged-out: rows of three, `padding-bottom: 133.333%` boxes) | Instagram's own grid (portrait 3:4 tiles, its gaps). |
| Own-profile web top bar | `svg[aria-label]` matching Settings / Options / New post / New / Create / Discover people / Threads / Switch account(s) / Down chevron icon, not in the profile header, dialogs or `main header`; outermost ancestor ≤ 8 levels at `top ≤ 2`, ≥ 90 % wide, 30–90 px tall, without `main`, `article`, inputs, the tab strip or a profile picture → `data-native-hidden="header"` (only while web chrome is hidden) | assumed | A web bar shows under the native Profile header. |
| Account switcher | In the hidden top bar: the first `button`/`a`/`[role="button"]` with `svg[aria-label*="chevron" i]` or `svg[aria-label*="switch account" i]`, or an aria-label containing "switch account"; native chevron calls `switchAccount()` (clicks it) | assumed | Chevron tap does nothing (`switchAccount()` returns false). |
| App-install dialog | `[role="dialog"]` with no inputs, forms or contenteditable, text ≤ 400 chars matching "see full profile/post… in the app", "use the app to see more", "get the full experience", "open/continue/view in the app", "use/get/download the app", and either an `applink.instagram.com` / App Store link or a control whose whole text is Open Instagram / Open (in) the app / Use the app / Get the app / Download the app. The overlay layer (outermost `position: fixed` or `tabindex="-1"` ancestor ≤ 6 levels without page content) → `data-native-hidden="app-dialog"`, and `html[data-native-app-dialog]` restores body scrolling. Supersedes the "not matched" note in the App banners row above. | seen (logged-out profile: `div[tabindex="-1"] > … > [role="dialog"]`, "See full profile in the app", "Open Instagram", "Sign up") | The dialog shows; closing it with its own control still works. Login challenges and confirmations are never matched (inputs, or no app wording/link). |
| Sign-up overlay | `a[href^="/accounts/signup"]` whose whole text is "Sign up" / "Sign up for Instagram", outside dialogs: nearest `fixed`/`sticky`/`absolute` ancestor ≤ 8 levels whose text contains "Get the full experience" and that holds no images, inputs, header, `main`, `article` or tab strip → `data-native-hidden="signup-banner"` | seen (logged-out profile: an absolute gradient overlay over the grid) | The overlay shows over the grid (logged out only). |
| Button colour | Primary (Follow) buttons use Instagram's own `--ig-primary-button` triplet: `rgb(var(--ig-primary-button, 74, 93, 249))` | seen (logged-out profile, dark: `74, 93, 249`) | The fallback is the same blue. |
| Settings route | Profile menu → Settings and activity pushes `/accounts/edit/`. `/accounts/settings/` and `/accounts/privacy_and_security/` 302 to login when signed out (real, gated routes) while unknown `/accounts/x/` paths return 200; their signed-in content is unverified. | probed (curl, logged out) | Edit profile page only. |

## Home feed skin (`NativeSkin.css`, `/* === Home === */`)

Every post-card rule is scoped to `html[data-following-mode="feed"] [data-following-approved="yes"]`
(attributes FeedFilter sets on the document and on the cards it approved), so nothing outside
approved Following-feed cards changes. No hashed class names; an element these selectors cannot
reach keeps Instagram's own style. Colours follow `prefers-color-scheme` (dark: text
`rgb(245,245,245)`, secondary `rgb(168,168,168)`; light: `#000`, `rgb(115,115,115)`).
Checked in the simulator against `Tests/fixtures/home-feed.html`, an approximation of m-web
markup built from these assumptions, not a capture of Instagram's signed-in DOM.

| What | Selector (inside an approved card) | Found | Fallback when it fails |
| --- | --- | --- | --- |
| Card frame | the card itself: no border, no radius, no side margins; 14/18 px text | inherited (FeedFilter's cards) | Instagram's own card frame. |
| Avatar | `header img[alt$="profile picture" i]` → 32×32, round | assumed (Instagram's alt text is "<user>'s profile picture") | Instagram's avatar size. Headerless (modern `div`) markup is not matched; story-ring canvases are left alone. |
| Username | `header a[href]` without an `img`, not a post (`/p/`), location (`/explore/`) or audio (`/audio/`) link, and its spans → 14 px semibold, primary | assumed | Instagram's weight. |
| Timestamps | `time` → 12 px secondary, no uppercase; `header time` → 14 px secondary | assumed | Instagram's timestamp style. |
| Action glyphs | `svg[aria-label]` = `Like`, `Unlike`, `Comment`, `Share Post`, `Share`, `Save`, `Remove` → 24×24 | assumed | Instagram's glyph size; spacing is always Instagram's own button padding. |
| Like count | `a[href$="/liked_by/"]` and its spans → 14 px semibold, primary | assumed (FeedFilter already accepts `/liked_by/` post links) | Instagram's style. "Liked by X and others" rows get the same weight for the linked part only. |
| Comments link | `a[href$="/comments/"]` and its spans → 14 px secondary | assumed | Instagram's style. |
| Inline comment field | `form:has(textarea)` → hidden (native has no inline composer in the feed; Comment opens the comments page) | assumed | The field shows. |
| Not styled | Caption username (no attribute tells it from @mentions), carousel dots (no stable attribute), "•" separator text | — | Instagram's own style. |
| Caught-up card | `[data-instagram-caught-up]` and its `[data-part]` children, injected by FeedFilter | n/a (our markup) | — |

## Sound (audio session + unmute control)

| What | Selector / rule | Found | Fallback when it fails |
| --- | --- | --- | --- |
| Feed and story videos start muted with a tap-to-unmute toggle | An element labelled like "Toggle audio", "Audio is muted", "Audio is playing", "Unmute", "Mute" (button, `[role="button"]` or svg `aria-label`). The skin never targets it: no rule hides it or sets `pointer-events` on it (audited: the only hiding rules in cards are `form:has(textarea)`, the stories row, app banners and `[data-native-hidden]` bars, none of which contain a video). Native code does not touch it either. | assumed | If the control is missing from the outline of a signed-in card, capture it and record the real label here; do not add CSS that hides it. |
| Playback category | `AudioSession.activateForPlayback()` sets `.playback`/`.moviePlayback` once at scene connect (category only, not activated). | n/a (native) | Without it, sound is silenced by the ringer switch. |
| Playback policy | `mediaTypesRequiringUserActionForPlayback = .all` unchanged: unmute happens in Instagram's tap handler (a user gesture); muted autoplay is Instagram's own behaviour. | assumed | Only revisit with a concrete device finding. |

## Messages inbox (`Bridge.js` "Tabs" region, message notifications)

`inboxState` is posted on `inbox` routes (the Messages tab and the hidden background-refresh web view). Signed-in inbox
markup has **never been observed** (logged out only): every row is **assumed**. DEBUG builds write
`page-outline-inbox-ready-<n>.json` after a background-style check and when the Messages tab is ready, so the real
structure can be pulled from a device and these rules corrected.

| What | Selector / rule | Found | Fallback when it fails |
| --- | --- | --- | --- |
| Thread row link | `a[href*="/direct/t/"]` whose path is `/direct/t/<id>/` on an instagram.com host, `<id>` = `[A-Za-z0-9_.-]{1,64}`; first link per id, at most 50 | assumed (route shape matches the Router's `thread` kind) | No links: nothing is posted, so nothing is ever announced. |
| Row | The link itself when it holds text; else the nearest ancestor (<= 5 levels) that holds only this thread link | assumed | If the link holds no text, name is empty ("New message") and only label/dot signals inside the row apply. |
| Name | Text of the first text-bearing leaf in the row (no children, not svg/img), whitespace collapsed, trimmed, first 80 characters | assumed | Empty name: the notification reads "New message". |
| Unread signal 1: label | Any element in the row with `aria-label` or `title` containing the word "unread", or a leaf whose whole text is "Unread" / "<n> unread" | assumed | Falls to signal 2. |
| Unread signal 2: dot | A childless `div`/`span`/`i` in the row, 4-16 px wide and tall (within 2 px of square), with an opaque solid blue background (b >= 200, b > r + 60, b > g; Instagram blue is rgb(0,149,246)) | assumed | Falls to signal 3. |
| Unread signal 3: bold preview | The row's second text leaf (after the name) has computed `font-weight` >= 600 (or `bold`) | assumed | If none of the signals match, every row is read and no notification is posted (fails quiet). If a signal matches rows that are read, they announce once, then the baseline holds them. |
| Readiness | `inboxState` is posted when `document.readyState` is `complete` (or `ready` was sent), not on `ready` itself, and from a dedicated `MutationObserver` and window `load` (the shared chrome scan runs from `requestAnimationFrame`, which a hidden web view may not get) | n/a | The probe times out after 20 s and changes nothing. |
| Throttle | At most one scan per second; a post only when the thread list (ids, flags, names) differs from the last post of this document; leaving the inbox route forgets it | n/a (ours) | — |
