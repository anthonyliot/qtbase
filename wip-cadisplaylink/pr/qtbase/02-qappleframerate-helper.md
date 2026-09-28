# 02 Add QAppleFrameRateRange helper for display link frame-rate intent

| | |
|---|---|
| Commit | `efae5dc0bdf` (qtbase) |
| Files | `src/gui/platform/darwin/qappleframerate{.cpp,_p.h}`, `src/gui/CMakeLists.txt`, `tests/auto/gui/platform/qappleframerate/*`, `tests/auto/gui/platform/CMakeLists.txt` |
| Plan | Keep; squash 15 (rounding fix) into it |
| Later changed by | 09 (`effectiveFrameInterval`), 15 (rounding), 23 (public API mapping, gcd union), 30 (supported rates) |

## What
A private, plain C++ model of `CAFrameRateRange` shared by the cocoa and ios plugins:
`QAppleFrameRateRange` (validation, parsing, union, pacing) and `QAppleFrameRatePreference`
(per-window state: which range the window wants, when it last got a frame). Not used yet.

## Why
* `-[CADisplayLink setPreferredFrameRateRange:]` throws `NSInvalidArgumentException` on invalid
  ranges, so anything that comes from applications must be validated in C++ first.
* One display link per screen is shared by all windows on it: their ranges must be united, and
  windows wanting less than the link's rate must skip frames. That logic is the same on macOS and
  iOS, and testable without a display, so it lives in QtGui (Apple only), not in each plugin.

## How
* `isValid()` mirrors CoreAnimation's validation, measured with `wip-cadisplaylink/probes/valid.m`
  (default 0,0,0 is valid; minimum > 0 and finite; maximum >= minimum, may be infinite; preferred
  0 or within [min, max]).
* `fromVariant()`/`fromString()`: number, `[min, max(, preferred)]`, map with
  `minimum`/`maximum`/`preferred`, strings `"60"`, `"30,120"`, `"30,120,60"`, `"default"`.
  Unknown map keys are rejected (typos).
* `unitedWith()`: default wins (the system may run at the maximum), otherwise max of minimums and
  maximums, and the faster preferred rate.
* `shouldDeliverFrame(lastTarget, target, linkInterval)`: deliver when at least
  `frames - 0.5` link intervals elapsed since the last delivered target timestamp.
* `QAppleFrameRatePreference::update(window)` re-reads `_q_preferredFrameRateRange`, falling back
  to `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` (read once), and warns once per invalid value.
* Logging category `qt.qpa.framerate`.

## Risks and edge cases
* Exported (`Q_GUI_EXPORT`) private API, used by plugins; `_p.h` only.
* `QJSValue` from QML doesn't compare equal to itself, so the "warn once" logic tracks validity
  rather than comparing values.
* Timestamps going backwards (link recreated) deliver immediately.

## Tests
`tst_qappleframerate`: validation table, parsing of every supported form, union, pacing over long
sequences with and without timestamp jitter, `QAppleFrameRatePreference` from the property and
the environment. Runs without a display (Apple only, `if(APPLE)` in CMake).

## Verify
`tst_qappleframerate` → all pass (136 at the branch head).

## Questions for the reviewer
* Is QtGui (`src/gui/platform/darwin`) the right home, rather than a header shared by the two
  plugins?
