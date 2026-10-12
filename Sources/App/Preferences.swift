//
//  Preferences.swift
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
import Foundation

extension Notification.Name {
    static let preferencesChanged = Notification.Name("net.netzgut.focustool37.preferencesChanged")
}

@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let focusEnabled = "focusEnabled"
        static let warpAcrossDisplaysOnly = "warpAcrossDisplaysOnly"
        static let navVimKeys = "navVimKeys"
        static let navArrowKeys = "navArrowKeys"
        static let navSameApp = "navSameApp"
        static let navEdgeSlopPx = "navEdgeSlopPx"
        static let navConeAngleDeg = "navConeAngleDeg"
        static let showFocusHighlight = "showFocusHighlight"
        static let showCursorPulse = "showCursorPulse"
        static let highlightColor = "highlightColor"
        static let highlightCornerRadius = "highlightCornerRadius"
        static let highlightCornerRadiusAutomatic = "highlightCornerRadiusAutomatic"
        static let highlightBorderWidth = "highlightBorderWidth"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let navCustomBindings = "navCustomBindings"
    }

    static let customSlots = [
        "left",
        "down",
        "up",
        "right"
    ]

    private let defaults = UserDefaults.standard

    private init() {
        self.defaults.register(defaults: [
            Key.focusEnabled: true,
            Key.warpAcrossDisplaysOnly: false,
            Key.navVimKeys: true,
            Key.navArrowKeys: true,
            Key.navSameApp: false,
            Key.navEdgeSlopPx: 8.0,
            Key.navConeAngleDeg: 45.0,
            Key.showFocusHighlight: true,
            Key.showCursorPulse: true,
            Key.highlightCornerRadius: 10.0,
            Key.highlightCornerRadiusAutomatic: true,
            Key.highlightBorderWidth: 5.0,
            Key.ignoredBundleIDs: [String]()
        ])
    }

    /// One-shot guard to enable/disable.
    var focusEnabled: Bool {
        get {
            self.defaults.bool(forKey: Key.focusEnabled)
        }
        set {
            self.defaults.set(newValue, forKey: Key.focusEnabled)
            self.notify()
        }
    }

    /// Only warp when the target is on a different display than the cursor,
    /// so the pointer teleports only when it would otherwise be stranded.
    var warpAcrossDisplaysOnly: Bool {
        get {
            self.defaults.bool(forKey: Key.warpAcrossDisplaysOnly)
        }
        set {
            self.defaults.set(newValue, forKey: Key.warpAcrossDisplaysOnly)
            self.notify()
        }
    }

    /// Enable ⌥⌘+HJKL for focus changes.
    var navVimKeys: Bool {
        get {
            self.defaults.bool(forKey: Key.navVimKeys)
        }
        set {
            self.defaults.set(newValue, forKey: Key.navVimKeys)
            self.notify()
        }
    }

    /// Enable ⌥⌘+arrow keys for focus changes.
    var navArrowKeys: Bool {
        get {
            self.defaults.bool(forKey: Key.navArrowKeys)
        }
        set {
            self.defaults.set(newValue, forKey: Key.navArrowKeys)
            self.notify()
        }
    }

    /// ⇧ same-app variants of the directional presets.
    var navSameApp: Bool {
        get {
            self.defaults.bool(forKey: Key.navSameApp)
        }
        set {
            self.defaults.set(newValue, forKey: Key.navSameApp)
            self.notify()
        }
    }

    var navEdgeSlopPx: Double {
        get {
            self.defaults.double(forKey: Key.navEdgeSlopPx)
        }
        set {
            self.defaults.set(newValue, forKey: Key.navEdgeSlopPx)
            self.notify()
        }
    }

    var navConeAngleDeg: Double {
        get {
            self.defaults.double(forKey: Key.navConeAngleDeg)
        }
        set {
            self.defaults.set(newValue, forKey: Key.navConeAngleDeg)
            self.notify()
        }
    }

    var showFocusHighlight: Bool {
        get {
            self.defaults.bool(forKey: Key.showFocusHighlight)
        }
        set {
            self.defaults.set(newValue, forKey: Key.showFocusHighlight)
            self.notify()
        }
    }

    /// Whether the outline follows the corners of standard macOS windows,
    /// keeping `highlightCornerRadius` for windows it can't classify.
    var highlightCornerRadiusAutomatic: Bool {
        get {
            self.defaults.bool(forKey: Key.highlightCornerRadiusAutomatic)
        }
        set {
            self.defaults.set(newValue, forKey: Key.highlightCornerRadiusAutomatic)
            self.notify()
        }
    }

    /// Window corner radii differ from app to app. If not detected properly or disabled, this is the fallback.
    var highlightCornerRadius: Double {
        get {
            self.defaults.double(forKey: Key.highlightCornerRadius)
        }
        set {
            self.defaults.set(newValue, forKey: Key.highlightCornerRadius)
            self.notify()
        }
    }

    /// Stroke width of the focus outline in points.
    var highlightBorderWidth: Double {
        get {
            self.defaults.double(forKey: Key.highlightBorderWidth)
        }
        set {
            self.defaults.set(newValue, forKey: Key.highlightBorderWidth)
            self.notify()
        }
    }

    var showCursorPulse: Bool {
        get {
            self.defaults.bool(forKey: Key.showCursorPulse)
        }
        set {
            self.defaults.set(newValue, forKey: Key.showCursorPulse)
            self.notify()
        }
    }

    /// Colour shared by both visual cues: the focus outline and the cursor ring.
    /// Absent means "follow the system accent".
    var highlightColor: NSColor? {
        get {
            guard let data = self.defaults.data(forKey: Key.highlightColor) else {
                return nil
            }

            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self,
                                                           from: data)
        }
        set {
            if let newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue,
                                                            requiringSecureCoding: true) {
                self.defaults.set(data, forKey: Key.highlightColor)
            } else {
                self.defaults.removeObject(forKey: Key.highlightColor)
            }

            self.notify()
        }
    }

    /// Bundle IDs of apps that should be ignored as focus targets.
    var ignoredBundleIDs: [String] {
        get {
            self.defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? []
        }
        set {
            self.defaults.set(newValue, forKey: Key.ignoredBundleIDs)
            self.notify()
        }
    }

    /// Slot key (left/down/up/right) -> binding.
    /// Additive with the presets, which keep their own toggles. A custom
    /// binding only displaces a preset combo it collides with outright.
    /// ⇧ same-app variants are preset-only.
    var navCustomBindings: [String: KeyBinding] {
        get {
            guard let raw = self.defaults.dictionary(forKey: Key.navCustomBindings) as? [String: [String: Int]] else {
                return [:]
            }

            return raw.compactMapValues { entry in
                guard let keyCode = entry["keyCode"],
                      let modifiers = entry["modifiers"] else {
                    return nil
                }

                return KeyBinding(keyCode: keyCode,
                                  modifiers: modifiers)
            }
        }
        set {
            let raw = newValue.mapValues { [
                "keyCode": $0.keyCode,
                "modifiers": $0.modifiers
            ] }
            self.defaults.set(raw, forKey: Key.navCustomBindings)
            self.notify()
        }
    }

    /// Always excluded app list that's tested first for eligility detection
    static let hardcodedExclusions: Set<String> = [
        "net.netzgut.focustool37",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.WindowManager",
        "com.apple.screencaptureui"
    ]

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }

        return Self.hardcodedExclusions.contains(bundleID) || self.ignoredBundleIDs.contains(bundleID)
    }

    private func notify() {
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
}
