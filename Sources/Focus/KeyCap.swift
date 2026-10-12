//
//  KeyCap.swift
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
import Carbon.HIToolbox

/// Bindings are physical key codes.
/// Labels are layout-aware.
/// A stored key code must never be displayed as the wrong character, so every label is
/// translated through the active keyboard layout.
enum KeyCap {

    static func label(for binding: KeyBinding) -> String {
        self.modifierSymbols(binding.modifiers) + self.keyLabel(forKeyCode: binding.keyCode)
    }

    /// Spelled-out form for VoiceOver
    static func spokenLabel(for binding: KeyBinding) -> String {
        var parts: [String] = []

        if binding.modifiers & controlKey != 0 {
            parts.append(String(localized: "modifier.control"))
        }

        if binding.modifiers & optionKey != 0 {
            parts.append(String(localized: "modifier.option"))
        }

        if binding.modifiers & shiftKey != 0 {
            parts.append(String(localized: "modifier.shift"))
        }

        if binding.modifiers & cmdKey != 0 {
            parts.append(String(localized: "modifier.command"))
        }

        parts.append(self.spokenKeyLabels[binding.keyCode].map(self.localized) ?? self.keyLabel(forKeyCode: binding.keyCode))

        return parts.joined(separator: " ")
    }

    static func modifierSymbols(_ carbonModifiers: Int) -> String {
        var symbols = ""
        if carbonModifiers & controlKey != 0 {
            symbols += "⌃"
        }

        if carbonModifiers & optionKey != 0 {
            symbols += "⌥"
        }

        if carbonModifiers & shiftKey != 0 {
            symbols += "⇧"
        }

        if carbonModifiers & cmdKey != 0 {
            symbols += "⌘"
        }

        return symbols
    }

    /// An event's modifier flags as the Carbon mask bindings store.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.command) {
            carbon |= cmdKey
        }

        if flags.contains(.option) {
            carbon |= optionKey
        }

        if flags.contains(.control) {
            carbon |= controlKey
        }

        if flags.contains(.shift) {
            carbon |= shiftKey
        }

        return carbon
    }

    static func keyLabel(forKeyCode keyCode: Int) -> String {
        // Space is the only displayed label that is a word rather than a glyph
        if keyCode == kVK_Space {
            return String(localized: "key.space")
        }

        // Glyphs are the same in every language
        if let glyph = specialKeyGlyphs[keyCode] {
            return glyph
        }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(source,
                                                                kTISPropertyUnicodeKeyLayoutData) else {
            return String(format: String(localized: "key.unknown"),
                          keyCode)
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }

            return UCKeyTranslate(layout,
                                  UInt16(keyCode),
                                  UInt16(kUCKeyActionDisplay),
                                  0, // no modifiers: the base character of the physical key
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState,
                                  characters.count,
                                  &length,
                                  &characters)
        }

        guard status == noErr,
              length > 0 else {
            return String(format: String(localized: "key.unknown"), keyCode)
        }

        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    /// The keys whose glyph doesn't speak well, mapping their carbon keycode to the spoken text.
    private static let spokenKeyLabels: [Int: String] = [
        kVK_LeftArrow: "key.left-arrow",
        kVK_RightArrow: "key.right-arrow",
        kVK_DownArrow: "key.down-arrow",
        kVK_UpArrow: "key.up-arrow",
        kVK_Return: "key.return",
        kVK_Tab: "key.tab",
        kVK_Escape: "key.escape",
        kVK_Delete: "key.delete",
        kVK_ForwardDelete: "key.forward-delete",
        kVK_Home: "key.home",
        kVK_End: "key.end",
        kVK_PageUp: "key.page-up",
        kVK_PageDown: "key.page-down"
    ]

    /// `spokenKeyLabels` holds catalog keys, so an entry is looked up rather
    /// than hardcoded.
    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    /// Displayed labels that are glyphs, not words.
    /// Identical in every language and never localized.
    private static let specialKeyGlyphs: [Int: String] = [
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_DownArrow: "↓",
        kVK_UpArrow: "↑",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12"
    ]
}
