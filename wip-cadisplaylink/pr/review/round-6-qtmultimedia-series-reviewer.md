# Round 6 review: qtmultimedia series (stream frame rate, QVideoWindow, per-view AVFDisplayLink)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, branch `wip/cadisplaylink`, base upstream `635067497`.

| # | Commit | Subject | Status |
|---|--------|---------|--------|
| 1 | `2152cdbd8` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | approved in R4, not re-reviewed except where commit 4 builds on it |
| 2 | `4a5411069` | Report the stream frame rate of played video frames | reviewed |
| 3 | `99534da15` | QVideoWindow: Drive the window's preferred frame rate from the video | reviewed again (R5 approved an earlier version; see R6-1, which R5 missed) |
| 4 | `fce7875de` | darwin: Poll for video frames in sync with the display the video is on | reviewed |

How I checked: I read `git show` for every commit and the files at HEAD. I checked the qtbase side
(`qwindow.cpp` preferredFrameRate docs, `qplatformwindow.cpp`, `offscreen/qoffscreenwindow.cpp`)
and the qtdeclarative side (`qquickwidget.cpp`). I read the author's probe (`/tmp/viewprobe/main.cpp`) and
the logs in `/tmp/qtmm-results/`. As instructed I did not build in or run from `qtmm-build`, and I
ran no GUI tests.

---

## Summary

Commit 2 is correct and cheap. Commit 4 is the right direction: the public
`-[NSView displayLinkWithTarget:selector:]` is the clean way to get a link that follows the video's
display, and the API shape (`QPlatformVideoSink::setDisplayWindow`) is minimal and correctly kept
apart from `setWinId`. Lifetime handling (QPointer, event filter, surface create/destroy, stop/start
around recreation) is mostly right.

But the series has two blockers and two majors:

* **R6-1 (blocker, commit 3)**: the preference is the *stream* rate, and `QWindow::preferredFrameRate`
  paces the window's update requests. At any `playbackRate > 1` the video window now renders fewer
  frames than the player delivers. For example, 25 fps at 2x gives 50 frames/s but only 30 are shown. This
  affects QVideoWidget/QVideoWindow users who never opted into anything, on both backends. It is worse
  on timer-paced platforms (X11/Android/eglfs), where 2x shows 25 frames/s.
* **R6-2 (blocker, commit 4)**: `reinterpret_cast<NSView *>(m_window->winId())` assumes the cocoa
  QPA. With `QT_QPA_PLATFORM=offscreen` (or `minimal`, `vnc`), `winId()` is a small integer
  (1, 2, 3...), and the darwin backend then sends an Objective-C message to it and crashes.
* **R6-3 (major, commits 1+4)**: `-[DisplayLinkObserver setDisplayLink:]` leaves a dangling
  `m_displayLink` when it is passed nil. Commit 4 makes this reachable: a recreation with
  `NSScreen.mainScreen == nil` makes the next `start()` message a freed object.
* **R6-4 (major, commit 4)**: the sink stops receiving frames (`QVideoSink::videoFrameChanged` is
  no longer emitted) while the window is hidden, and possibly while it is minimized or occluded. This
  is a behavior change for apps that don't use the feature. It isn't documented, and it is inconsistent with the
  FFmpeg backend and with the darwin backend without a window.

---

## Findings

| ID | Severity | Title | Commit |
|----|----------|-------|--------|
| R6-1 | blocker | Stream-rate preference throttles the video window below the delivered frame rate at playbackRate > 1 | 3 (with 2) |
| R6-2 | blocker | `winId()` cast to `NSView *` crashes on non-cocoa QPA plugins (offscreen, minimal) | 4 |
| R6-3 | major | `setDisplayLink:nil` leaves a dangling `m_displayLink`, which recreation with a nil `mainScreen` reaches | 4 (latent in 1) |
| R6-4 | major | Frames stop reaching the sink while the window is hidden (maybe also minimized or occluded); undocumented behavior change | 4 |
| R6-5 | minor | `avg_frame_rate` / `nominalFrameRate` under-estimates variable-frame-rate content, so the window drops frames in fast segments | 2, 3 |
| R6-6 | minor | AVFDisplayLink's own link still runs at the default (maximum) range, which may keep a ProMotion panel at 120 Hz (unverified) | 4 |
| R6-7 | minor | No automated test for commit 4 (surface recreation, hide/show, QVideoWidget child view, QML) | 4 |
| R6-8 | minor | QQuickWidget / QQuickRenderControl: the offscreen QQuickWindow has no handle, so VideoOutput keeps following the main screen | 4 |
| R6-9 | minor | Carry-over A5-2: the QML VideoOutput not driving the preference is still not documented | 3 |
| R6-10 | nit | eventFilter comment says the view is recreated "when it's hidden and shown"; on cocoa hide() doesn't destroy the platform window | 4 |

