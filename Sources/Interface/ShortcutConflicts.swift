//
//  ShortcutConflicts.swift
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

/// Display names for the things a shortcut can be bound to.
@MainActor
enum ShortcutNaming {

    static func preset(_ preset: HotKeyManager.Preset) -> String {
        switch preset {
        case .vim: String(localized: "settings.vim-keys")
        case .arrows: String(localized: "settings.arrow-keys")
        }
    }

    static func slot(_ slot: String) -> String {
        switch slot {
        case "left": String(localized: "shortcut.focus-left")
        case "down": String(localized: "shortcut.focus-down")
        case "up": String(localized: "shortcut.focus-up")
        case "right": String(localized: "shortcut.focus-right")
        default: slot
        }
    }
}

/// Who already owns a combo, checked before a custom binding is stored.
@MainActor
enum ShortcutConflicts {

    /// Returns a description of the current owner, or nil when the combo is free.
    static func description(for binding: KeyBinding,
                            slot: String) -> String? {

        for (otherSlot, other) in Preferences.shared.navCustomBindings where otherSlot != slot && other == binding {
            return String(format: String(localized: "conflict.owner.slot"),
                          ShortcutNaming.slot(otherSlot))
        }

        // Now that the presets register alongside the custom slots, a preset can
        // own the combo too. The custom binding would take it over, so say which
        // preset key stops working.
        for claim in HotKeyManager.activePresetClaims() where claim.binding == binding {
            return String(format: String(localized: "conflict.owner.preset"), ShortcutNaming.preset(claim.preset))
        }

        for (known, owner) in self.knownSystemChords where known == binding {
            // The table holds catalog keys, so the owner name is looked up
            return String(localized: String.LocalizationValue(owner))
        }

        return nil
    }

    private static let knownSystemChords: [(KeyBinding, String)] = [
        (KeyBinding(keyCode: kVK_Space, modifiers: cmdKey), "conflict.owner.spotlight"),
        (KeyBinding(keyCode: kVK_Space, modifiers: optionKey | cmdKey), "conflict.owner.finder-search"),
        (KeyBinding(keyCode: kVK_Space, modifiers: controlKey), "conflict.owner.input-source"),
        (KeyBinding(keyCode: kVK_Tab, modifiers: cmdKey), "conflict.owner.app-switcher"),
        (KeyBinding(keyCode: kVK_ANSI_3, modifiers: shiftKey | cmdKey), "conflict.owner.screenshots"),
        (KeyBinding(keyCode: kVK_ANSI_4, modifiers: shiftKey | cmdKey), "conflict.owner.screenshots"),
        (KeyBinding(keyCode: kVK_ANSI_5, modifiers: shiftKey | cmdKey), "conflict.owner.screenshots"),
        (KeyBinding(keyCode: kVK_UpArrow, modifiers: controlKey), "conflict.owner.mission-control"),
        (KeyBinding(keyCode: kVK_DownArrow, modifiers: controlKey), "conflict.owner.app-expose"),
        (KeyBinding(keyCode: kVK_LeftArrow, modifiers: controlKey), "conflict.owner.space-switching"),
        (KeyBinding(keyCode: kVK_RightArrow, modifiers: controlKey), "conflict.owner.space-switching")
    ]
}
