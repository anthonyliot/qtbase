# 17 cocoa: Stop the fallback update timer once the display link delivers

| | |
|---|---|
| Commit | `925147b8de0` (qtbase) |
| Files | `qcocoascreen.mm`, `qcocoawindow{.h,.mm}` |
| Plan | Squash into 03 |

## What
`QCocoaWindow::stopFallbackUpdateTimer()` stops `QPlatformWindow`'s update timer when
`QCocoaScreen::requestUpdate()` succeeds, and right before the display link delivers.

## Why
Without an NSScreen (or, since 23, during a nested event loop), `QCocoaWindow` falls back to the
timer based `QPlatformWindow::requestUpdate()`. That timer keeps firing while a request is pending,
so once the link worked again the window got updates from both, ignoring its preference, and in
debug builds could hit the assert in `QPlatformWindow::deliverUpdateRequest()`.

## Tests
None automated for the NSScreen case (the link can't be made to fail on demand); the nested loop
case is covered by `requestUpdateDuringNestedEventLoop` (25).
