#!/usr/bin/env python3
"""Reads tables exported by `xctrace export --xpath ...` (values are defined once with id= and
then referenced with ref=) and prints what the ProMotion checklist needs.

  xtable.py vsync <display-vsyncs-interval.xml>            the panel's refresh intervals
  xtable.py cpu <ProcessCPUUsage.xml>                      CPU time by process
  xtable.py frames <hitches-frame-lifetimes.xml> <process> commit to display, per frame
  xtable.py columns <table.xml>                            the columns and the first rows
"""
import sys
import statistics
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict


def rows(path):
    root = ET.parse(path).getroot()
    node = root.find('node')
    schema = node.find('schema')
    names = [c.findtext('mnemonic') for c in schema.findall('col')]
    ids = {}

    def value(e):
        if 'ref' in e.attrib:
            return ids[e.attrib['ref']]
        v = (e.text, e.attrib.get('fmt'), e)
        if 'id' in e.attrib:
            ids[e.attrib['id']] = v
        # define nested values too, later rows may refer to them
        for child in e:
            value(child)
        return v

    out = []
    for r in node.findall('row'):
        vals = [value(e) for e in r]
        out.append(dict(zip(names, vals)))
    return names, out


def num(v):
    return int(v[0]) if v and v[0] is not None else None


def trace_window(label):
    """The recording's wall-clock window (epoch seconds) from <label>.toc.xml, or None"""
    import datetime
    import os
    import re
    path = f'{label}.toc.xml'
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    toc = open(path, errors='replace').read()
    start = re.search(r'<start-date>([^<]+)</start-date>', toc)
    duration = re.search(r'<duration>([^<]+)</duration>', toc)
    if not start or not duration:
        return None
    t0 = datetime.datetime.fromisoformat(start.group(1)).timestamp()
    return t0, t0 + float(duration.group(1))


def vsync(path):
    _, rs = rows(path)
    ts = sorted(num(r['timestamp']) for r in rs if r.get('timestamp'))
    iv = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
    if not iv:
        print('no vsyncs'); return
    buckets = Counter(round(x / (1000 / 120)) for x in iv)  # in 120 Hz frames
    span = (ts[-1] - ts[0]) / 1e9
    print(f'{len(ts)} vsyncs over {span:.2f} s = {(len(ts) - 1) / span:.2f} Hz on average; '
          f'interval median {statistics.median(iv):.3f} ms, min {min(iv):.3f}, max {max(iv):.3f}')
    for k in sorted(buckets):
        print(f'  {k} x 8.33 ms ({1000 / (k * 1000 / 120) if k else 0:.0f} Hz): '
              f'{buckets[k]} intervals ({100 * buckets[k] / len(iv):.1f}%)')


def cpu(path):
    names, rs = rows(path)
    total = defaultdict(int)
    for r in rs:
        proc = r.get('process')
        t = r.get('cpu-time') or r.get('duration')
        if proc and t and t[0]:
            total[proc[1] or proc[0]] += int(t[0])
    for p, t in sorted(total.items(), key=lambda x: -x[1])[:15]:
        print(f'  {t / 1e9:8.2f} s  {p}')


def columns(path):
    names, rs = rows(path)
    print(names)
    for r in rs[:5]:
        print({k: (v[1] if v else None) for k, v in r.items()})


def frames(path, process):
    names, rs = rows(path)
    print('columns:', names)
    sel = [r for r in rs if any(process in (v[1] or '') for v in r.values() if v)]
    print(f'{len(sel)} of {len(rs)} rows mention {process}')
    for r in sel[:3]:
        print({k: (v[1] if v else None) for k, v in r.items()})


def fmt_ms(v):
    """'24.02 ms', '1.02 s', '850.00 µs' -> milliseconds"""
    if not v or not v[1] or v[1] == '-':
        return None
    s = v[1].replace(',', '')
    for unit, f in (('µs', 1e-3), ('ms', 1.0), ('ns', 1e-6), ('s', 1e3)):
        if s.endswith(unit):
            return float(s[:-len(unit)].strip()) * f
    return None


def summary(label):
    """The panel's refresh intervals (by time spent), and the probe's displayed frames"""
    import re
    _, vs = rows(f'{label}.display-vsyncs-interval.xml')
    ts = sorted(int(r['timestamp'][0]) for r in vs)
    iv = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
    span = sum(iv)
    by_rate = defaultdict(float)
    stalls = [x for x in iv if x > 100]
    for x in iv:
        if x <= 100:
            by_rate[max(1, round(x / (1000 / 120)))] += x
    print(f'{label}: {len(ts)} vsyncs over {span / 1000:.2f} s; time at each refresh interval '
          f'(stalls over 100 ms excluded: {len(stalls)}, {sum(stalls):.0f} ms):')
    t0 = ts[0] if ts else 0
    for a, b in zip(ts, ts[1:]):
        if (b - a) / 1e6 > 100:
            print(f'    stall: no vsync from {(a - t0) / 1e9:.3f} s to {(b - t0) / 1e9:.3f} s ({(b - a) / 1e6:.0f} ms)')
    for k in sorted(by_rate):
        print(f'    {k * 1000 / 120:6.2f} ms ({120 / k:5.1f} Hz): {100 * by_rate[k] / max(1e-9, span - sum(stalls)):5.1f}%')
    _, ds = rows(f'{label}.displayed-surfaces-interval.xml')
    probe, others = [], Counter()
    for r in ds:
        lab = (r.get('event-label') or (None, ''))[1] or ''
        m = re.search(r'\(([^:()]+) \(\d+\)', lab)
        who = m.group(1) if m else 'unattributed'
        if who == 'viewprobe':
            probe.append((fmt_ms(r.get('duration')), fmt_ms(r.get('cpu-to-display-latency'))))
        else:
            others[who] += 1
    lat = sorted(l for _, l in probe if l is not None)
    dur = Counter(round(d / (1000 / 120)) for d, _ in probe if d is not None and d <= 100)
    if lat:
        q = lambda p: lat[min(len(lat) - 1, int(p * len(lat)))]
        print(f'  probe frames displayed: {len(probe)}; commit to display: median {statistics.median(lat):.2f} ms, '
              f'p10 {q(0.1):.2f}, p90 {q(0.9):.2f}, max {lat[-1]:.2f}')
    print('  probe frames on screen for: ' + ', '.join(f'{k * 1000 / 120:.2f} ms x{dur[k]}' for k in sorted(dur)))
    print(f'  other surfaces displayed: {dict(others)}')


if __name__ == '__main__':
    cmd = sys.argv[1]
    {'vsync': lambda: vsync(sys.argv[2]), 'cpu': lambda: cpu(sys.argv[2]),
     'columns': lambda: columns(sys.argv[2]),
     'summary': lambda: [summary(l) for l in sys.argv[2:]],
     'frames': lambda: frames(sys.argv[2], sys.argv[3])}[cmd]()
