# Video frame rates on a 120 Hz ProMotion display (2026-09-26)

Measured with `bench/video-rates.sh` (tests/manual/displaylink, window kept on top), requesting a
rate with `QT_APPLE_PREFERRED_FRAME_RATE_RANGE=<rate>`, and the panel's actual refresh from the
display's vsyncs (xctrace Display instrument) at the same time. Built-in MacBook display,
variable 24-120 Hz.

| Requested | Qt delivered | Panel refresh | Notes |
|---|---|---|---|
| 23.976 | 24.00 | 24 Hz (100%) | film: exact cadence, panel follows |
| 24 | 24.00 | 24 Hz (85%) | |
| 25 | 24.00 | 24 Hz | PAL: not an exact rate on this panel |
| 29.97 | 30.00 | 30 Hz (87%) | NTSC |
| 30 | 30.00 | 30 Hz (97%) | |
| 40 | 40.00 | 40 Hz (100%) | |
| 48 | 60 | 60 Hz (97%) | not an exact rate on this panel |
| 50 | 60 | 60 Hz (96%) | PAL 50p: not exact |
| 59.94 | 60 | 60 Hz (99%) | |
| 60, 80, 120, default | 60, 120, 120, 120 | see below | |

The panel readings for 60 and above couldn't be taken cleanly: while measuring, another app kept
the panel at a constant 30 Hz, and then at 120 Hz, regardless of our window. Earlier the same day,
cool-retro-term at 60 fps measured a 60 Hz panel and the default a 120 Hz panel.

## Which rates are exact (240 Hz external display, 2026-09-28)

`probes/divisors.m` asks an NSScreen display link for 240 / n and counts the callbacks:

| n | requested | delivered |
|---|---|---|
| 1-6, 8, 10, 12, 15, 16, 20, 24 | 240, 120, 80, 60, 48, 40, 30, 24, 20, 16, 15, 12, 10 | same |
| 7 | 34.29 | 40 |
| 9 | 26.67 | 30 |
| 11 | 21.82 | 24 |
| 13, 14 | 18.46, 17.14 | 20 |

CoreAnimation only runs a display link at whole rates that divide the refresh rate, and rounds
other requests up to the next such rate. `QAppleFrameRateRange::forPreferredFrameRate()` now only
picks those (25 on 240 Hz asks for 30 instead of 26.67, which the system turned into 30 anyway),
so that its idea of "exact" (used to keep a video and a UI window exact together) matches the
system's. On the 120 Hz ProMotion panel only n = 1-5 were measured (all divide 120).

## What it means

* On a 120 Hz ProMotion panel CoreAnimation offers exactly 120 / n: 120, 60, 40, 30, 24 (and 20,
  ...). On a 240 Hz display 240 / n adds 80 and 48.
* Film (23.976/24), NTSC (29.97/30) and 59.94/60 content get an exact cadence, and the panel drops
  to match (24 Hz for film).
* 25/50 (PAL) and 48 can't be shown exactly on 120 Hz: those need the user to pick a fixed refresh
  mode in Display settings, which apps can't request through CADisplayLink.
* The panel's rate is shared: another app driving it to an incompatible rate (e.g. 60 Hz while
  playing 24p) makes CoreAnimation deliver the nearest rate it can (30), seen once while Instruments
  was recording.
* With the private property/env var, rates that aren't exact round to the nearest one (25 → 24,
  which skips a content frame per second). The public `QWindow::preferredFrameRate` rounds to the
  **next faster** exact rate instead (25 → 30, no skipped frames), and keeps several windows exact
  together (24 fps video + 60 fps UI → display link at 120, both exact).

## Guidance for video apps

* Set the window's `preferredFrameRate` to the content rate while playing (e.g. `24000.0 / 1001`),
  and back to 0 (or a UI rate like 60) when paused.
* Pick the video frame to show from the presentation time, not by counting update requests: the
  panel rate can change underneath (another app, Low Power Mode). Public timing API is still to do
  (API-PROPOSAL.md section 2); privately, `QWindowPrivate::updateRequestInterval` is the paced
  interval during delivery.
* Keep a single visible Qt Quick window for the video where possible: with several exposed windows
  Qt Quick drives animations from a timer, not the display link.

## Other findings from this run

* An intermittent stall (update requests stop although the window stays exposed) was seen again
  with `120` and `1,120` right after startup, then not in 45 further runs. The manual test's
  `--trace` option records the event sequence to catch it next time. Still not root-caused.
* xctrace itself occasionally hangs; `video-rates.sh` gives up on it after 30 s.
