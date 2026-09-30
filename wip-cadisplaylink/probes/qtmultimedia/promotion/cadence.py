#!/usr/bin/env python3
"""cadence.py <label>...: the intervals between consecutive frames of the probe on screen (its
surfaces are labelled 'viewprobe (pid):Frame N' in displayed-surfaces-interval), in display
refreshes of 8.33 ms. For 24 fps on a 120 Hz panel, an even cadence is every interval at
41.67 ms (5 refreshes); judder is 33.33/50 ms pairs (4 and 6). Intervals across a gap in the
frame numbers (a frame the trace didn't show) are left out of the first percentage and counted as
uneven in the second."""
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xtable import rows  # noqa: E402

REFRESH = 1000 / 120
for label in sys.argv[1:]:
    _, ds = rows(f'{label}.displayed-surfaces-interval.xml')
    frames = []
    for r in ds:
        m = re.search(r'viewprobe \(\d+\):Frame (\d+)', (r.get('event-label') or (None, ''))[1] or '')
        if m:
            frames.append((int(m.group(1)), int(r['start'][0]) / 1e6))
    frames.sort()
    steps = Counter()
    gaps = 0
    for (n1, t1), (n2, t2) in zip(frames, frames[1:]):
        if n2 != n1 + 1:
            gaps += 1
            continue
        steps[round((t2 - t1) / REFRESH)] += 1
    total = sum(steps.values())
    even = steps.get(5, 0)
    print(f'{label}: {len(frames)} probe frames, {total} consecutive intervals, {gaps} gaps in the '
          f'frame numbers; at 41.67 ms: {100 * even / total if total else 0:.1f}% '
          f'({100 * even / (total + gaps) if total + gaps else 0:.1f}% with the gaps as uneven); '
          + ', '.join(f'{k * REFRESH:.1f} ms x{v}' for k, v in sorted(steps.items())))
