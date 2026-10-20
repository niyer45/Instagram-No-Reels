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

FeedFilter's own `login` status (`input[type="password"]`, or no posts/records and
`main a[href^="/accounts/login"]`) is unchanged and also marks the page as login content.

## Readiness probes (`Bridge.js`, held for 6 frames; Search 24 stable frames)

| Kind | Ready when | Fallback |
| --- | --- | --- |
| home | `[data-following-approved="yes"]` (FeedFilter approved a post) or `[data-instagram-caught-up]` | Document complete + 8 s |
| profile | `main header img`, `main header h1` or `main header h2`, and no loader | complete + 4 s |
| post / comments / likes | `main article` or `main img, main video`, and no loader | complete + 4 s |
| search | The search control (`input[placeholder*="Search" i]`, `input[aria-label*="Search" i]`, `input[type="search"]`, `[role="combobox"]`) visible with an unchanged rect for 24 frames, document complete | complete + 4 s |
| other kinds | `main` has text or media and no loader | complete + 4 s |
| loader | `main [role="progressbar"]`, `main [data-visualcompletion="loading-state"]`, `main svg[aria-label^="Loading"]` (visible) | — |

Native shows "Couldn't load" if nothing is ready after 20 s.

## Theme

`document.elementsFromPoint(viewportWidth / 2, 2)`, keeping full-width (≥ 90 %) elements;
the first opaque `background-color` wins, then `body`, then `html`. Re-sampled 0.3, 1 and
2.5 s after `ready` because stylesheets can repaint without DOM mutations. Only the visible
page's colour is applied. Fallback: native keeps the last colour (persisted across launches).

Known miss (seen): Meta's `/accounts/login/` page paints a grey (#212121) surface while
`html`, `body` and every element under the top-centre point report `rgb(12, 16, 20)` or
transparent at `ready`, so the native status bar and tab bar stay Instagram dark around a
grey login form. The grey likely comes from a layer excluded from hit-testing
(`pointer-events: none`) or a pseudo-element. Not fixed in Phase 1.

## Stories tray (tray web view, `Bridge.js` role `tray`)

| What | Selector / rule | Found | Fallback |
| --- | --- | --- | --- |
| Tray items | `a[href^="/stories/"]`, `button[aria-label*="story" i]`, `[role="button"][aria-label*="story" i]` | inherited | No `storiesTray` message: the host keeps its placeholder rings, then the feed reveals after 1.5 s. |
| Tray container | Ancestor ≤ 7 levels of an item, 40–190 px tall, ≥ 60 % wide, not containing `article`, post links or the wordmark. Pinned `position: fixed; top: 0` with everything else hidden. | inherited | As above. |
| Signed-in confirm dialog | `[role="dialog"]` whose text matches "view … story … signed in"; clicks the button whose whole text is "View story", "View" or "Continue" (once per dialog) | inherited | The dialog shows inside the native story viewer; the user taps it. |
| Viewer state | `location.pathname` starts with `/stories/` | inherited | — |
| Wordmark | `svg[aria-label="Instagram"]`: `viewBox` plus `path`, `polygon`, `polyline`, `rect` children (≤ 12, converted to path data) | seen (logged-out landing: `viewBox="0 0 600 150"`, one `polygon` for the "I" + six `path`s) | Native header shows a text "Instagram" fallback. |

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
