# Static Search image

Reference found through image search: [Instagram caught-up design](https://brianlovin.com/writing/design-to-save-people-from-themselves-SVZYQV4).

`Resources/SearchCaughtUpDark.svg` is a local static dark adaptation of the circular gradient checkmark and caught-up layout. It has a transparent background, light text, no animation, no external image request, and no clickable older-posts control. The two-day wording matches the requested recent-post window.

Idle Search displays this image and suppresses its loading indicators. A typed account query or dialog removes the image; other tabs remove both the image and idle-only spinner suppression. The original search control, account results and bottom navigation are preserved.

The device check confirmed that the static SVG decoded and that no idle loading indicator was visible. The rendered on-device screen was inspected during development. The JavaScript suite has 50 checks.
