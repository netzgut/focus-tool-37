//
//  HotKeyManager.swift
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
import os

private let hotKeySignature: OSType = 0x4654_3337 // 'FT37'

extension Notification.Name {
    static let hotKeyRegistrationsUpdated = Notification.Name("net.netzgut.focustool37.hotKeyRegistrationsUpdated")
}

/// Hotkeys via Carbon RegisterEventHotKey: system-wide, consumes
/// the event so ⌥⌘L never reaches the focused app.
/// Presets and custom slots register side by side; every combo (⇧ variants
/// included) is its own explicit registration.
@MainActor
final class HotKeyManager {

    private static let log = Logger(subsystem: "net.netzgut.focustool37", category: "hotkeys")

    typealias Action = HotKeyAction

    enum Preset: CaseIterable {
        case vim
        case arrows

        var keys: [(keyCode: Int, direction: Direction)] {
            switch self {
            case .vim: HotKeyPlan.vimKeys
            case .arrows: HotKeyPlan.arrowKeys
            }
        }

        @MainActor
        var isEnabled: Bool {
            switch self {
            case .vim: Preferences.shared.navVimKeys
            case .arrows: Preferences.shared.navArrowKeys
            }
        }
    }

    /// Every combo the enabled presets currently claim, ⇧ variants included.
    static func activePresetClaims() -> [(binding: KeyBinding, preset: Preset)] {
        var claims: [(binding: KeyBinding, preset: Preset)] = []

        for preset in Preset.allCases where preset.isEnabled {
            for (keyCode, _) in preset.keys {
                claims.append((KeyBinding(keyCode: keyCode,
                                          modifiers: HotKeyPlan.optCmd),
                               preset))

                if Preferences.shared.navSameApp {
                    claims.append((KeyBinding(keyCode: keyCode,
                                              modifiers: HotKeyPlan.optCmdShift),
                                   preset))
                }
            }
        }

        return claims
    }

    var handler: ((Action) -> Void)?

    /// Custom slots whose RegisterEventHotKey failed (e.g., combo owned by another
    /// running app).
    private(set) var failedCustomSlots: Set<String> = []

    /// Failed preset registrations, shown as a summary note.
    private(set) var failedPresetCount = 0

    private var hotKeys: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: Action] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// The prefs the current registrations were built from.
    /// Every preference change triggers a rebuild, most have nothing to do with hotkeys.
    private var registeredInputs: HotKeyPlan.Inputs?

    /// Tears down and re-registers from current prefs, unless the hotkey-relevant prefs are unchanged.
    func rebuild() {
        let prefs = Preferences.shared
        let inputs = HotKeyPlan.Inputs(vimKeys: prefs.navVimKeys,
                                       arrowKeys: prefs.navArrowKeys,
                                       sameApp: prefs.navSameApp,
                                       custom: prefs.navCustomBindings)

        if prefs.focusEnabled,
           inputs == self.registeredInputs {
            return
        }

        self.unregisterAll()
        self.failedCustomSlots = []
        self.failedPresetCount = 0

        defer {
            NotificationCenter.default.post(name: .hotKeyRegistrationsUpdated,
                                            object: nil)
        }

        guard prefs.focusEnabled else {
            return
        }

        self.registeredInputs = inputs
        self.installEventHandlerIfNeeded()

        for entry in HotKeyPlan.entries(for: inputs) {
            register(binding: entry.binding,
                     action: entry.action,
                     customSlot: entry.customSlot)
        }
    }

    func stop() {
        self.unregisterAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleHotKey(id: UInt32) {
        if let action = actionsByID[id] {
            self.handler?(action)
        }
    }

    // MARK: - Registration plumbing

    private func register(binding: KeyBinding,
                          action: Action,
                          customSlot: String? = nil) {
        let id = self.nextID
        self.nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(binding.keyCode),
                                         UInt32(binding.modifiers),
                                         EventHotKeyID(signature: hotKeySignature, id: id),
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)

        guard status == noErr, let ref else {
            // Another running app owns the combo: carry on with the rest.
            Self.log.error("Hotkey registration failed for keyCode \(binding.keyCode) (status \(status))")
            if let customSlot {
                self.failedCustomSlots.insert(customSlot)
            } else {
                self.failedPresetCount += 1
            }

            return
        }

        self.hotKeys.append(ref)
        self.actionsByID[id] = action
    }

    private func unregisterAll() {
        for ref in self.hotKeys {
            UnregisterEventHotKey(ref)
        }

        self.hotKeys.removeAll()
        self.actionsByID.removeAll()
        self.nextID = 1
        self.registeredInputs = nil
    }

    private func installEventHandlerIfNeeded() {
        guard self.eventHandler == nil else {
            return
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyEventHandler,
                            1,
                            &spec,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &self.eventHandler)
    }
}

/// C callback (nonisolated); Carbon dispatches on the main thread, so the
/// main-actor hop is an assume.
private func hotKeyEventHandler(_: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event,
          let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)

    guard status == noErr, hotKeyID.signature == hotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id

    MainActor.assumeIsolated {
        manager.handleHotKey(id: id)
    }

    return noErr
}
