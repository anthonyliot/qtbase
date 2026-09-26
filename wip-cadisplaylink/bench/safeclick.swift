// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

// Usage: qt-safeclick <pid> <x-in-window> <y-in-window>  -- clicks only if no other window covers the point
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let pid = Int32(a[1])!, rx = Double(a[2])!, ry = Double(a[3])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
func bounds(_ w: [String: Any]) -> CGRect { let b = w[kCGWindowBounds as String] as! [String: Double]; return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!) }
guard let idx = list.firstIndex(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && bounds($0).height > 300 }) else { print("no window"); exit(1) }
let r = bounds(list[idx]); let p = CGPoint(x: r.minX + rx, y: r.minY + ry)
for w in list[..<idx] where bounds(w).contains(p) && ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01 {
    print("covered by \(w[kCGWindowOwnerName as String] ?? "?") - not clicking"); exit(2)
}
let original = CGEvent(source: nil)!.location
for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(80_000)
}
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: original, mouseButton: .left)!.post(tap: .cghidEventTap)
print("clicked \(p)")
