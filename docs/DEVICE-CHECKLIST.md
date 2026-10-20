# Device checklist (0.5.0, build 14)

Everything below could not be verified in the simulator because nobody can sign in to
Instagram there. Install the Debug build over the existing 0.4.5 installation (same team
and `com.local.following`, so the login persists) and tick each item. Note failures with
the page, what you did and what you saw; never paste usernames or post content.

## Install and launch

- [ ] Installing over 0.4.5 keeps you signed in and launches into the new shell (not a black screen).
- [ ] The splash shows only at launch and cross-fades into Home within a few seconds; no Instagram website splash or spinner appears.
- [ ] Status bar, Home header and tab bar use Instagram's dark surface with no white or grey flashes on launch, tab switches or pushes.

## Tab bar

- [ ] Four tabs: Home, Search, Notifications, Profile. No web tab bar visible on any page (Home, Search, Profile, post, inbox, thread, settings).
- [ ] The Profile tab shows your avatar after the first page loads; the selected Profile tab shows a ring around it.
- [ ] Tab switches keep each tab's page and scroll position (scroll Home, visit Search and Profile, come back).
- [ ] Re-tapping the selected tab scrolls to top; again pops pushed pages; again at the root reloads Home, Notifications and Profile with a skeleton. Search does nothing more.
- [ ] Light haptic on tab changes and pushes.

## Home

- [ ] Native header shows Instagram's real wordmark (not the script-font fallback) after the first launch, plus heart and Messenger.
- [ ] No web header above the feed; the first post sits right under the Stories tray with no gap or overlap.
- [ ] The header slides away while scrolling down and returns on scrolling up; it never covers the status bar.
- [ ] Heart pushes Notifications; Messenger pushes the inbox, both with a back chevron and title.
- [ ] Stories tray shows your stories row, scrolls horizontally, and scrolls vertically with the feed (vertical drags starting on the tray scroll the feed).
- [ ] Tapping a story opens the viewer full screen (no tab bar, no status bar); closing it returns to Home with the tray in place. A left-edge swipe closes it.
- [ ] Tapping a username inside the story viewer closes it and pushes that profile.
- [ ] "View story signed in?" prompts, if Instagram shows them, are confirmed automatically once.
- [ ] Pull to refresh: the spinner shows above the header; after release the pulled distance holds until the new feed is ready, then header, tray and posts settle up together with no blank flash.
- [ ] Filtering is unchanged from 0.4.5: no Reels, ads or suggested posts; posts older than two days stop at the caught-up card; "View older posts" and scrolling past the card continue into older posts.
- [ ] The caught-up card shows a gradient ring with a check, "You're all caught up" and grey secondary text.

## Navigation

- [ ] Tapping a profile, post, comments, likes or a "followers" list pushes a new page with a native back chevron and title; no instant in-place swaps.
- [ ] Interactive edge swipe-back works on every pushed page and does not fight horizontal carousels inside posts.
- [ ] Liking, following, opening the comment composer and expanding captions stay in the page (no push).
- [ ] Profile Posts/Tagged switching stays in the page.
- [ ] Reels links and the profile Reels tab show "Reels are disabled." and never open.
- [ ] Thread pages show the other person's name as the header title.
- [ ] The inbox header compose button opens a new-message page.
- [ ] A story ring on another profile opens that story full screen; closing it returns to the profile.
- [ ] External links (bio links) show the "External links … disabled" alert.

## Search

- [ ] Search opens with Instagram's search field and no web header above it; account results work.
- [ ] While idle (no focus, no query) the native "You're all caught up" state shows below the field; it disappears on focus or typing.
- [ ] The Explore media grid stays hidden.

## Profile tab

- [ ] Shows your own profile with your username as the header title and a menu button.
- [ ] Menu → Settings opens account settings; Menu → Content filters opens the sheet.
- [ ] Pull to refresh holds and settles like Home.

## Content filters, account

