# Round 4 review — qtmultimedia CVDisplayLink removal (resolves R1-10)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Scope: one commit, qtmultimedia `wip/cadisplaylink`
Commit: `2152cdbd8` "darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink"
Base: upstream `635067497` ("Update dependencies on 'dev' in qt/qtmultimedia")
Files: `src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.{mm,_p.h}`

## Context

This is the follow-up the author committed to in R1-10: qtmultimedia's
`AVFDisplayLink` still carried a CVDisplayLink fallback for macOS 14.x, guarded
by `if (@available(macOS 15.0, *))`. The commit deletes that fallback and uses
`-[NSScreen displayLinkWithTarget:selector:]` unconditionally on macOS
(iOS/UIKit path was already CADisplayLink and is untouched).

## Verification

### 1. Correctness of the removal — availability floor (CONFIRMED)

* Minimum deployment target: `qtbase/.cmake.conf:58`
  `set(QT_SUPPORTED_MIN_MACOS_VERSION "14.4")`.
* The API's availability, straight from the AppKit SDK header
  (`.../AppKit.framework/Headers/NSScreen.h`):

  ```objc
  API_AVAILABLE(macos(14.0))
  @interface NSScreen (NSDisplayLink)
  - (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector ...;
  @end
  ```

  So the category — and the method — is annotated `macos(14.0)`.
* 14.0 <= 14.4, therefore the `@available(macOS 15.0, *)` guard was always true
  at runtime on any supported system and the CVDisplayLink `else` branch was
  dead code. Removing it is correct. The author's claim (API is macos(14.0),
  floor is 14.4) is accurate.

### 2. No CVDisplayLink usage left; CoreVideo correctly kept (CONFIRMED)

* Grepped the whole darwin plugin. The only remaining occurrence of the string
  "CVDisplayLink" is the explanatory comment at `avfdisplaylink.mm:93`. No
  `CVDisplayLinkCreate/Start/Stop/Release`, no `CVDisplayLinkRef`, no
  `m_cvDisplayLink` member, and `#include <QuartzCore/CVDisplayLink.h>` is gone
  from the header. Start/stop/isValid/ctor/dtor no longer branch on it.
* `${FWCoreVideo}` is correctly retained in
  `src/plugins/multimedia/darwin/CMakeLists.txt:29`. CoreVideo is used
  pervasively across the plugin for pixel-buffer handling —
  `CVImageBufferRef`/`CVPixelBufferRef`, `CVMetalTextureCache`,
  `CVPixelBufferGet*`, `kCVPixelBuffer*` keys — in avfvideobuffer, avfvideosink,
  avfvideorenderercontrol, avfcamerarenderer, avfmetadata, etc. Dropping the
  framework would break the build. The author was right not to remove it.

### 3. Build (CONFIRMED)

* `cmake --build /Users/anthony.liot/Desktop/bitbucket/qtmm-build --target
  QDarwinMediaPlugin` completes: `[100%] Built target QDarwinMediaPlugin`.
* To be sure the changed TU compiles clean at the new HEAD, I re-ran the exact
  compile command from `compile_commands.json` for `avfdisplaylink.mm` to a
  scratch object: it produced a fresh `.o` with **zero** diagnostic output (no
  errors, no new warnings) using the project's own flags.

### 4. Object lifetime / behavior (NO REGRESSION)

* The `DisplayLinkObserver` path is now the sole macOS path, but it is
  byte-for-byte the same path that already ran on macOS 15+ before this commit
  (verified against base `635067497`: the macOS-15 branch already did
  `[[DisplayLinkObserver alloc] initWithAVFDisplayLink:this]` +
  `[NSScreen.mainScreen displayLinkWithTarget:...]`). Lifetime is sound:
  `setDisplayLink:` retains/invalidates/releases the CADisplayLink; `dealloc`
  calls `setDisplayLink:nil`; `~AVFDisplayLink` calls `stop()` then releases the
  observer. Non-ARC memory management is correct.
* `isValid()` simplified from `m_observer || m_cvDisplayLink` to `m_observer`.
  Consistent with the observer being the only path.
* Run-loop mode: `NSDefaultRunLoopMode` (avfdisplaylink.mm:63/68). Verified this
  is **pre-existing** — the `DisplayLinkObserver start/stop` methods were not
  touched by this commit and already used `NSDefaultRunLoopMode` in the base.
  It differs from the qtbase Cocoa plugin (which uses common modes), but that is
  an existing qtmultimedia property, out of scope for this commit, and not a
  regression introduced here. Worth being aware of: a media player's display
  link registered only in `NSDefaultRunLoopMode` will pause while the run loop
  is in a modal/tracking mode (e.g. live window resize), but that is unchanged
  behavior.

### 5. Commit message and Qt style (GOOD)

Imperative subject with `darwin:` area prefix; body explains *why* (API since
14.0, floor 14.4, fallback unreachable) before *how*, and explicitly records
that CoreVideo stays linked for pixel buffers — which preempts the obvious
"why not drop the framework too" question. Change-Id present, no WIP content,
license header intact.

## Findings

### R4-1 — minor — Headless macOS 14.x: mainScreen-nil no longer has a working fallback

`avfdisplaylink.mm:96-99`. `NSScreen.mainScreen` can be `nil` (headless / no
attached display / some remote-session contexts). The `_Nonnull` annotation on
the return is not enforced; messaging `nil` yields a `nil` CADisplayLink, so
`m_displayLink` stays `nil` and no ticks are ever delivered — while `isValid()`
still returns `true` (it only checks `m_observer`). Previously, on macOS 14.x
the CVDisplayLink fallback used `CVDisplayLinkCreateWithCGDisplay(
kCGDirectMainDisplay, ...)`, which does not depend on an `NSScreen` and works
headless. So this is a narrow behavioral change on 14.x.

Why it is only minor / acceptable: the exact same `mainScreen`-nil edge already
existed on macOS 15+ before this commit (identical code), so the change merely
makes 14.x consistent with 15+ rather than introducing a new failure mode to the
codebase; video playback inherently targets a display; and the whole point of
the request is to stop using the deprecated API. Not blocking. If the author
wants to harden it, fall back to `NSScreen.screens.firstObject` or guard
`isValid()` on `m_displayLink != nil`, but I would accept the commit as-is.

## Verdict

**APPROVE**

Severity counts: blocker 0, major 0, minor 1, nit 0.

* R4-1 — minor — Headless macOS 14.x: `NSScreen.mainScreen` nil has no working
  fallback (pre-existing on 15+, acceptable).

R1-10 is resolved: the deprecated CVDisplayLink is gone from AVFDisplayLink, the
replacement API is genuinely available at the deployment floor, CoreVideo is
correctly retained, and the plugin builds and the changed file compiles without
new warnings.
