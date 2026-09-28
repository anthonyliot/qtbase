# qtdeclarative 05 Document Window.preferredFrameRate and test it from QML

| | |
|---|---|
| Commit | `14a08b8318` (qtdeclarative) |
| Files | `src/quick/items/qquickwindow.cpp` (doc), `tests/auto/quick/qquickwindow/{tst_qquickwindow.cpp,data/preferredFrameRate*.qml}`, `tst_qquickanimations.cpp` |
| Plan | Keep; squash 06 into it. Needs qtbase 22 |

## What
* `\qmlproperty real Window::preferredFrameRate` (the property comes from QWindow): what it does
  on macOS/iOS, Animators may still render at the display rate, `undefined` resets, QQuickWidget
  only paces composition (use `createWindowContainer()` for full pacing).
* `tst_qquickwindow::preferredFrameRateFromQml` (binding, reset with `undefined`, binding that
  evaluates to `undefined`), `preferredFrameRateRevision` (`import QtQuick 6.12` doesn't see it),
  `preferredFrameRateOwnProperty` (a Window declaring its own `preferredFrameRate` loads).
* Animation tests use the public API, allow ≤ 2 unexpected steps (expose-driven frames), and the
  Animator test waits 300 ms after the first frame before starting (right after showing, the Metal
  swapchain doesn't block for a moment and the render thread rendered ~30 frames in 6 ms).

## Tests
`tst_qquickwindow` 127/127 (when no other app has focus), `tst_qquickanimations` 73/73; Animator
and steps tests 10/10 on 240 Hz, 15/15 on 120 Hz.
