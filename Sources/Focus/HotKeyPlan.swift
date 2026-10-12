//
//  HotKeyPlan.swift
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

import Carbon.HIToolbox

/// A physical key binding: Carbon virtual key code + Carbon modifier mask.
/// Position-based, never character-based, to survive layout changes.
struct KeyBinding: Hashable, Sendable {
    let keyCode: Int
    let modifiers: Int
}

/// What a registered combo does.
enum HotKeyAction: Equatable, Sendable {
    case focus(Direction)
    case focusSameApp(Direction)
}

/// Which combo gets which action, decided from prefs alone.
/// Pure, so the precedence rules are easier to unit-test.
/// `HotKeyManager` only performs the Carbon calls.
enum HotKeyPlan {

    /// The prefs a plan is built from.
    struct Inputs: Equatable {
        let vimKeys: Bool
        let arrowKeys: Bool
        let sameApp: Bool
        let custom: [String: KeyBinding]
    }

    struct Entry: Equatable {
        let binding: KeyBinding
        let action: HotKeyAction

        /// Set for custom slots, so a failed registration lands on its row.
        let customSlot: String?
    }

    static let optCmd = Int(optionKey | cmdKey)
    static let optCmdShift = Int(optionKey | cmdKey | shiftKey)

    static let vimKeys: [(keyCode: Int, direction: Direction)] = [
        (kVK_ANSI_H, .left),
        (kVK_ANSI_J, .down),
        (kVK_ANSI_K, .up),
        (kVK_ANSI_L, .right)
    ]

    static let arrowKeys: [(keyCode: Int, direction: Direction)] = [
        (kVK_LeftArrow, .left),
        (kVK_DownArrow, .down),
        (kVK_UpArrow, .up),
        (kVK_RightArrow, .right)
    ]

    /// Fixed order, so a duplicate custom combo always goes to the same slot.
    static let customSlots: [(slot: String, direction: Direction)] = [
        ("left", .left),
        ("down", .down),
        ("up", .up),
        ("right", .right)
    ]

    static func entries(for inputs: Inputs) -> [Entry] {
        var entries: [Entry] = []

        // Custom bindings are additive with the presets, so a combo can be
        // asked for twice.
        // Carbon refuses the second claim on one combo, which would surface
        // as a bogus "in use by another app" note.
        // Planning the custom slots first lets an explicit binding win the
        // overlap and the preset skip it. A combo saved in two custom slots
        // goes to the first.
        var claimed: Set<KeyBinding> = []

        for (slot, direction) in self.customSlots {
            guard let binding = inputs.custom[slot],
                  claimed.insert(binding).inserted else {
                continue
            }

            entries.append(Entry(binding: binding,
                                 action: .focus(direction),
                                 customSlot: slot))
        }

        let presets = [
            (inputs.vimKeys, self.vimKeys),
            (inputs.arrowKeys, self.arrowKeys)
        ]

        for (enabled, keys) in presets where enabled {
            for (keyCode, direction) in keys {
                let binding = KeyBinding(keyCode: keyCode,
                                         modifiers: self.optCmd)
                if claimed.insert(binding).inserted {
                    entries.append(Entry(binding: binding,
                                         action: .focus(direction),
                                         customSlot: nil))
                }

                // ⇧ same-app variants are their own gated registrations (off by default).
                guard inputs.sameApp else {
                    continue
                }

                let shifted = KeyBinding(keyCode: keyCode,
                                         modifiers: self.optCmdShift)
                if claimed.insert(shifted).inserted {
                    entries.append(Entry(binding: shifted,
                                         action: .focusSameApp(direction),
                                         customSlot: nil))
                }
            }
        }

        return entries
    }
}
