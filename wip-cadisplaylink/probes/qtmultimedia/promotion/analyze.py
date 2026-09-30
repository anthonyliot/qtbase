#!/usr/bin/env python3
"""analyze.py <label>...: one line per run of the ProMotion A/B (measure.sh output, in the current
directory): the panel's refresh rate, the probe's frames on screen, the Qt display link during
the recording, and the display modes the probe read.

Only the recording's window counts: the Qt log (qt.qpa.screen.updates, wall-clock times) is cut
to the trace's start-date and duration (<label>.toc.xml). A run whose video window delivered no
update in that window is marked NOT SHOWN: an idle panel sits at its slowest rate, which on a
120 Hz ProMotion panel is 24 Hz, so it can't be told from one following 24 fps video.

Columns:
  24Hz, 120Hz   time the panel spent at 41.7 and 8.3 ms refresh intervals (gaps over 100 ms apart)
  shown         the probe's frames on screen (surfaces labelled 'viewprobe (pid):Frame N')
  disp          their intervals at 41.7 ms: over consecutive frame numbers / counting gaps as uneven
  render        the Qt log's display link callbacks 41.7 ms apart (each delivers one frame)
  wait          update request (the link is resumed for it) to delivery, median/p90, in ms
  c2d           commit to display of the probe's frames, median, in ms
  commits/s     the probe's Core Animation commits per second (with the Core Animation Commits
                instrument: the light recording)
  others        surfaces of other processes, and unattributed ones (window server framebuffers)
  modes         the display modes the probe read (its per-second lines), if not all 120 Hz
"""
import datetime
import os
import re
import statistics
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xtable import rows, fmt_ms, trace_window  # noqa: E402

REFRESH = 1000 / 120


def table(label, schema):
    path = f'{label}.{schema}.xml'
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return []
    return rows(path)[1]


def qtlog(label, window):
    """The display link events inside the window: callbacks, and request-to-delivery waits"""
    callbacks, waits, resumed, stall_messages = [], [], None, 0
    if not os.path.exists(f'{label}.qtlog.txt'):  # the Animation Hitches runs didn't log
        return None, [], 0
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
            stall_messages += 1
    return callbacks, waits, stall_messages


def analyze(label):
    o = {}
    window = trace_window(label)
    o['window'] = window is not None
    # The panel
    ts = sorted(int(r['timestamp'][0]) for r in table(label, 'display-vsyncs-interval'))
    iv = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
    at = defaultdict(float)
    for x in iv:
        if x <= 100:
            at[max(1, round(x / REFRESH))] += x
    counted = sum(at.values())
    o['24Hz'] = 100 * at.get(5, 0) / counted if counted else 0
    o['120Hz'] = 100 * at.get(1, 0) / counted if counted else 0
    # The probe's frames on screen, and the other surfaces
    frames, latencies, others = [], [], Counter()
    for r in table(label, 'displayed-surfaces-interval'):
        lab = (r.get('event-label') or (None, ''))[1] or ''
        m = re.search(r'\(([^:()]+) \((\d+)\):Frame (\d+)', lab)
        if m and m.group(1) == 'viewprobe':
            frames.append((int(m.group(3)), int(r['start'][0]) / 1e6))
            lat = fmt_ms(r.get('cpu-to-display-latency'))
            if lat is not None:
                latencies.append(lat)
        elif m:
            others[m.group(1)] += 1
        else:
            others['unattributed'] += 1
    frames.sort()
    steps, gaps = Counter(), 0
    for (n1, t1), (n2, t2) in zip(frames, frames[1:]):
        if n2 == n1 + 1:
            steps[round((t2 - t1) / REFRESH)] += 1
        else:
            gaps += 1
    total = sum(steps.values())
    o['shown'] = len(frames)
    o['disp'] = (f'{100 * steps.get(5, 0) / total:.1f}/{100 * steps.get(5, 0) / (total + gaps):.1f}'
                 if total else '-')
    o['c2d'] = statistics.median(latencies) if latencies else None
    o['others'] = dict(others)
    commits = sorted(int(r['start'][0]) / 1e9 for r in table(label, 'coreanimation-commit-interval')
                     if 'viewprobe' in ((r.get('thread') or (None, ''))[1] or ''))
    span = commits[-1] - commits[0] if len(commits) > 1 else 0
    o['commits'] = f'{(len(commits) - 1) / span:.1f}' if span else '-'
    # The Qt display link during the recording
    callbacks, waits, stall_messages = qtlog(label, window)
    o['qtlog'] = callbacks is not None
    callbacks = callbacks or []
    render = Counter(round((b - a) * 120) for a, b in zip(callbacks, callbacks[1:]))
    rtotal = sum(render.values())
    o['render'] = f'{100 * render.get(5, 0) / rtotal:.1f}' if rtotal else '-'
    o['deliveries'] = len(waits)
    w = sorted(waits)
    o['wait'] = f'{statistics.median(w):.1f}/{w[int(0.9 * len(w))]:.1f}' if w else '-'
    o['stall_messages'] = stall_messages
    # The display modes the probe read, and whether the window was shown
    probe = open(f'{label}.probe.txt', errors='replace').read()
    modes = Counter(re.findall(r'\((\d+\.\d+) Hz\)', probe))
    other_modes = not set(modes) <= {'120.000'}
    o['modes'] = ' '.join(f'{k}x{v}' for k, v in sorted(modes.items())) if other_modes else ''
    o['failed'] = 'FAILED' in probe
    return o


if __name__ == '__main__':
    print(f'{"run":22} {"24Hz":>6} {"120Hz":>6} {"shown":>5} {"disp":>11} {"render":>6} '
          f'{"wait":>10} {"c2d":>5} {"commits/s":>9}  notes')
    for label in sys.argv[1:]:
        try:
            o = analyze(label)
        except Exception as e:  # noqa: BLE001 - report the run, go on with the others
            print(f'{label:22} error: {e}')
            continue
        notes = []
        if not o['window']:
            notes.append('no toc: the whole Qt log')
        if not o['qtlog']:
            notes.append('no Qt log')
        elif o['deliveries'] == 0:
            notes.append('NOT SHOWN (no update delivered while recording)')
        if o['others']:
            notes.append(f'others {o["others"]}')
        if o['modes']:
            notes.append(f'modes {o["modes"]}')
        if o['stall_messages']:
            notes.append(f'stall messages {o["stall_messages"]}')
        if o['failed']:
            notes.append('FAILED')
        c2d = f'{o["c2d"]:.1f}' if o['c2d'] is not None else '-'
        print(f'{label:22} {o["24Hz"]:5.1f}% {o["120Hz"]:5.1f}% {o["shown"]:5d} {o["disp"]:>11} '
              f'{o["render"]:>6} {o["wait"]:>10} {c2d:>5} {o["commits"]:>9}  '
              f'{"; ".join(notes)}')