---

### R6-1: blocker: the stream-rate preference throttles the video window at playbackRate > 1

* Commits: `99534da15` (with `4a5411069` providing the rate).
* Where: `src/multimedia/video/qvideowindow.cpp:532`
  `setPreferredFrameRate(frame.surfaceFormat().streamFrameRate());`
* qtbase semantics (`qtbase/src/gui/kernel/qwindow.cpp:1279-1345`): the preference *paces the
  update requests the window makes with requestUpdate()*. When the rate can't be shown exactly,
  "the next faster such rate is used", so 25 becomes 30 on 60/120 Hz. On timer platforms "the preferred
  frame rate is the minimum interval between update requests". `QVideoWindow::setVideoFrame`
  renders by calling `requestUpdate()`, so it is paced by this preference.
* Scenario: a QVideoWidget (or QVideoWindow) plays a 25 fps file with
  `player.setPlaybackRate(2.0)`. Both backends then deliver about 50 frames/s to the sink: FFmpeg's
  renderer is paced by the time controller at the playback rate, and AVPlayer at rate 2.
  * Before this series: the window renders each frame, about 50 shown on a 60 Hz display.
  * After: the preference is 25, so pacing is 30 Hz on macOS/iOS and about 20 of every 50 frames
    are dropped. On X11/Android/eglfs the minimum interval is 40 ms, so 25 are shown and half are dropped.
  * At 4x on macOS, 30 of 100 frames are shown.
* This hits apps that never touched the new API, which the reviewer rules treat as a blocker. R5
  approved commit 3 without considering playback rate. Before commit 2 the rate was always 0 in real
  playback, so the problem never showed. Commit 2 activates it.
* The tests don't catch it: `videoWindow_preferredFrameRate_isSetDuringPlayback` only checks that
  the property equals the stream rate at 1x.
* Proposed fix, any of these:
  1. Have the backend tell the sink the effective delivery rate (`streamFrameRate * |playbackRate|`)
     separately from the stream rate, e.g. a private `QPlatformVideoSink` or `QVideoFramePrivate`
     field that QVideoWindow reads. Don't change the public meaning of `streamFrameRate`.
  2. In QVideoWindow, estimate the arrival rate of frames over a short window and set
     `max(streamFrameRate, measured arrival rate)`. Or set no preference while frames arrive faster
     than the preference.
  3. At minimum, don't set a preference when the frame's `endTime - startTime` doesn't match the
     wall-clock arrival interval.
* Resolved when a test plays `colors.mp4` (or a synthetic sink feed) at `playbackRate(2.0)` in a
  QVideoWindow and shows that the window's preferred rate is at least the delivery rate, or that no
  delivered frame is skipped by pacing, and the 1x test still passes.

### R6-2: blocker: `winId()` is cast to `NSView *` on any QPA plugin

* Commit: `fce7875de`.
* Where: `src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm:141-145`
  ```objc
  NSView *view = useWindow && m_window && m_window->handle()
          ? reinterpret_cast<NSView *>(m_window->winId())
          : nil;
  CADisplayLink *dl = view ? [view displayLinkWithTarget:...] : ...;
  ```
* Evidence: on macOS the offscreen QPA returns `m_winId = ++counter`
  (`qtbase/src/plugins/platforms/offscreen/qoffscreenwindow.cpp:30,133-135`). A platform window
  that doesn't override `winId()` returns `WId(1)` (`qtbase/src/gui/kernel/qplatformwindow.cpp:279-286`),
  which is the case for the minimal and other plugins. `handle()` is non-null on those plugins.
