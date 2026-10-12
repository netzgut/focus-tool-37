//
//  WindowEnumerator.swift
//  FocusTool37
//
//  Copyright © 2026 Netzgut GmbH.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import CoreGraphics

/// One entry of the CGWindowList snapshot.
/// Array order is z-order, frontmost first: the implicit z-index.
struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

/// One CGWindowList snapshot per keypress.
/// Visible windows on the current Space, all displays, global top-left points, no Screen Recording
/// permission needed (we never read titles).
@MainActor
enum WindowEnumerator {

    private static let minSize: CGFloat = 40.0

    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let prefs = Preferences.shared
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var bundleIDCache: [pid_t: String?] = [:]

        var result: [WindowInfo] = []
        for info in list {
            // Normal windows only (drops Dock, menu bar, shadows, panels, PiP)
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  frame.width >= minSize,
                  frame.height >= minSize,
                  let pidValue = info[kCGWindowOwnerPID as String] as? Int else {
                continue
            }

            let pid = pid_t(pidValue)
            guard pid != ownPID, let idValue = info[kCGWindowNumber as String] as? Int else {
                continue
            }

            let bundleID: String?
            if let cached = bundleIDCache[pid] {
                bundleID = cached
            } else {
                bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                bundleIDCache[pid] = bundleID
            }
            guard !prefs.isIgnored(bundleID: bundleID) else {
                continue
            }

            result.append(WindowInfo(windowID: CGWindowID(idValue),
                                     pid: pid,
                                     frame: frame))
        }

        return result
    }
}
