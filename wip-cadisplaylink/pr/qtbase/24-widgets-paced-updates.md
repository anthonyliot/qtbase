# 24 Widgets: Pace top-level updates when the window has a preferred rate

| | |
|---|---|
| Commit | `1060540e5eb` (qtbase) |
| Files | `src/widgets/kernel/qwidget{.cpp,_p.h}`, `qwidgetrepaintmanager{.cpp,_p.h}`, `qwidgetwindow.cpp`, `tst_qwidgetrepaintmanager.cpp` |
| Plan | Keep |

## What
When `usesPacedUpdateRequests()` is true for a top-level, `QWidget::update()` schedules the sync
with `QWindow::requestUpdate()` instead of posting `QEvent::UpdateRequest` to the widget.

`usesPacedUpdateRequests()`: the top-level has a platform window, isn't paint-on-screen, isn't
`WA_DontShowOnScreen`, isn't in a graphics view proxy, and the platform window
`pacesUpdateRequests()` (or `QT_WIDGETS_PACED_UPDATES=1`; `=0` disables).

## Why
Widgets never used `requestUpdate()`, so a window's preferred frame rate had no effect on them,
including `QOpenGLWidget`/`QRhiWidget` content, which many video applications use.

## How
* `sendUpdateRequest(UpdateLater)` for the top-level: remember that the window's pending request
  is ours (`windowUpdateRequested`, only if none was pending), call `requestUpdate()`, and set
  `updateRequestSent`. If the window didn't take it, post the event as before.
* `QWidgetWindow::event(UpdateRequest)`: if the request is ours (`takeWindowUpdateRequest()`,
  taken before the sync so that an `update()` during it schedules the next frame the same way),
  forward it to the widget (`QWidget::event()` → sync, so event filters and overrides still see
  it) only if ours was sent or something is dirty. Otherwise, as before, `repaint()` (a request
  someone else made on the window).
* `QTLWExtra::preferredFrameRate` keeps the value when the `QWidgetWindow` is deleted and
  recreated (e.g. reparenting), reapplied in `createTLSysExtra()`.

## Risks and edge cases
* `update()` then `repaint()` (buttons, progress bars): the repaint syncs, the paced request then
  finds nothing to do (no second paint; review #2 M4).
* An external `windowHandle()->requestUpdate()` coinciding with ours only syncs the dirty regions,
  not a full repaint.
* `repaint()` isn't paced (unchanged), except that windows with texture-based children may
  already defer it to the next frame.
* Only cocoa/ios pace today; everywhere else nothing changes (base `pacesUpdateRequests()` is
  false).
* Not covered yet: a `QT_WIDGETS_PACED_UPDATES=1` test target for the opt-outs, hide/recreate
  while pending, and QOpenGLWidget `frameSwapped` (review #2 m13).

## Tests
`tst_qwidgetrepaintmanager::pacedUpdates` (raster, QRhiWidget; skipped without Metal),
`pacedUpdatesSemantics` (sync count, update+repaint paints once, no loop),
`pacedUpdatesAfterRecreate` (reparenting, adding a QRhiWidget).
