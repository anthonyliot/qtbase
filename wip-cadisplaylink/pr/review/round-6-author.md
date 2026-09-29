# Round 6: author's response (qtmultimedia series)

Verdict received: REQUEST CHANGES (blocker 2, major 2, minor 5, nit 1). All verified against the code
before acting; all accepted. Summary: 2 blockers and 2 majors fixed with tests, R6-7/R6-8/R6-10 fixed,
R6-5/R6-6/R6-9 documented with reasons. Baselining the fixes also found a pre-existing leak, now M1.

## The series now

Five commits on upstream `635067497`, recorded as trees (`/tmp/mm/series2-trees.txt`) because
signing is blocked (see the end). Each state is built and tested (TESTING.md, qtmultimedia).

| # | Subject | Tree | Round 6 items |
|---|---|---|---|
| M1 | darwin: Don't leak the display link of AVFDisplayLink | `47653cfd479b` | R6-3, and the leak below |
| M2 | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | `a1e88291a4f3` | (was `2152cdbd8`, same patch) |
| M3 | Report the stream frame rate of played video frames | `198815449c08` | |
| M4 | QVideoWindow: Drive the window's preferred frame rate from the video | `6102ba5d546f` | R6-1, R6-5 (message), R6-7 |
| M5 | darwin: Poll for video frames in sync with the display the video is on | `3b2fda1ab1a4` | R6-2, R6-4, R6-7, R6-8, R6-10 |

Messages: `/tmp/mm/{m1,m2,c3,c4,c5}.txt`. Per-commit documents: `pr/series/M1…M5`.

| ID | Response |
|---|---|
| R6-1 blocker | **Fixed** (M4). Preference = stream rate × \|playbackRate\| of the source QMediaPlayer (new private `QVideoSink::source()`, friend `QVideoWindow`). Test `videoWindow_preferredFrameRate_followsPlaybackRate` (2×), which fails without the fix. |
| R6-2 blocker | **Fixed by redesign** (M5). No `winId()` cast: the link comes from `QScreen::nativeInterface<QNativeInterface::QCocoaScreen>()->nativeScreen()`, null on other platforms (then the main screen). The probe under `QT_QPA_PLATFORM=offscreen QT_MEDIA_BACKEND=darwin` runs without crashing (0 frames, like upstream in the same configuration, checked by A/B). |
| R6-3 major | **Fixed** (M1), together with the leak it's needed for: `m_displayLink = [displayLink retain];` unconditionally. Not a separate commit any more: M1's `setDisplayLink:nil` in the destructor would message a released link without it. |
| R6-4 major | **Fixed by redesign** (M5), your suggested alternative: the display link of the *window's screen*, recreated on `QWindow::screenChanged`. Screen links keep firing while the window is hidden, like the main screen's before. Probe: 25 fps shown, **25 hidden** (0 with the view link), 25 shown again. Test `videoWindow_receivesFrames_whileHidden`. |
| R6-5 minor | **Documented** (M4 message, M4 document, README): VFR content reports its average rate, so faster segments may be paced below their rate. `r_frame_rate` often is a timebase-like value, so it isn't used. |
| R6-6 minor | **Documented as a follow-up** (M5 document, README): pinning the decode poll to the content rate would let the panel drop on ProMotion, but polling at exactly the frame rate risks sampling a frame late and skipping the next. Can't be measured on the connected fixed-rate 240 Hz display. Only the AVFoundation backend is affected; FFmpeg (the default) has no decode display link. |
| R6-7 minor | **Fixed**: `videoWindow_receivesFrames_whileHidden`, `videoWindow_canBeDeleted_whilePlaying`, `videoWindow_receivesFrames_afterMovingToAnotherScreen` (skips with one screen), `tst_QVideoWidget::preferredFrameRate_followsStreamFrameRate`. Surface recreation no longer matters (screen link). The QML window change isn't covered by a new test (tst_qquickvideooutput* pass). |
| R6-8 minor | **Fixed** (M5): `QQuickVideoOutput` passes `QQuickRenderControl::renderWindowFor(window)` when there is one. |
| R6-9 minor | **Documented** (M4 document, README): QML VideoOutput sets no preference (the window is the whole scene's; an app sets `Window.preferredFrameRate`). |
| R6-10 nit | Gone with the event filter. |

## Found while baselining: AVFDisplayLink leaked its display link (now M1)

A display link retains its target until invalidated; the observer (the target) only invalidated
its link in `dealloc`, which never ran, so every media player leaked an observer and a display
link. Upstream on iOS and macOS 15+. The old commit 1 would have extended it to macOS 14.x, where
upstream used CVDisplayLink and released it, so the fix comes first and the CVDisplayLink removal
moves to M2. Measured with heap(1): 20 players leave 20 observers and 20 CADisplayLinks upstream
and without the fix, 0 and 0 with it (TESTING.md, "AVFDisplayLink leak").

M2's message is also corrected: it said the fallback "can never run", which is wrong (the
`@available(macOS 15.0)` check sends every 14.x to it); it isn't *needed*.

## Evidence caveats you raised

* Unbaselined darwin failures: A/B'd against upstream, interleaved (TESTING.md, "Upstream A/B"):
  same failure families on both, and upstream additionally hung once in
  `destruction_doesNotDeadlock_afterMediaPlayerCall` (watchdog abort). Not the series.
* Probe setup: one display, the 240 Hz Odyssey G95SC (main, fixed rate). The BEFORE run's 24 vs 25
  is counting a 1 s window starting mid-stream (±1 frame), not a rate difference.

## Signing

AppleConnect signing is blocked (two 10-minute attempts without the prompt being answered), so the
commits aren't created yet. `/tmp/mm/commit-series2.sh` makes them: it stages each state from its
recorded tree, checks the tree before and after each signed commit, stops at the first failure,
and resumes from what's already committed.
