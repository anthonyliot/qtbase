# 22 Add QWindow::preferredFrameRate

| | |
|---|---|
| Commit | `71f67301a9b` (qtbase) |
| Files | `src/gui/kernel/qwindow{.h,.cpp,_p.h}`, `qplatformwindow{.h,.cpp,_p.h}` |
| Plan | Keep; needs Qt API review |
| Later changed by | 30 (docs: which rates are exact) |

## What
Public API, `\since 6.13`:

```cpp
Q_PROPERTY(qreal preferredFrameRate READ preferredFrameRate WRITE setPreferredFrameRate
           RESET resetPreferredFrameRate NOTIFY preferredFrameRateChanged REVISION(6, 13))
void setPreferredFrameRate(qreal framesPerSecond);
qreal preferredFrameRate() const;
void resetPreferredFrameRate();
Q_REVISION(6, 13) void preferredFrameRateChanged(qreal preferredFrameRate);
```

QPA (no compatibility promise): `virtual void QPlatformWindow::setPreferredFrameRate(qreal)` and
`virtual bool QPlatformWindow::pacesUpdateRequests() const`.

## Why
The goal of the whole PR: an application (video player, editor, game) tells Qt how often a window
needs to render, and Qt tells the system, which picks the display refresh rate. A single number
in frames per second is what applications think in (24000/1001 for film); ranges and content
types were considered and deferred (`DESIGN.md`).

## How
* The value lives in `QWindowPrivate` (so it exists before the platform window), is forwarded to
  the platform window when it changes, and read from `window()` when pacing.
* Negative or non-finite values warn and become 0; setting the same value doesn't emit.
* Not `FINAL`: QML `Window` subtypes that declare their own `preferredFrameRate` would otherwise
  fail to load under every import version (review #2 M1).
* Timer platforms (`QPlatformWindow::requestUpdate()`): the next timer is at least
  `1/fps - (time since the last delivery)` away (nanosecond `QBasicTimer`, capped at one hour),
  and during delivery `updateRequestInterval = max(1/fps, 1/refresh)`.
* `QPlatformWindow::setPreferredFrameRate()` re-arms a pending timer, so raising the rate from
  1 fps doesn't wait up to a second.
* `pacesUpdateRequests()` defaults to false.

## Risks and edge cases
* It's a hint: the system may deliver less (Low Power Mode, occlusion, slow rendering).
* Platforms that implement `requestUpdate()` themselves without calling the base (Wayland,
  Windows with Direct3D vsync, WebAssembly) ignore it; documented.
* Setting it doesn't request an update.
* `lastUpdateRequestDelivery` is started in `deliverUpdateRequest()` on every platform.

## Tests
25 (`tst_qwindow`), qtdeclarative 05 (QML).

## Questions for the reviewer
* Naming and type: `preferredFrameRate` as `qreal` fps vs. an interval, or a range type.
* Should 0 mean "no preference" (current) and should there be a way to say "as fast as possible"?
