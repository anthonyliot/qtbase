#!/usr/bin/env python3
"""qtlog.py <label>...: the probe's display link log (qt.qpa.screen.updates, wall-clock times),
inside the recording (the trace's start-date and duration in <label>.toc.xml; the whole log if
there's none):
  * the render cadence: display link callbacks 41.7 ms apart (each delivers one frame);
  * the wait from an update request (the link is resumed for it) to its delivery (the link is
    paused once nothing is pending): the grid of the preferred rate, plus the render;
  * stall messages (the watchdog, the timer fallback).
A run whose window delivered no update in the recording is marked NOT SHOWN."""
import datetime
import os
import re
import statistics
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xtable import trace_window  # noqa: E402

for label in sys.argv[1:]:
    window = trace_window(label)
    callbacks, waits, resumed, stalls = [], [], None, 0
    for line in open(f'{label}.qtlog.txt', errors='replace'):
        m = re.match(r'(\S+) qt\.qpa\.screen\.updates:? (.*)', line)
        if not m:
            continue
        t = datetime.datetime.fromisoformat(m.group(1)).timestamp()
        if window and not (window[0] <= t <= window[1]):
            continue
        msg = m.group(2)
        if msg.startswith('Display link callback'):
            callbacks.append(t)
        elif msg.startswith('Resuming'):
            resumed = t
        elif msg.startswith('No pending') and resumed is not None:
            waits.append((t - resumed) * 1000)
            resumed = None
        if re.search(r"doesn't deliver|Falling back|Recreat", msg):
            stalls += 1
    where = 'the recording' if window else 'the whole log (no toc)'
    if not waits:
        print(f'{label}: NOT SHOWN, no update delivered in {where}')
        continue
    steps = Counter(round((b - a) * 120) for a, b in zip(callbacks, callbacks[1:]))
    total = sum(steps.values())
    w = sorted(waits)
    print(f'{label} ({where}): {len(callbacks)} callbacks, at 41.7 ms {100 * steps[5] / total:.1f}% '
          f'(33.3/50/83.3 ms: {steps[4]}/{steps[6]}/{steps[10]}); {len(waits)} requests, request to '
          f'delivery median {statistics.median(w):.1f} ms, p10 {w[int(0.1 * len(w))]:.1f}, '
          f'p90 {w[int(0.9 * len(w))]:.1f}, max {w[-1]:.1f}; stall messages: {stalls}')