* Scenario: `QT_QPA_PLATFORM=offscreen QT_MEDIA_BACKEND=darwin` with a QVideoWindow (or a QML
  VideoOutput in a QQuickWindow) that is shown and playing. The sequence is: `show()`, then `create()`,
  then `SurfaceCreated`, then `recreateDisplayLink(true)`, then `objc_msgSend((NSView *)1, ...)`, which gives SIGSEGV.
  Headless CI and developer runs use offscreen on macOS; `tst_qvideoframebackend` itself would crash
  that way with the darwin backend.
* Fix: only take the view path when the platform is cocoa, e.g.
  `QGuiApplication::platformName() == u"cocoa"`, checked once. An alternative is a native interface
  accessor if one exists. Keep the main-screen fallback otherwise.
* Resolved when the check is in, and `tst_qvideoframebackend` passes (does not crash) with
  `QT_QPA_PLATFORM=offscreen QT_MEDIA_BACKEND=darwin`.

### R6-3: major: dangling `m_displayLink` when `setDisplayLink:` receives nil

* Commits: latent in `2152cdbd8` (reachable only at construction there, where it was harmless),
  made reachable by `fce7875de`.
* Where: `avfdisplaylink.mm:51-61`:
  ```objc
  if (m_displayLink) { [m_displayLink invalidate]; [m_displayLink release]; }
  if (displayLink)
      m_displayLink = [displayLink retain];   // nil: m_displayLink keeps the freed pointer
  ```
  Commit 4 now calls it again at run time with the result of
  `[NSScreen.mainScreen displayLinkWithTarget:...]`, which is nil when `NSScreen.mainScreen` is nil
  (no screen attached: headless Mac, display disconnected or reconfiguring). This happens in
  `setWindow(nullptr)`, in `SurfaceAboutToBeDestroyed`, and in `SurfaceCreated` before the view exists.
* Scenario: while playing, the video window's surface is destroyed (for example the window is deleted,
  `QWindow::destroy()` is called, or QVideoWidget is reparented or goes fullscreen, which recreates native windows) at a moment
  with no main screen. `recreateDisplayLink(false)` releases the old link, and `m_displayLink` still
  points to it. `start()` then calls `[m_displayLink addToRunLoop:...]` on a freed object. `dealloc`
  would also double-release it, except that `setDisplayLink:nullptr` hits the same path, so there is a
  second `invalidate` and `release` of a freed object.
* This relates to R4-1 (nil `mainScreen`). R4-1 was accepted as a harmless edge because there was no
  recreation at the time. It is now a use-after-free.
* Fix: `m_displayLink = [displayLink retain];` unconditionally (retaining nil is a no-op), or set
  `m_displayLink = nil` in the release branch.
* Resolved when that change is in. A trivial code fix is enough evidence.

### R6-4: major: the sink stops receiving frames while the window isn't visible

* Commit: `fce7875de`.
* Evidence: the author's own probe (`/tmp/viewprobe/main.cpp`) counts
  `window.videoSink()->videoFrameChanged` and reports "hidden: 0 frames in 1 s" after the commit,
  compared with 25 before. Those are frames of the public `QVideoSink` API, not just renders. The view-based link stops
  firing when the view isn't on screen. On cocoa `QWindow::hide()` doesn't destroy the platform
  window, so this comes from the NSView link pausing, not from the main-screen fallback. The probe
  didn't measure minimized or occluded windows.
* Scenario: the app didn't opt into anything. It shows video in a QVideoWidget in a QTabWidget page or
  QStackedWidget that isn't current, or in a minimized window, or a QML VideoOutput in a minimized
  QQuickWindow. It also listens to `videoSink()->videoFrameChanged` (analysis, thumbnails, recording,
  forwarding to another output) or reads `videoSink()->videoFrame()`.
  * Before: frames keep coming.
  * After, on the darwin backend: no frames until the window is visible again, and `videoFrame()` is stale.
  * The FFmpeg backend, and the darwin backend with a plain QVideoSink (no window), keep delivering. The
    behavior now depends on the backend and on the output type.
