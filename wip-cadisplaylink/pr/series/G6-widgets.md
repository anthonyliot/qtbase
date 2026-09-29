# G6 Widgets: Pace top-level updates when the window has a preferred rate

| | |
|---|---|
| Files | `src/widgets/kernel/{qwidget.cpp,qwidget_p.h,qwidgetrepaintmanager.cpp,qwidgetrepaintmanager_p.h,qwidgetwindow.cpp}`, `src/gui/kernel/qwindow.cpp` (the Widgets paragraph of the property doc), `tst_qwidgetrepaintmanager.cpp` |
| From | old 24, 32; R1-8, R1-13, R2-3 |

See the old 24 document for the design. Changes since:
* No `QT_WIDGETS_PACED_UPDATES` switch (R1-13).
* `pacedUpdatesAfterRecreate` fails if pacing is lost after recreation (R1-8).
* `pacedUpdates` checks the paced interval exactly.
* The Widgets paragraph of `QWindow::preferredFrameRate` is part of this commit, as it describes
  this behavior (R2-2).

## Verified
TESTING.md, series section.