- [ ] Instagram's own settings menu still contains "Following filter settings", which opens the native sheet.
- [ ] Sheet counts update; "Reload Home" reloads the feed; importing and removing `following.json` changes filtering without restarting.
- [ ] Sign out (with confirmation) returns every tab to Instagram's login; signing in again returns to the Following feed in all tabs.

## Loading and recovery

- [ ] Every page shows its skeleton while loading (feed cards, profile header + grid, search rows, inbox rows, list rows), then cross-fades to content.
- [ ] With Airplane Mode on, a page shows "Couldn't load" after about 20 s; "Tap to retry" reloads once back online.
- [ ] After the app is backgrounded for a long time (web content process killed), returning reloads the page behind its skeleton instead of a blank view.

## Messages and other pages

- [ ] Inbox and thread pages have no duplicate web header, the composer works with the keyboard, and the tab bar does not cover the composer.
- [ ] Settings and other pushed pages have no duplicate web header.

## Known risks to look for

- [ ] Gap or overlap under the Home header (body padding vs. Instagram's own header spacer).
- [ ] The web top bar still visible on some page types (selector misses).
- [ ] Login page: status bar and tab bar match Meta's grey login surface (fixed in review; confirm on device), and return to Instagram dark after signing in.

## Review follow-ups (Phase 1 review; plausible, not confirmable signed out)

- [ ] Right after signing in (or after Sign out → sign in), tapping Profile at once shows your profile, not a skeleton that never ends.
- [ ] Tapping a #hashtag or location (caption, search result) pushes a page with a back chevron instead of jumping to the Search tab. Its post grid is hidden by the filter's Search rule (unchanged); note whether that page is still useful.
- [ ] In Search, submitting a keyword search (`/explore/search/keyword/?q=…`) either shows results with a way back, or nothing changes; it must not strand you on a page with no back control.
- [ ] On the login and sign-up pages, tapping Terms, Privacy, Locations or any other instagram.com link does not reset the tabs or behave as if you signed in (the Router treats any login → non-login navigation as a sign-in).
- [ ] After signing in, including Instagram's "Save your login info?" step, Home shows the Following feed with the native header and Stories tray, not a login page left in the Home tab.
- [ ] Open a post or profile from Home, a profile and the inbox, then swipe back: the page underneath still shows what it showed before (Instagram's router must not have rendered the opened page in place when Bridge.js cancelled its history change).
- [ ] If Settings still links to `/accounts/password/change/`, it pushes normally and the session is not marked signed out (its password fields trip the login probes).
- [ ] Scrolling a long Home feed stays smooth (Bridge.js samples the theme with `elementsFromPoint` on DOM-change frames).

## Phase 2D — Hardening

Simulator-verified where noted in the Phase 2D report; everything here needs a signed-in device.

### Launch

- [ ] Fresh install over the previous build: the splash ends as soon as Home's feed (and its Stories tray) is ready, noticeably sooner than before on a cold start; no white flash, no second splash.
- [ ] Warm launches (app killed from the switcher, reopened) reach the feed within about 2–3 s on a good connection.
- [ ] Signed in, the first page after launch is the Following feed with working links (tapping a profile pushes it); nothing behaves as if the first page were "still loading" (the pre-warmed feed is adopted by Home).

### Offline and failures

- [ ] Turn on Airplane Mode while on Home: a grey "No internet connection" strip slides in under the Home header (under the page header on other pages). Turning Airplane Mode off slides it away within a second or two.
- [ ] With Airplane Mode on, pull to refresh Home or open a profile: the page shows "Couldn't refresh feed" / "Couldn't load profile", "No internet connection…" and a blue Retry button (not a blank page and not Instagram's own error).
- [ ] Turning Airplane Mode off while that failure is showing reloads the page by itself, without tapping Retry.
- [ ] Retry while still offline shows the failure again after the load fails; it never leaves an endless skeleton.
- [ ] VoiceOver: the banner is announced when it appears; Retry reads "Retry, button"; while a skeleton or failure shows, swiping does not reach the hidden web page underneath.

### Foreground refresh

- [ ] Leave the app in the background for under 30 minutes (e.g. 5 minutes), return: every tab shows exactly what it showed, Home at the same scroll position; nothing reloads.
- [ ] Leave the app in the background for over 30 minutes, return on Home: Home reloads behind its skeleton and shows the top of a fresh feed (other tabs unchanged).
- [ ] Same, but return while on another tab: that tab is unchanged; Home reloads when you next tap it.

### Memory

- [ ] Push five or more pages in one tab (profile → post → profile → post → profile …), then swipe back one at a time: every page comes back with its content (deep pages briefly show their last image, then reload), and swipe-back keeps working.
- [ ] After a long session across all four tabs (many pushes, story views), the app is not killed in the background more often than before.
- [ ] With Home scrolled down, visit other tabs and use other heavy apps until iOS warns about memory (or Xcode's Debug → Simulate Memory Warning on device): returning to Home reloads it near the previous scroll position where the reloaded feed is long enough; Search and Notifications reload their pages.

## Phase 2B — Navigation

Supersedes two items above: Reels links and the profile Reels tab now do nothing (no "Reels are disabled." alert), and
external links open in Safari View Controller instead of showing the "External links … disabled" alert.

- [ ] Tapping a post, profile, comments ("View all … comments"), likes, a followers/following count, a hashtag, a location and a notification row pushes a page with the standard slide and a light haptic; going back has no haptic.
- [ ] Titles: "Post", "Comments", "Likes", the username on profiles and on followers/following lists, "Notifications", your username on the inbox, the other person's name on a thread, "New message", "Edit profile" (or Instagram's heading) on settings pages, "#tag" on hashtag pages.
- [ ] In Search, submitting a keyword (`/explore/search/keyword/?q=…`) pushes a results page titled with the query, with a back chevron; nothing strands you without a back control.
- [ ] Open a post or profile from Home, from a profile and from the inbox, then swipe back: the page underneath still shows what it showed before (no copy of the opened page, no reset to the top). If it did reset or reload once, note which page.
- [ ] A message thread hides the tab bar: it slides away with the inbox on push and comes back with the inbox on pop, including an interactive swipe-back; a cancelled swipe-back keeps it hidden. The composer sits at the bottom edge above the home indicator, not 49 pt above it.
- [ ] Pages opened from a thread (e.g. the other person's profile) also have no tab bar; popping back to the inbox restores it.
- [ ] Swipe back only works from the left screen edge. Swiping horizontally through a post carousel, the Stories tray or profile highlights never pops the page.
- [ ] A story ring on another profile opens the story full screen with no status bar and no tab bar. Swiping down drags it away (the profile shows behind it) and closes it after about 120 pt or a quick flick; a shorter, slow drag springs back. Instagram's own close "X" also closes it. The profile underneath is exactly as before (no reload, same scroll position).
- [ ] Bio links and links in captions open in an in-app Safari sheet with a Done/close button; closing it returns to the same page. App Store badges and "Open in app" prompts do nothing and show no alert.
- [ ] Email/phone buttons on business profiles open Mail/Phone.
- [ ] Settings links to Accounts Center (`accountscenter.instagram.com`) open in the Safari sheet; note whether that page asks you to sign in again there.
- [ ] Sign-in from the Home tab (including "Save your login info?") ends on the Following feed with the native header and Stories tray; Search, Notifications and Profile that showed login show their own pages afterwards without a further reset.
- [ ] On the login and sign-up pages, Terms, Privacy, Data Policy and "About" links push a page with a back chevron; nothing resets the tabs and you are not treated as signed in.
- [ ] Settings → Change password (`/accounts/password/change/`) pushes normally and keeps its header; afterwards Home and Profile still behave as signed in (no tab reset after returning).
- [ ] Notifications tab while signed in keeps its "Notifications" header. Known risk outside this workstream: FeedFilter reports state `login` for every `/accounts/…` route, which native treats as login content.
- [ ] Logged in, the Stories tray never turns the Home tab into a login page (e.g. after a long time in the background).
- [ ] "Log in with Facebook" on the login page shows a short explanation instead of opening Facebook.

## Phase 2C — Tabs

Simulator-verified (logged out): tab bar avatar (24 pt, ring when selected), cached avatar after relaunch with an expired URL, avatar cache removed by Sign out, Notifications red dot drawing, Profile header layout and action sheet, Content filters sheet, Search caught-up view, logged-out profile skin (square grid, Reels tab and app prompts hidden). Everything below needs a signed-in device.

### Tab bar
- [ ] Unselected tabs show outline glyphs, the selected one filled (Home, Notifications) or bold (Search); Profile shows your avatar in a 24 pt circle, with a thin ring and a small gap when selected; before the avatar is known it shows the person glyph.
- [ ] Relaunch in Airplane Mode: the Profile tab still shows your avatar immediately (disk cache).
- [ ] Menu → Sign out → Sign out: the Profile tab returns to the person glyph; relaunch keeps the glyph until you sign in again.
- [ ] When Instagram has unread activity, a small red dot appears under the Notifications heart within ~30 s (or on the next tab change); it clears when you open Notifications. Note whether the dot ever shows; if never, Instagram's m-web header exposes no indicator (DOM-NOTES, Unread activity).
- [ ] Tab change gives a selection tick; re-tapping a tab: scroll to top, then pop to root, then (Home, Notifications, Profile) reload behind the skeleton.

### Search
- [ ] The search field is a 36 pt rounded grey field with a magnifier and a grey "Search" placeholder; typing is 16 pt and the page does not zoom on focus. Only one magnifier.
- [ ] Focusing the field slides in "Cancel" at the right; Cancel clears the text, hides the keyboard, hides itself, and the caught-up view returns. Only one Cancel is visible.
- [ ] The caught-up view (ring check, "You're all caught up", grey text) shows only while idle; it fades out on focus or typing.
- [ ] Results: 44 pt round avatars, bold username, grey full name below, verified badge kept. Dragging the results hides the keyboard but keeps the query.
- [ ] Tapping a result pushes that profile with a back chevron (no in-place swap); the first tap works even with the keyboard up.
- [ ] No Explore media grid anywhere on the Search tab.

### Notifications
- [ ] Header reads "Notifications"; no web header under it.
- [ ] Rows: 44 pt round avatar, bold username, grey time, trailing 44 pt post thumbnail or a 32 pt rounded Follow (blue) / Following (grey) button, vertically centred.
- [ ] Pull to refresh holds and settles like Home.

### Profile (own)
- [ ] Header: your username in bold on the left with a small down chevron, "+" (New post) and the menu on the right; no web header under it.
- [ ] Chevron: opens Instagram's account switcher if Instagram's page has one; otherwise nothing happens (no error).
- [ ] "+" shows "Creating posts isn't available in this app."
- [ ] Menu → action sheet: Settings and activity (pushes Instagram's settings; note which page `/accounts/edit/` shows and whether `/accounts/settings/` would be the better hub), Content filters (opens the sheet), Sign out (asks to confirm, then every tab returns to login).
- [ ] Profile header: 90 pt avatar, counts with bold numbers, bio, Edit profile / Share profile as two equal 32 pt rounded grey buttons.
- [ ] Posts / Tagged strip with Instagram's icons, a line under the selected one; no Reels tab.
- [ ] Grid: three columns of square tiles with 1 pt gaps, edge to edge.
- [ ] Pushed profiles (from Search, a post, a comment) get the same skin, with Follow (blue) / Following / Message buttons.

### Prompts and dialogs
- [ ] No "Open app" / "Use the app" / "Get the app" banners, no "See full profile in the app" dialog and no "Get the full experience" overlay on any page; the page scrolls normally.
- [ ] Real dialogs still appear and work: unfollow confirmation, post options menu, login challenge / two-factor code, "Save your login info?".

### Content filters sheet
- [ ] Opens from the Profile menu and from Instagram's settings menu entry; dark inset groups with outline icons; Reload Home, Import following.json, Remove imported list, Sign in and Sign out (with confirmation) all still work.
