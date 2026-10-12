//
//  AXHelpers.swift
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

import ApplicationServices

@MainActor
enum AX {

    /// Brings the window forward visually without giving its app key focus
    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func focusedWindow(ofPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        // A wedged app must not hang the caller
        AXUIElementSetMessagingTimeout(app, 0.2)
        return elementAttribute(app, kAXFocusedWindowAttribute)
    }

    /// Window title, for VoiceOver announcements.
    /// `kAXTitle` needs no Screen Recording permission, unlike `CGWindowList`'s `kCGWindowName`.
    static func title(of window: AXUIElement) -> String? {
        guard let title = copyAttribute(window, kAXTitleAttribute) as? String,
              !title.isEmpty else {
            return nil
        }

        return title
    }

    /// Window frame in global top-left coordinates
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue = copyAttribute(window, kAXPositionAttribute),
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = copyAttribute(window, kAXSizeAttribute),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((posValue as! AXValue), .cgPoint, &origin),
              AXValueGetValue((sizeValue as! AXValue), .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    static func subrole(of window: AXUIElement) -> String? {
        copyAttribute(window, kAXSubroleAttribute) as? String
    }

    /// "AXFullScreen" has no constant in the headers, but AppKit windows
    /// have answered to it since full screen arrived.
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        (copyAttribute(window, "AXFullScreen") as? Bool) ?? false
    }

    /// Height of the window's toolbar, nil when it has none. The height tells
    /// a regular toolbar from a compact one.
    static func toolbarHeight(of window: AXUIElement) -> CGFloat? {
        guard let children = copyAttribute(window, kAXChildrenAttribute) as? [AnyObject] else {
            return nil
        }

        for item in children where CFGetTypeID(item) == AXUIElementGetTypeID() {
            let child = item as! AXUIElement
            if copyAttribute(child, kAXRoleAttribute) as? String == kAXToolbarRole {
                return self.frame(of: child)?.height
            }
        }

        return nil
    }

    /// Brings the app forward through Accessibility.
    /// Unlike `NSRunningApplication.activate()`, this isn't subject to macOS 14's
    /// cooperative activation, so it works while another app is active and
    /// won't yield.
    /// Used only as a fallback, because it may bring more of the app's windows forward
    /// than a regular activation does.
    static func makeFrontmost(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// kAXRaiseAction alone doesn't reliably move key status in every app.
    /// Set main too, so same-app moves really shift keyboard focus.
    static func makeMain(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// ±2 pt per edge, absorbing rounding issues between CG and AX.
    static func framesMatch(_ a: CGRect,
                            _ b: CGRect,
                            tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// Resolves a CGWindowList target to an AXUIElement by pid + frame.
    /// AX is touched exactly once per keypress, for the single chosen window.
    static func window(pid: pid_t, matching frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)

        guard let value = copyAttribute(app, kAXWindowsAttribute),
              let array = value as? [AnyObject] else {
            return nil
        }

        for item in array {
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else {
                continue
            }

            let window = item as! AXUIElement
            // Perfectly stacked duplicates: first match = frontmost.
            if let windowFrame = self.frame(of: window),
               framesMatch(windowFrame, frame) {
                return window
            }
        }

        return nil
    }

    // MARK: - Attribute plumbing

    private static func copyAttribute(_ element: AXUIElement,
                                      _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }

        return value
    }

    private static func elementAttribute(_ element: AXUIElement,
                                         _ name: String) -> AXUIElement? {
        guard let value = copyAttribute(element, name),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }
}