* Possible occlusion effect: if the NSView link also pauses when the window is fully covered (not
  measured), a video app behind another window gets no frames on the darwin backend.
* The commit message presents "none while hidden" as a benefit. That is a fair power argument for a
  pure display sink, but it changes observable public-API behavior, and that must be an explicit
  decision.
* Proposed fix, either:
  1. Keep the view link only while the window is exposed or visible. Fall back to a screen link of
     the window's screen, not `mainScreen`, while it isn't. Use `QWindow::visibleChanged`, the
     expose events, or `NSWindowDidChangeOcclusionStateNotification`. A screen link of the window's
     own screen also answers the user's "correct screen" question without the visibility coupling:
     `view.window.screen`, re-evaluated on `QWindow::screenChanged`.
  2. Or keep the new behavior, and state it in the commit message and in the known limitations or
     changes: "with the darwin backend, a video sink shown in a window gets no frames while the window
     isn't visible".
* Resolved when one of these is done. If option 1, the probe shows frames while hidden. In both cases
  the minimized and occluded behavior is measured and recorded.

### R6-5: minor: an average rate under-estimates variable-frame-rate content

* Commits: `4a5411069` (`qffmpegvideorenderer.cpp:79-82`, `avfvideorenderercontrol.mm:163-171`),
  used by `99534da15`.
* The two errors are not symmetric. Overestimating the rate is harmless: at worst there is no power
  saving. Underestimating it drops frames, because the window is paced to the preference.
  `avg_frame_rate` and `nominalFrameRate` are averages. A VFR screen recording that averages 20 fps
  with 60 fps motion segments gets a preference of 20, and the motion segments render at 20.
  `r_frame_rate` is usually the maximum rate for VFR, but can be absurd (1000/1 for millisecond
  timebases). An absurd value is harmless here: it is at or above the display rate, so it means no pacing.
* Consistency note (not a defect): `avg_frame_rate` matches the existing `QMediaMetaData::VideoFrameRate`
  (`qffmpegmediadataholder.cpp:161`) and `qffmpegframe_p.h:60`.
* Fix: for the preference, use `max(avg_frame_rate, r_frame_rate)` (clamped), or rely on the
  measured delivery rate from R6-1 option 2, which covers both issues.
* Resolved when the choice is made and noted in the commit message. Either fix, or "VFR content
  is paced to its average rate" as a documented limitation.

Also checked and found fine:
* float/double: `QVideoFrameFormat` stores `float`. 23.976 survives to within 1e-6, well inside
  qtbase's 1% tolerance, and the test accounts for it.
* Per-frame cost: before this commit the loop over `playerItem.tracks` ran only when
  `startTime >= 0`, but `copyPixelBufferFromLayer` returns a buffer only after rejecting negative item
  times, so it already ran for effectively every frame. There is no new cost.
* `QVideoFrameFormat::operator==` includes the frame rate (`qvideoframeformat.cpp:40`). The rate is
  constant within a stream, and no render path compares whole formats per frame: QQuickVideoOutput
  compares `pixelFormat()`, and the texture helper compares texture size and format. No test compares whole
  formats of played frames.
* HLS: `assetTrack` is nil for streamed tracks, which gives 0 (no preference). That is safe.

### R6-6: minor: AVFDisplayLink's own link may keep the panel at its maximum rate

* Commit: `fce7875de` (pre-existing; the commit reworks this link and leaves it as it was).
* The recreated link never sets `preferredFrameRateRange`, so it asks for the display's maximum. The
  author's own `AUDIT.md:35` and `PLAN.md:241-242` list "set the range from the video frame rate" as
  the follow-up for this link. `VIDEO.md:51` records that another link driving the panel keeps it
  from dropping.
* Scenario (unverified): with 24 fps film on a ProMotion panel with the darwin backend, the QVideoWindow asks
  for 24 but AVFDisplayLink's link, which is active whenever a layer is set, even when paused, asks for 120. The
  panel may stay at 120, which defeats the headline use case for this backend. The FFmpeg default
  backend has no such link.
