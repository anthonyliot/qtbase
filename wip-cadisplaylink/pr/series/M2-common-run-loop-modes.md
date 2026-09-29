# M2 darwin: Keep polling for video frames while menus and dialogs are open

| | |
|---|---|
| Repo, branch | qtmultimedia `wip/cadisplaylink` |
| Files | `src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm`, `tests/auto/integration/qvideoframebackend/tst_qvideoframebackend.cpp` |
| Tree | S2 `e4ea5041e0f5` (`pr/qtmultimedia-series/trees.txt`) |
| Change-Id | `I2e3535f843c182dced14d966ddd954787c9e5c70` |
| From | review rounds 7 (R7-3) and 8 (R8-3, R8-7) |

## What
`-[DisplayLinkObserver start]` and `-stop` schedule the display link in `NSRunLoopCommonModes`
instead of `NSDefaultRunLoopMode`, like qtbase's cocoa display link (`qcocoascreen.mm:327`).

## Why
A display link scheduled in the default mode doesn't fire while the main run loop runs in another
mode: `NSEventTrackingRunLoopMode` (a menu is open, a live resize) and `NSModalPanelRunLoopMode`
(`QDialog::exec()`, `QMessageBox`, native `QFileDialog`: a modal session). The AVFoundation
player then stops polling for frames, so the video freezes while the audio plays on. Qt delivers
the posted event the display link sends in the common modes (`qcocoaeventdispatcher.mm:784`,
`:801`; on iOS `qeventdispatcher_cf.mm:190`).

On iOS the common modes also include UIKit's tracking mode (`UITrackingRunLoopMode`), so the
video keeps playing while UIKit tracks a touch; the message says so (R8-7).

This was already the case on iOS and on macOS 15+ (CADisplayLink). On macOS 14 upstream used a
CVDisplayLink, which called back on its own thread, so M3, which removes it, would have made 14.x
freeze too. That's why M2 comes before M3.

## Tests
`tst_QVideoFrameBackend::playback_deliversFrames_whileRunLoopIsInMode(event tracking, modal panel)`:
plays `colors.mp4` and runs the main run loop in that mode for 1 s, expecting at least 10 frames.
Only on the cocoa platform: elsewhere (offscreen, minimal) Qt doesn't deliver its events from those
modes, so the test would fail for reasons unrelated to the video (R8-3). With the default mode (the
code before M2) the darwin backend gets 0 and 0 frames (log `/tmp/mm/r8/modes-test-default-mode.log`),
with the common modes both backends pass.

Real menus and modal sessions (`menuprobe`, TESTING.md): with the default mode, 1 frame in 1 s of an
open `NSMenu` and 0 in 1 s of `-[NSApp runModalForWindow:]`; with the common modes 30 and 25 (26 in
the normal event loop). The reviewer's AppKit probe (`/tmp/rv7/modes.mm`, rerun by the author): 0
callbacks in those modes with the default mode, about 237 per second with the common modes.

## Verified
TESTING.md, qtmultimedia section, "Series states", "Round 7" (the A/B), "Round 8" (the saved
default-mode logs, the real menu and modal session) and "Round 9" (counted on the main thread).
