//
//  Accessibility.swift
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
import ApplicationServices

extension Notification.Name {
    /// Posted once the Accessibility grant arrives, so the menu and prefs
    /// window can drop their "permission required" state.
    static let accessibilityStatusChanged = Notification.Name("net.netzgut.focustool37.accessibilityStatusChanged")
}

enum AccessibilityPermission {

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks trust and, if not yet granted, shows the system prompt that
    /// deep-links to the System Settings.
    static func promptIfNeeded() -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt (the C global itself)
        // is rejected under Swift 6 strict concurrency (shared mutable state).
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    @MainActor
    static func openSystemSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }
}
