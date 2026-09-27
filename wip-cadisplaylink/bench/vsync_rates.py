# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause

# Usage: vsync_rates.py <trace>  -- panel refresh rate histogram from the xctrace Display instrument
import subprocess, sys, collections, xml.etree.ElementTree as ET
xml = subprocess.run(['xcrun', 'xctrace', 'export', '--input', sys.argv[1], '--xpath',
                      '/trace-toc/run[@number="1"]/data/table[@schema="display-vsyncs-interval"]'],
                     capture_output=True, text=True).stdout
root = ET.fromstring(xml)
ids, times = {}, collections.defaultdict(list)
def val(el):
    if el is None: return None
    if 'ref' in el.attrib: return ids[el.attrib['ref']]
    v = el.text
    if 'id' in el.attrib: ids[el.attrib['id']] = v
    return v
for row in root.iter('row'):
    t = val(row.find('start-time')); name = val(row.find('display-name'))
    for child in row:  # register ids of other columns too
        if child.tag not in ('start-time', 'display-name'): val(child)
    if t is not None: times[name].append(int(t))
for name, ts in times.items():
    ts.sort(); d = [b - a for a, b in zip(ts, ts[1:]) if b > a]
    if not d: continue
    span = (ts[-1] - ts[0]) / 1e9
    hist = collections.Counter(min((24, 30, 40, 48, 60, 80, 120, 240), key=lambda r: abs(1e9 / x - r)) for x in d)
    share = {r: f"{100 * n / len(d):.0f}%" for r, n in sorted(hist.items(), reverse=True)}
    print(f"{name}: {len(ts)} vsyncs in {span:.1f} s = {len(ts) / span:.1f} Hz average; intervals by nearest rate: {share}")