* Fix: set the link's range from the stream rate, e.g. `{fps, max, fps}` with rounding up as in qtbase.
  Or measure it with `bench/panel-rate-ab.sh` and record the result as a limitation.
* Resolved when this is measured, and then either fixed or documented. Raise it to major if the panel is measured
  to stay at 120.

### R6-7: minor: no test for commit 4

* None of the commit's paths are exercised automatically:
  * surface recreation (`QWindow::destroy()` then `create()` while playing)
  * hide and show
  * deleting the window while playing
  * the QVideoWidget child view
  * the QML VideoOutput window change (`setDisplayWindow(nullptr)` on scene change)
* The listed runs (`tst_qmediaplayerbackend`, `tst_qvideowidget`, `tst_qquickvideooutput*`) pass.
  But `tst_qmediaplayerbackend` uses window-less sinks, so it only exercises the main-screen path.
* Ask: an integration test in `tst_qvideoframebackend` covering all of these:
  * a QVideoWindow plays `colors.mp4` (darwin and ffmpeg)
  * frames keep arriving after `window.destroy(); window.show();`
  * no crash when the window is deleted while playing
  * frames arrive in a shown QVideoWidget
  * (with R6-4 decided) the hidden-window behavior
* Resolved when that test is added.

### R6-8: minor: QQuickWidget and QQuickRenderControl fall back to the main screen

* Commit: `fce7875de`, `qquickvideooutput.cpp:471-474`.
* With QQuickWidget the item's window is the offscreen QQuickWindow, which never has a handle
  (`qtdeclarative/src/quickwidgets/qquickwidget.cpp:1329` asserts `!offscreenWindow->handle()`).
  `recreateDisplayLink` therefore correctly takes the main-screen path, so this is not a crash. But the fix
  doesn't apply to QQuickWidget or render-control apps.
* Fix: pass `QQuickRenderControl::renderWindowFor(m_window)` when it isn't null. Otherwise document it.
* Resolved when one of these is done.

### R6-9: minor: carry-over A5-2 not documented

* `pr/README.md` still says nothing about qtmultimedia's QVideoWindow integration or about QML
  VideoOutput not setting a preference. Commit 4 now makes VideoOutput call `setDisplayWindow`, which
  makes the difference from QVideoWindow easier to miss.
* Resolved when a line is added to the known limitations.

### R6-10: nit: eventFilter comment

* `avfdisplaylink.mm:120-121`: "which the window destroys and creates again, e.g. when it's hidden
  and shown". On cocoa `QWindow::hide()` keeps the platform window. It is destroyed by `destroy()`,
  deletion, or reparenting and native-window recreation (e.g. QWidget flag changes). Reword it.

---

## Other questions from the brief

* **API shape**: `QPlatformVideoSink::setDisplayWindow(QWindow *)` next to `setRhi()` is the right,
  minimal private hook. Both are "information from the output about where frames go", and both are called from the
  same two places. Reusing `setWinId` would be wrong, because on Windows EVR it means "render into
  this window". Accepted.
* **Lifetime**:
  * `QPointer<QWindow>` in both `AVFVideoSink` and `AVFDisplayLink`: correct.
  * `~QWindow` calls `destroy()`, which sends `SurfaceAboutToBeDestroyed` while the QPointer is still set.
    The view link is therefore replaced before the view dies, and the filter is removed automatically on destruction.
  * `setWindow` removes the old filter.
  * `winId()` is guarded by `handle()`, so no platform window is created by accident.
  * stop/start around recreation is correct.
  * No double delivery: `m_framePending` coalesces, and `stop()` clears it, so a stale posted event is dropped.
  * `AVFVideoSinkInterface::setVideoSink(nullptr)` resets the window. Virtual dispatch isn't used from
    a destructor.
* **Threading (not raised)**: `installEventFilter` and `[NSView displayLinkWithTarget:]` assume that
  the player and the window are on the main thread. A QMediaPlayer on a worker thread would get a
  Qt warning and an AppKit call off the main thread. That is an unusual setup and the old code already
  added the link to the worker's run loop, so I don't raise it, but a `Q_ASSERT`/`qWarning` would be cheap.
