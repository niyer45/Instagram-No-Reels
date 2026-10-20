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
