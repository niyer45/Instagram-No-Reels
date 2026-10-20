# Device checklist (0.5.0, build 15)

Everything below could not be verified in the simulator because nobody can sign in to
Instagram there. Install the Debug build over the previous installation (same team
and `com.local.following`, so the login persists) and tick each item. Note failures with
the page, what you did and what you saw; never paste usernames or post content.

The simulator checks used the logged-out pages and `Tests/fixtures/home-feed.html`.

## Launch and sign-in

- [ ] Installing over the previous build keeps you signed in and launches into the new shell (not a black screen).
- [ ] The splash shows only at launch and ends as soon as Home's feed and its Stories tray are ready, cross-fading straight into the feed (or the login page) within a few seconds; no grey skeleton in between, no blank frame, no white flash, no second splash, and no Instagram website splash or spinner.
- [ ] Warm launches (app killed from the switcher, reopened) reach the feed within about 2-3 s on a good connection.
- [ ] Signed in, the first page after launch is the Following feed with working links (tapping a profile pushes it); nothing behaves as if the first page were "still loading" (the pre-warmed feed is adopted by Home).
- [ ] Status bar, Home header and tab bar use Instagram's dark surface with no white or grey flashes on launch, tab switches or pushes.
- [ ] On the login page the status bar and tab bar match its grey surface; after signing in everything returns to Instagram dark, and nothing stays light or grey across relaunches.
- [ ] Sign-in from the Home tab (including "Save your login info?") ends on the Following feed with the native header and Stories tray, not a login page left in the Home tab; Search, Messages and Profile that showed login show their own pages afterwards without a further reset.
- [ ] Right after signing in (or after Sign out, then sign in), tapping Profile at once shows your profile, not a skeleton that never ends.
- [ ] On the login and sign-up pages, Terms, Privacy, Data Policy, Locations and "About" links push a page with a back chevron; nothing resets the tabs and you are not treated as signed in.
- [ ] "Log in with Facebook" on the login page shows a short explanation instead of opening Facebook.
- [ ] Sign out (with confirmation) returns every tab to Instagram's login; signing in again returns to the Following feed in all tabs.
- [ ] Visit Search and Profile while signed out, then sign in on Home: Profile shows its native header (username, chevron, "+", menu with Sign out) and Search its caught-up state and Cancel, not a plain page header.
- [ ] Switch between a tab showing the grey `/accounts/login/` page and a tab showing the dark logged-out landing: the status bar and tab bar follow the visible page each time (the page colour is only re-sent when it changes, so a stale colour is possible).

## Home

### Header

- [ ] The native header shows Instagram's real wordmark (not the script-font fallback) on the very first launch, about 103 pt wide and 16 pt from the left edge; it does not change size when the captured one replaces it. Heart and Messenger sit 16 pt from the right edge, 20 pt apart.
- [ ] Scrolling down less than about 8 pt does nothing; scrolling further slides the header away with the content, and scrolling up brings it back. Releasing mid-way snaps it fully shown or fully hidden (a flick follows its direction). At the top of the feed it is always fully shown, it never covers the status bar, and there is no stutter.
- [ ] Re-tapping Home while scrolled down brings the header back at once as the feed scrolls to the top.
- [ ] Scrolling down and back up on Home never shows Instagram's web "Following" bar (or any web bar) under or instead of the native header; nor does pull to refresh.
- [ ] Heart pushes Notifications on Home with a back chevron and title; Messenger switches to the Messages tab (no second inbox).
- [ ] Home's skeleton gives way as soon as the first post at the top is shown, rather than after the whole feed loads; the top of the feed is never blank after the skeleton goes.

### Feed

