# M6 darwin: Poll for video frames in sync with the display the video is on

| | |
|---|---|
| Repo, branch | qtmultimedia `wip/cadisplaylink` |
| Files | `src/multimedia/platform/qplatformvideosink_p.h`, `src/multimedia/video/qvideowindow.cpp`, `src/multimediaquick/qquickvideooutput.cpp`, `src/plugins/multimedia/darwin/avfvideosink.mm`, `avfvideosink_p.h`, `mediaplayer/avfdisplaylink.mm`, `avfdisplaylink_p.h`, `avfvideorenderercontrol.mm`, `avfvideorenderercontrol_p.h`, `tests/auto/integration/qvideoframebackend/tst_qvideoframebackend.cpp` |
| Tree | S6 `f4801ada7da2`, the final tree (`pr/qtmultimedia-series/trees.txt`) |
| Change-Id | `Ie93c9ad86840e1f391993bdd6c1ebb02a7d79c92` |
| From | the user's question about `NSScreen.mainScreen` with several displays; review round 6 R6-2, R6-4, R6-8, R6-10; round 7 R7-5, R7-7, R7-8 |

## What
* `QPlatformVideoSink::setDisplayWindow(QWindow *)`: a hint telling the sink which window shows its
  frames. Unlike `setWinId()`, it doesn't make the sink render into that window.
* Callers: `QVideoWindow` (so QVideoWidget), and QML `VideoOutput` on `ItemSceneChange`, with its
  `QQuickWindow` as is. For a QQuickWidget that's the offscreen window, whose screen QQuickWidget
  keeps in sync with its own (`qquickwidget.cpp:191`, `:1885-1889`), so it follows the widget's
  screen. Round 6's `QQuickRenderControl::renderWindowFor()` was dropped (R7-7): it was read once and
  went stale when the widget moved to another top-level window.
* macOS: `AVFVideoSink` stores the window and forwards it to its interface; `AVFVideoRendererControl`
  hands it to `AVFDisplayLink::setWindow()`. `AVFDisplayLink` creates the display link of the
  window's screen, found with `QScreen::nativeInterface<QNativeInterface::QCocoaScreen>()->
  nativeScreen()`, and recreates it on `QWindow::screenChanged`, keeping it running if it was.
  Without a window, or when the screen isn't a cocoa screen (offscreen, minimal), it uses
  `NSScreen.mainScreen` at the time, as before. iOS is unchanged.

## Why
`AVFDisplayLink` paces how often the AVFoundation player polls for decoded frames. The main screen
is the one with the key window, so with several displays the video could be paced by another,
slower display. A private CoreAnimation SPI for per-display links was considered and rejected
(public API only). Round 6's NSView-link design was replaced: view links stop while the view is
hidden (R6-4), and casting `winId()` to an NSView crashed on the offscreen platform (R6-2).

## Limits (documented)
The decode link runs at the screen's maximum rate, which may keep a ProMotion panel above the
video's rate while playing with this backend (R6-6, follow-up: polling at exactly the content rate
risks sampling a frame late; can't be measured on a fixed-rate display). FFmpeg, the default
backend, has no decode display link.

## Tests, and what they don't cover (R7-5)
* `videoWindow_receivesFrames_whileHidden`: guards against going back to view links (it passes
  upstream too).
* `videoWindow_canBeDeleted_whilePlaying`.
* `videoWindow_receivesFrames_afterMovingToAnotherScreen` skips with one screen, and has never run
  here. It catches a recreation that breaks delivery, not a missing one: a link left on the old
  screen would still poll every frame of a 25 fps video. Its comment says so now.
* Not covered by any automated test: that the link follows the window's screen, the QVideoWidget
  child window with a real backend (`tst_qvideowidget` uses the mock backend), and the QML window
  change. To do when a second display is connected: a manual two-screen run with the video on the
  screen that isn't the main one, with a debug message naming the screen the link uses.

## Verified
TESTING.md, qtmultimedia section: probe (frames shown / hidden / shown again, preferred rate),
offscreen platform without a crash, both backends' suites.
