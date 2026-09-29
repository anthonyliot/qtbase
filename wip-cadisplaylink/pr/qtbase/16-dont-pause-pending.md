# 16 cocoa, ios: Don't pause the display link while a request is pending

| | |
|---|---|
| Commit | `7862556b859` (qtbase) |
| Files | `qcocoascreen{.h,.mm}`, `qiosscreen{.h,.mm}`, `tst_qwindow.cpp` |
| Plan | Keep as its own commit (fixes a bug that predates this work) |

## What
Before pausing the link after a delivery pass, look at all windows again
(`updateDisplayLinkFrameRate()` now returns whether any window has a pending request).

## Why
A window looked at earlier in the pass can get a request while another window's request is
delivered (one window driving another). Its request is then already pending, so it never reaches
`QCocoaScreen::requestUpdate()` again, and with the link paused the window froze. The same bug
existed with CVDisplayLink (the test fails there too); pausing when idle (03) made it matter more.

## Tests
`tst_qwindow::requestUpdateForOtherWindowDuringDelivery`.