- [ ] The Stories tray shows your stories row and scrolls horizontally; a vertical drag that starts on the tray scrolls the feed, and a horizontal drag scrolls the tray only. Grey rings show while it loads.
- [ ] Filtering is unchanged from 0.4.5: no Reels, ads or suggested posts; posts older than two days stop at the caught-up card; "View older posts" and scrolling past the card continue into older posts.
- [ ] The caught-up card shows a gradient ring with a check, "You're all caught up", grey "You've seen all new posts from the past 2 days." and a blue "View older posts" that loads older posts.
- [ ] Post cards: edge to edge with no card border; 32 pt round avatar; bold 14 pt username followed by grey "• 2h"; 24 pt heart, comment and share on the left, bookmark on the right; bold like count; grey "View all N comments"; small grey timestamp ("2 hours ago"). Note any element that still looks like the website (and which one); selectors are in DOM-NOTES "Home feed skin".
- [ ] No "Add a comment…" field under feed posts; the comment glyph still opens comments.
- [ ] Only if Instagram itself renders light for you, native surfaces follow (header, wordmark, heart, Messenger, tray rings, card text); nothing is half light, half dark.
- [ ] Scrolling a long Home feed stays smooth.

### Pull to refresh

- [ ] The header stays put and the native spinner shows in the gap below it, above the tray. After release the pulled distance holds until the new feed is ready, then header, tray and posts settle up together with no blank flash; the tray keeps showing the previous stories (no grey rings flash) until the new tray is measured.

## Stories

- [ ] Tapping a story on Home, or a story ring on another profile, opens the viewer full screen: no tab bar, no status bar, no home indicator.
- [ ] Swiping down drags the viewer with your finger (the page shows behind it) and closes it after about 120 pt or a quick flick; a shorter, slow drag springs back.
- [ ] Instagram's own close "X" closes the viewer.
- [ ] A left-edge swipe closes the Home viewer.
- [ ] After closing, the page underneath is exactly as before: Home with the tray in place, or the profile at the same scroll position, with no reload.
- [ ] Tapping through a story and swiping sideways between people still work.
- [ ] Tapping a username inside the viewer closes it and pushes that profile.
- [ ] Open a story from a ring on a pushed profile and close it with Instagram's "X": you are back on that profile once, not on a second copy of it pushed on top (if Instagram's close navigates to the profile instead of going back, the Router pushes it again).
- [ ] Swipe the Home viewer down: if it does not close by itself, the screen accepts taps again within about a second (the invisible container waits 1 s before dismissing).
- [ ] "View story signed in?" prompts, if Instagram shows them, are confirmed automatically once.
- [ ] Logged in, the Stories tray never turns the Home tab into a login page (e.g. after a long time in the background). If the tray lands on a login or "Save your login info?" (`/accounts/onetap/`) page, the tray disappears and Home stays on the feed.

## Navigation

### Tab bar

- [ ] Four tabs: Home, Search, Messages, Profile. No web tab bar is visible on any page (Home, Search, Profile, post, inbox, thread, settings).
- [ ] Unselected tabs show outline glyphs; the selected one is filled (Home, Messages with the bolt knocked out) or bold (Search).
- [ ] Tab switches keep each tab's page and scroll position (scroll Home, visit Search and Profile, come back).
- [ ] Re-tapping the selected tab scrolls to top; again pops pushed pages; again at the root reloads Home, Messages and Profile behind a skeleton. Search does nothing more.
- [ ] A light haptic (selection tick) on tab changes and on pushes; going back has no haptic.

### Pushed pages

