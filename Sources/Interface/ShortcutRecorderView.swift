//
//  ShortcutRecorderView.swift
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

/// A custom binding slot: click, type a combo, done.
/// Esc cancels, ⌫ clears the slot.
/// Captures the *physical* key, so bindings are key-code-based for free.
/// Conflict checking is the owner's job (onChange).
@MainActor
final class ShortcutRecorderView: NSView {

    var binding: KeyBinding? {
        didSet { self.updateTitle() }
    }

    /// Called with the newly recorded binding, or nil when cleared.
    var onChange: ((KeyBinding?) -> Void)?

    private let button = NSButton(title: "",
                                  target: nil,
                                  action: nil)
    private var monitor: Any?
    private var isRecording = false

    /// Only one recorder listens at a time
    private weak static var activeRecorder: ShortcutRecorderView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.button.bezelStyle = .rounded
        self.button.setButtonType(.momentaryPushIn)
        self.button.target = self
        self.button.action = #selector(self.toggleRecording)
        self.button.translatesAutoresizingMaskIntoConstraints = false

        addSubview(self.button)

        NSLayoutConstraint.activate([
            self.button.leadingAnchor.constraint(equalTo: leadingAnchor),
            self.button.trailingAnchor.constraint(equalTo: trailingAnchor),
            self.button.topAnchor.constraint(equalTo: topAnchor),
            self.button.bottomAnchor.constraint(equalTo: bottomAnchor),
            self.button.widthAnchor.constraint(greaterThanOrEqualToConstant: 140.0)
        ])

        self.updateTitle()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func refreshLabel() {
        updateTitle()
    }

    /// A pane switch takes the recorder out of the window, but the key monitor
    /// is app-wide and would keep capturing.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if self.isRecording {
            endRecording()
        }
    }

    /// Closing the window, switching apps or an alert: whatever comes next
    /// wasn't meant for this recorder.
    @objc private func windowDidResignKey(_: Notification) {
        endRecording()
    }

    @objc private func toggleRecording() {
        isRecording ? endRecording() : beginRecording()
    }

    private func beginRecording() {
        if let other = Self.activeRecorder,
           other !== self {
            other.endRecording()
        }

        Self.activeRecorder = self
        self.isRecording = true

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.windowDidResignKey),
                                               name: NSWindow.didResignKeyNotification,
                                               object: window)

        self.button.title = String(localized: "recorder.prompt")

        // The button's title changes in place, which VoiceOver doesn't announce on its own.
        self.button.setAccessibilityValueDescription(String(localized: "a11y.recorder.recording"))
        VoiceOver.announce(String(localized: "a11y.recorder.announcement"))

        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleKeyDown(event)
        }
    }

    private func endRecording() {
        self.isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        NotificationCenter.default.removeObserver(self,
                                                  name: NSWindow.didResignKeyNotification,
                                                  object: nil)

        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }

        updateTitle()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case kVK_Escape:
            endRecording()
            return nil
        case kVK_Delete:
            self.binding = nil
            endRecording()
            onChange?(nil)
            return nil
        default:
            let modifiers = KeyCap.carbonModifiers(from: event.modifierFlags)
            // A bare key (or shift-only) would shadow normal typing system-wide.
            guard modifiers & (cmdKey | optionKey | controlKey) != 0 else {
                NSSound.beep()
                return nil
            }
            let recorded = KeyBinding(keyCode: Int(event.keyCode),
                                      modifiers: modifiers)
            self.binding = recorded

            endRecording()
            onChange?(recorded)

            return nil
        }
    }

    private func updateTitle() {
        if self.isRecording {
            return
        }

        if let binding {
            self.button.title = KeyCap.label(for: binding)
            self.button.setAccessibilityValueDescription(KeyCap.spokenLabel(for: binding))
        } else {
            self.button.title = String(localized: "recorder.record")
            self.button.setAccessibilityValueDescription(String(localized: "a11y.recorder.not-set"))
        }
    }
}
