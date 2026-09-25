# Notes for resuming with Claude Code

Paste or point Claude at this file when you continue the work on another machine.

## Context

* User goal: pro apps built with Qt on macOS shouldn't rely on the deprecated CVDisplayLink.
  Qt should use CADisplayLink (and later CAMetalDisplayLink), and apps must be able to control
  their FPS, so the macOS scheduler can arbitrate on 240 Hz displays instead of every app running
  flat out.
* Constraint: no public Qt API changes for now. Private mechanism now (`_q_preferredFrameRateRange`
  dynamic property + `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` env), public API proposal for later.
* Work is split into separate commits (see PLAN.md). Docs live in this directory (first commit).

## Decisions made (and why)

* **Per-screen NSScreen CADisplayLink, not per-NSView.** View links stop when the window isn't on
  screen, which would change `requestUpdate()` semantics for hidden windows (measured, see
  AUDIT.md).
* **No fallback to CVDisplayLink.** Qt's minimum macOS is 14.4, and CADisplayLink on macOS is 14.0.
* **Validate ranges in Qt** with rules measured from CoreAnimation, since invalid ranges throw
  `NSInvalidArgumentException`.
* **Mixed windows**: the link range is the union of the pending windows' preferences, and each
  window is paced with `targetTimestamp` (half-frame tolerance), so 30 fps and 240 fps windows
  coexist. Measured: a 100 fps request snaps to 120 on a 240 Hz panel. The pacing tolerance gives
  the same result.
* **Link paused when idle** (was: CVDisplayLink kept running). Unpausing is immediate (measured).
* Kept the live-resize `CGEventTap` workaround in `QCocoaScreen::requestUpdate()`. It was written
  for the GCD source, and with the CADisplayLink run-loop source it should be re-validated with
  live resize. If live resize is fine without it, remove it in a follow-up.

## Environment used

* macOS 27.2, Xcode 27.2, M5 Max, Samsung Odyssey G95SC at 240 Hz
* Build dir: `../qt5-build-cadisplaylink` (Unix Makefiles, Debug, developer build, tests on demand)
* Qt Quick: `../qt5-build-nofw` (qtbase, no frameworks), `../qt5-build-nofw-qtshadertools`,
  `../qt5-build-nofw-qtdeclarative`
* Forks: `anthonyliot/qt5` (branch pins qtbase + qtdeclarative), `anthonyliot/qtbase`,
  `anthonyliot/qtdeclarative`, all on branch `wip/cadisplaylink`
* Baseline `tst_qwindow`: 64 pass / 6 fail (focus-related, pre-existing) / 7 skip

## Gotchas found along the way

* `QTest::qWait()` sleeps 10 ms between event processing rounds, which caps update request
  delivery at ~50-100/s. Rate tests have to spin a real `QEventLoop` (`spinEventLoop()` in
  tst_qwindow).
* The macOS build hides missing includes through the plugin/QtGui precompiled headers. The iOS
  build doesn't (that's how the missing `<QtCore/qmap.h>` in qappleframerate.cpp was found).
* CoreAnimation rounds non-divisor rates *up* (24@60 → 30, 100@240 → 120). The tests use
  `achievableRate()` for this.
* zsh doesn't word-split `$VAR`, use `${=VAR}` when passing test function lists.
* **Qt Quick needs qtshadertools built**: qtdeclarative lists it as optional, but without `qsb`
  the Quick modules are silently skipped (`Qt Quick support ... no`).
* **Building qtdeclarative against the framework (default) non-prefix qtbase build fails in moc**
  ("Undefined interface" for `QQmlParserStatus`, `QTextObjectInterface`, ...): `-I lib/QtQml.framework`
  comes before `-I include`, so moc picks the framework's `#include_next` forwarding header and
  doesn't follow it. It's unrelated to this work (fails in QtQmlMeta). Workaround: a separate
  `-DFEATURE_framework=OFF` qtbase build for qtdeclarative work (`../qt5-build-nofw*`).
* qtdeclarative configure inherits `QT_BUILD_MANUAL_TESTS` from the qtbase build, and its manual
  tests fail to configure. Pass `-DQT_BUILD_MANUAL_TESTS=OFF`.
* Commit hooks run clang-format and the Qt sanity bot. `QT_DECLARE_NAMESPACED_OBJC_INTERFACE` needs
  `// clang-format off`.

## Status

See `git log origin/dev..wip/cadisplaylink` and the "Status" section in PLAN.md.