* **iOS**: unaffected. `setWindow` installs a filter that does nothing, and the UIKit construction is unchanged.
* **QVideoWidget**: the sink's window is the embedded child QVideoWindow. Its `winId()` is its own QNSView,
  which is a subview of the container's view. An NSView link tracks the view's window's screen, so it follows.
  The child platform window is created when the container is shown. That takes the `SurfaceCreated` path and
  moves the link from the main screen to the view. By reading, this is correct. It is not tested (R6-7).
* **SPI question**: the author's answer is correct. An SPI that takes a display ID still needs the right
  display and must be re-targeted on screen changes. The public NSView link does both automatically.
  One public alternative wasn't discussed: a link from the *window's* `NSScreen`,
  re-created on `QWindow::screenChanged`. It is also correct-screen, and it doesn't couple delivery
  to visibility (see R6-4). Record the trade-off in the commit message.
* **Commit order and self-containedness**:
  * Commit 2 (`git show 4a5411069`) uses only the existing `setStreamFrameRate`.
  * Commit 3 uses `QWindow::setPreferredFrameRate` (qtbase dependency, stated in the message).
  * Commit 4 adds the virtual function and all its overrides in one commit. At commits 2 and 3 neither
    the header nor the renderer references `setDisplayWindow`.
  * Each commit builds on its own, as far as I can tell by reading. I didn't compile, per the instruction.
* **Commit messages**: imperative, why before how, Change-Ids present. Commit 4's message should
  mention the hidden-window consequence (R6-4) and the non-cocoa fallback once R6-2 is fixed.
  Commit 2's message is accurate.
* **Tests**: `videoWindow_preferredFrameRate_isSetDuringPlayback` would have failed before commit 2,
  because `QTRY_VERIFY(streamFrameRate > 0)` times out when backends leave the rate at 0. It is a meaningful test.
  `followsStreamFrameRate` covers the A5-1 fix (a null or zero rate resets the preference). Neither covers
  the playback rate (R6-1).
* **Evidence**:
  * `/tmp/qtmm-results/tst_qvideoframebackend-darwin.log`: 15/15 pass. It is timestamped 20:06, so I couldn't
    confirm it was run against the final commit 4 binaries.
  * `tst_qmediaplayerbackend-darwin-full.log` is still in progress (it had reached the invalid-media rows at 21:03).
    Its `invalidHttpsAddress` failures match the stated baseline.
  * The probe's BEFORE figure "shown 24 fps" for a 25 fps file isn't explained. A main-screen poll at 60 Hz or
    more should still give 25. It doesn't block anything, but it suggests the BEFORE setup (which display was
    main, and its rate) should be recorded with the A/B.

---

## Verdict: REQUEST CHANGES

Severity counts: blocker 2, major 2, minor 5, nit 1.

- R6-1: blocker: stream-rate preference throttles the video window below the delivered rate at playbackRate > 1 (commit 3, with 2)
- R6-2: blocker: `winId()` cast to `NSView *` crashes on non-cocoa QPA plugins (offscreen, minimal) (commit 4)
- R6-3: major: `setDisplayLink:nil` leaves a dangling `m_displayLink`, which recreation with a nil `mainScreen` reaches (commit 4, latent in 1)
- R6-4: major: sink gets no frames while the window is hidden (maybe also minimized or occluded); undocumented behavior change (commit 4)
- R6-5: minor: average frame rate under-estimates VFR content, so fast segments are dropped (commits 2, 3)
- R6-6: minor: AVFDisplayLink's link still asks for the maximum rate and may keep ProMotion at 120 Hz (unverified) (commit 4)
- R6-7: minor: no automated test for commit 4's paths (commit 4)
- R6-8: minor: QQuickWidget / render control keep the main-screen fallback (commit 4)
- R6-9: minor: A5-2 (QML VideoOutput doesn't set a preference) still undocumented (commit 3)
- R6-10: nit: eventFilter comment wrongly says hide/show recreates the view (commit 4)
