# M1 darwin: Don't leak the display link of AVFDisplayLink

| | |
|---|---|
| Repo, branch | qtmultimedia `wip/cadisplaylink` |
| Files | `src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm` |
| Tree | S1 `47653cfd479b` (`pr/qtmultimedia-series/trees.txt`) |
| Change-Id | `I38b6dae4b00580e8241dd075684e32d437b997a9` |
| From | review round 6 R6-3, and a leak found while baselining the round 6 fixes |

## What
* `~AVFDisplayLink` calls `[m_observer setDisplayLink:nil]` before releasing the observer, which
  invalidates the display link.
* `-[DisplayLinkObserver setDisplayLink:]` assigns the new link (retained) even when it's nil, so it
  doesn't keep pointing to the link it just released (R6-3).

## Why
A display link retains its target until it's invalidated. The target is the observer, and the
observer only invalidated its link in `dealloc`, which then never ran: the link kept the observer
alive, and the observer kept the link. Every `AVFMediaPlayer` creates an `AVFVideoRendererControl`
and so an `AVFDisplayLink`, so every media player leaked one observer and one display link. This
is upstream on iOS and on macOS 15 and later (the CADisplayLink path). On macOS 14.x upstream used
CVDisplayLink, which it released, so M3, which removes that fallback, would have extended the leak
to 14.x. That's why M1 comes first. It fixes a leak in released versions and stands alone, so it's
a candidate for a QTBUG and a `Pick-to:` footer (R7-8), which the author decides at Gerrit time.

The pointer fix is needed by the leak fix: without it, `setDisplayLink:nil` in the destructor would
leave `m_displayLink` pointing to the released link, and `dealloc` would message it again.

Probe (`probe.mm`, MRC like the plugin): after `[target release]` the target isn't deallocated
while the link exists; `[link invalidate]` deallocates it.

## Verified
See TESTING.md, qtmultimedia section: heap(1) counts of live `DisplayLinkObserver` and
`CADisplayLink` objects after 20 players, before and after the fix, and at every later state; the
S1 state built and tested. The reviewer ran the S5-era lifecycle under NSZombieEnabled (round 7):
no message to a freed object, every observer deallocated.