- [ ] Tapping a post, profile, comments ("View all … comments"), likes, a followers/following count, a hashtag, a location or a notification row pushes a page with the standard slide, a native back chevron and a title; no instant in-place swaps.
- [ ] Titles: "Post", "Comments", "Likes", the username on profiles and on followers/following lists, "Notifications", your username on the inbox, the other person's name on a thread, "New message", "Edit profile" (or Instagram's heading) on settings pages, "#tag" on hashtag pages.
- [ ] A #hashtag or location (caption, search result) pushes a page with a back chevron instead of jumping to the Search tab. Its post grid is hidden by the filter's Search rule (unchanged); note whether that page is still useful.
- [ ] Interactive swipe-back works on every pushed page, but only from the left screen edge. Swiping horizontally through a post carousel, the Stories tray or profile highlights never pops the page.
- [ ] Open a post or profile from Home, from a profile and from the inbox, then swipe back: the page underneath still shows what it showed before (no copy of the opened page, no reset to the top). If it did reset or reload once, note which page.
- [ ] Liking, following, opening the comment composer and expanding captions stay in the page (no push).
- [ ] Profile Posts/Tagged switching stays in the page.
- [ ] Open a profile's followers list, then swipe back: the profile shows no followers dialog left open underneath (if Instagram opens the list as an in-page dialog while the native push happens).
- [ ] No blank strip between the native header and the profile header (or any page's content) on pushed pages; on Home the first post sits right under the Stories tray with no gap or overlap.
- [ ] The web top bar is never visible on any page type.
- [ ] Reels links and the profile Reels tab do nothing, silently (no alert, nothing opens).

### Messages

- [ ] The inbox header compose button opens a new-message page.
- [ ] Inbox and thread pages have no duplicate web header, the composer works with the keyboard, and the tab bar does not cover the composer.
- [ ] A message thread hides the tab bar: it slides away with the inbox on push and comes back with the inbox on pop, including an interactive swipe-back; a cancelled swipe-back keeps it hidden. The composer sits at the bottom edge above the home indicator, not 49 pt above it.
- [ ] Pages opened from a thread (e.g. the other person's profile) also have no tab bar; popping back to the inbox restores it.

### External links, prompts and dialogs

- [ ] Bio links and links in captions open in an in-app Safari sheet with a Done/close button; closing it returns to the same page. App Store badges and "Open in app" prompts do nothing and show no alert.
- [ ] Email/phone buttons on business profiles open Mail/Phone.
- [ ] No "Open app" / "Use the app" / "Get the app" banners, no "See full profile in the app" dialog and no "Get the full experience" overlay on any page; the page scrolls normally.
- [ ] Real dialogs still appear and work: unfollow confirmation, post options menu, login challenge / two-factor code, "Save your login info?".

## Search

- [ ] Search opens with Instagram's search field and no web header above it; account results work. The field is a 36 pt rounded grey field with a magnifier and a grey "Search" placeholder; typing is 16 pt and the page does not zoom on focus. Only one magnifier.
- [ ] Focusing the field slides in "Cancel" at the right; Cancel clears the text, hides the keyboard, hides itself, and the caught-up view returns. Only one Cancel is visible.
- [ ] While idle (no focus, no query) the native caught-up view (ring check, "You're all caught up", grey text) shows below the field; it fades out on focus or typing.
- [ ] Results: 44 pt round avatars, bold username, grey full name below, verified badge kept. Dragging the results hides the keyboard but keeps the query.
- [ ] Tapping a result pushes that profile with a back chevron (no in-place swap); the first tap works even with the keyboard up.
- [ ] Submitting a keyword search (`/explore/search/keyword/?q=…`) pushes a results page titled with the query, with a back chevron; nothing strands you without a back control.
- [ ] No Explore media grid anywhere on the Search tab.

## Messages tab

- [ ] The tab shows the inbox with your username as the title and a compose button; no web header under it.
- [ ] Opening a thread pushes it on the Messages tab and hides the tab bar; back returns with the bar.
- [ ] The Home header Messenger icon switches to the Messages tab (no second inbox).
- [ ] The Home heart pushes Notifications on Home; its red dot shows for unread activity and clears after opening.
- [ ] Re-tapping Messages scrolls to top, then pops to the inbox, then reloads.
- [ ] Pull to refresh on the inbox.

## Notifications

- [ ] Opened from the Home heart, the pushed header reads "Notifications", with no web header under it. Opening Notifications or Settings never signs you out or resets the tabs.
- [ ] Rows: 44 pt round avatar, bold username, grey time, and a trailing 44 pt post thumbnail or a 32 pt rounded Follow (blue) / Following (grey) button, vertically centred.
- [ ] Pull to refresh holds and settles like Home.
- [ ] When Instagram has unread activity, a small red dot appears under the Home header heart within about 30 s (or on the next tab change); it clears when you tap the heart. Note whether the dot ever shows; if never, Instagram's m-web header exposes no indicator (DOM-NOTES, Unread activity).

## Profile

### Tab bar avatar

- [ ] The Profile tab shows your avatar in a 24 pt circle after the first page loads, with a thin ring and a small gap when selected; before the avatar is known it shows the person glyph.
- [ ] Relaunch in Airplane Mode: the Profile tab still shows your avatar immediately (disk cache).
- [ ] After Sign out, the Profile tab returns to the person glyph; relaunch keeps the glyph until you sign in again.

### Own profile

- [ ] Header: your username in bold on the left with a small down chevron, "+" (New post) and the menu on the right; no web header under it.
- [ ] The chevron opens Instagram's account switcher if Instagram's page has one; otherwise nothing happens (no error).
- [ ] "+" shows "Creating posts isn't available in this app."
- [ ] Menu opens an action sheet: Settings and activity (pushes Instagram's settings; note which page `/accounts/edit/` shows and whether `/accounts/settings/` would be the better hub), Content filters (opens the sheet), Sign out (asks to confirm).
- [ ] No blank strip between the native Profile header and your profile once the page has loaded and stopped changing.
- [ ] Pull to refresh holds and settles like Home.
- [ ] Profile header: 90 pt avatar, counts with bold numbers, bio, Edit profile / Share profile as two equal 32 pt rounded grey buttons.
- [ ] Posts / Tagged strip with Instagram's icons and a line under the selected one; no Reels tab.
- [ ] Grid: three columns of 3:4 portrait tiles with 1 pt gaps, edge to edge.

### Pushed profiles

- [ ] Profiles pushed from Search, a post or a comment get the same skin, with Follow (blue) / Following / Message buttons.

## Settings and filters

- [ ] Settings and other pushed pages have no duplicate web header.
- [ ] Settings → Change password (`/accounts/password/change/`) pushes normally and keeps its header; afterwards Home and Profile still behave as signed in (no tab reset after returning).
- [ ] Settings links to Accounts Center (`accountscenter.instagram.com`) open in the Safari sheet; note whether that page asks you to sign in again there.
- [ ] Instagram's own settings menu still contains "Following filter settings", which opens the native sheet.
- [ ] The Content filters sheet also opens from the Profile menu; it shows dark inset groups with outline icons.
- [ ] In the sheet, counts update, "Reload Home" reloads the feed, and Import following.json, Remove imported list, Sign in and Sign out (with confirmation) all work; importing and removing `following.json` changes filtering without restarting.

## Offline and recovery

### Loading

- [ ] Every page shows its skeleton while loading (feed cards, profile header + grid, search rows, inbox rows, list rows), then cross-fades to content.

### Offline

- [ ] Turn on Airplane Mode while on Home: a grey "No internet connection" strip slides in under the Home header (under the page header on other pages). Turning Airplane Mode off slides it away within a second or two.
- [ ] With Airplane Mode on, pull to refresh Home or open a profile: the page shows "Couldn't refresh feed" / "Couldn't load profile", "No internet connection…" and a blue Retry button (not a blank page and not Instagram's own error).
- [ ] Turning Airplane Mode off while that failure is showing reloads the page by itself, without tapping Retry.
- [ ] Retry while still offline shows the failure again after the load fails; it never leaves an endless skeleton.
- [ ] VoiceOver: the banner is announced when it appears; Retry reads "Retry, button"; while a skeleton or failure shows, swiping does not reach the hidden web page underneath.

### Foreground refresh

- [ ] Leave the app in the background for under 30 minutes (e.g. 5 minutes), return: every tab shows exactly what it showed, Home at the same scroll position; nothing reloads.
- [ ] Leave the app in the background for over 30 minutes, return on Home: Home reloads behind its skeleton and shows the top of a fresh feed (other tabs unchanged).
- [ ] Same, but return while on another tab: that tab is unchanged; Home reloads when you next tap it.
- [ ] After the app is backgrounded for a long time (web content process killed), returning reloads the page behind its skeleton instead of a blank view.

### Memory

- [ ] Push five or more pages in one tab (profile → post → profile → post → profile …), then swipe back one at a time: every page comes back with its content (deep pages briefly show their last image, then reload), and swipe-back keeps working.
- [ ] After a long session across all four tabs (many pushes, story views), the app is not killed in the background more often than before.
- [ ] With Home scrolled down, visit other tabs and use other heavy apps until iOS warns about memory (or use Xcode's Debug → Simulate Memory Warning on device): returning to Home reloads it near the previous scroll position where the reloaded feed is long enough; Search and Messages reload their pages.
- [ ] After such a memory warning, Search still hides the keyboard when you drag its results.
- [ ] With a link open in the Safari sheet, trigger a memory warning, then close Safari: the page underneath comes back from its snapshot and reloads (it was off screen), never blank.
