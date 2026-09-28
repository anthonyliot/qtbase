# 23 cocoa, ios: Honor QWindow::preferredFrameRate with exact display rates

| | |
|---|---|
| Commit | `cbace1505b6` (qtbase) |
| Files | `qappleframerate{.cpp,_p.h}`, `qcocoascreen{.h,.mm}`, `qcocoawindow{.h,.mm}`, `qiosscreen.mm`, `qioswindow{.h,.mm}`, `tst_qappleframerate.cpp` |
| Plan | Keep; squash 29, 30 into it |

## What
* `QAppleFrameRateRange::forPreferredFrameRate(fps, displayRate)`: maps the public rate to an exact
  rate `displayRate / n`, the slowest not below the preference (1% tolerance, so 23.976 → 24),
  default range when n = 1. (30 restricts n to divisors of the refresh rate.)
* `unitedWith(other, displayRate)`: two exact rates unite to their greatest common rate
  (`displayRate / gcd(n1, n2)`), so 24 + 60 on 120 Hz keeps the link at 120 and both exact.
* `QAppleFrameRatePreference::update()`: the public API wins over the property and env var.
* `QCocoaWindow`/`QIOSWindow::setPreferredFrameRate()`: apply the change to a pending request
  right away; `pacesUpdateRequests()`: true with an explicit preference (not for the env var
  default, which would switch every widget window to the paced path), and on macOS only with
  vsync on.
* macOS **nested event loop watchdog**: `deliverUpdateRequests()` starts a single-shot timer
  (`max(50 ms, 3 frames)`); it can only fire if an event loop runs inside the delivery. When it
  fires, `QCocoaScreen::requestUpdate()` returns false (windows use the timer fallback) and pending
  display-link windows get timer requests, until the delivery returns.

## Why
* "Nearest, not below" rather than "nearest": content at the preferred rate never has to skip a
  frame (25 fps video gets 30, not 24).
* gcd union: with a plain union the 60 fps UI wins and the 24 fps video is paced at 30 (every 2nd
  60 Hz frame is 30 fps, 24 isn't reachable), which is the classic 3:2 judder.
* The display link doesn't call back while its callback is on the stack, so a modal dialog opened
  from a paint event froze every paced window on the screen (review #2 M3).

## Risks and edge cases
* `displayRate` is `QScreen::refreshRate()` (the nominal maximum); on iOS it can be stale (m9).
* Mixing the private ranges with public-API windows can pace below a preference (m7) and depends
  on window order (m8): documented, private knobs only.
* The watchdog restores the display link only when the delivery returns; windows keep the timer
  path until their next request.

## Tests
`tst_qappleframerate::forPreferredFrameRate`, `unitedExactRates`, `preferenceFromPublicApi`;
`tst_qwindow` (25).
