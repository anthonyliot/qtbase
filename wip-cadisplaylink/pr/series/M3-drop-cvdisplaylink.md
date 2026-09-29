# M3 darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink

| | |
|---|---|
| Repo, branch | qtmultimedia `wip/cadisplaylink` |
| Files | `src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm`, `avfdisplaylink_p.h` |
| Tree | S3 `dcbc502d19c3` (`pr/qtmultimedia-series/trees.txt`) |
| Change-Id | `Idbc052e25c70a48c05c121874e396abca0702b3f` (was the first commit, `2152cdbd8`) |
| From | review round 1, R1-10 (the original request: stop using CVDisplayLink) |

## What
Removes the `@available(macOS 15.0)` check and the CVDisplayLink fallback (creation, output
callback, `CVDisplayLinkStart/Stop`, release, the `m_cvDisplayLink` member and its include). macOS
always uses `-[NSScreen displayLinkWithTarget:selector:]` on the main screen, like 15.x did.

## Why
The NSScreen API is available from macOS 14.0, and the minimum deployment target is 14.4, so the
fallback isn't needed. CVDisplayLink is deprecated. CoreVideo stays linked (pixel buffer types).

It comes after M1 (the CADisplayLink path leaked, the CVDisplayLink one didn't) and M2 (the
CADisplayLink didn't fire in menus and modal sessions, the CVDisplayLink did), so that macOS 14.x
never gets either. The patch is unchanged (same +/- lines as `2152cdbd8`).

The message is corrected (round 6): it said the fallback "can never run", but it runs on 14.x; it
isn't *needed*. And (R7-3) it now says what else changes on 14.x: the display link calls back on
the main run loop, not on a thread of its own, and it's `NSScreen.mainScreen`'s (the screen with the
key window when it's created) instead of `kCGDirectMainDisplay` (the display with the menu bar).
Both as on macOS 15 and later, and M6 replaces the main screen with the video window's screen.

## Verified
Builds with no warnings in the changed file; S3 tested (TESTING.md, "Series states"). On macOS 27
upstream already took the CADisplayLink path, so the behavior here is unchanged.
