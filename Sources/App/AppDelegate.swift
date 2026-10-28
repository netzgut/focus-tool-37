//
//  AppDelegate.swift
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
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) weak static var shared: AppDelegate?

    private static let log = Logger(subsystem: "net.netzgut.focustool37", category: "windows")

    private var statusItemController: StatusItemController?
    private var preferencesWindowController: PreferencesWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var dockWindows: Set<ObjectIdentifier> = []
    private var keyboardEngine: KeyboardFocusEngine?
    private var hotKeyManager: HotKeyManager?
    private var hasAccessibility = false
    private var permissionPoll: Task<Void, Never>?

    /// The prefs window reads registration failures for its inline notes
    var hotKeyFailures: (customSlots: Set<String>, presetCount: Int) {
        (self.hotKeyManager?.failedCustomSlots ?? [], self.hotKeyManager?.failedPresetCount ?? 0)
    }

    func applicationDidFinishLaunching(_: Notification) {
        Self.shared = self

        self.installMainMenu()

        self.statusItemController = StatusItemController()
        self.statusItemController?.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }
        self.statusItemController?.onMenuNeedsUpdate = { [weak self] in
            self?.verifyPermission()
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.preferencesChanged),
                                               name: .preferencesChanged,
                                               object: nil)

        if AccessibilityPermission.isTrusted {
            self.permissionGranted()
        } else {
            self.openOnboarding()
            self.waitForPermission()
        }
    }

    private func waitForPermission() {
        self.statusItemController?.permissionState = .waiting

        guard self.permissionPoll == nil else {
            return
        }

        // There is no completion callback for the accessibility grant.
        // Poll until the user flips the switch in System Settings.
        self.permissionPoll = Task { [weak self] in
            while !AccessibilityPermission.isTrusted {
                try? await Task.sleep(for: .seconds(1))
            }

            self?.permissionPoll = nil
            self?.permissionGranted()
        }
    }

    /// The grant can be revoked while running (System Settings, or a changed signature), so we
    /// need a way to check.
    private func verifyPermission() {
        guard self.hasAccessibility,
              !AccessibilityPermission.isTrusted else {
            return
        }

        // Registered hotkeys would keep swallowing their combos system-wide
        // while every move fails silently.
        self.hasAccessibility = false
        self.hotKeyManager?.stop()
        self.hotKeyManager = nil
        self.keyboardEngine = nil

        NotificationCenter.default.post(name: .accessibilityStatusChanged,
                                        object: nil)

        waitForPermission()
    }

    private func installMainMenu() {
        let appMenu = NSMenu()

        // About lives in the settings window, so this opens that pane rather
        // than the standard About panel.
        let aboutItem = appMenu.addItem(withTitle: String(localized: "menu-item.about"),
                                        action: #selector(self.showAbout),
                                        keyEquivalent: "")
        aboutItem.target = self

        appMenu.addItem(.separator())

        let prefsItem = appMenu.addItem(withTitle: String(localized: "menu-item.preferences"),
                                        action: #selector(self.showPreferences),
                                        keyEquivalent: ",")
        prefsItem.target = self

        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: String(localized: "menu-item.quit-app"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let windowMenu = NSMenu(title: String(localized: "menu.window"))
        windowMenu.addItem(withTitle: String(localized: "menu-item.close"),
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")

        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem(title: submenu.title,
                                  action: nil,
                                  keyEquivalent: "")
            item.submenu = submenu
            mainMenu.addItem(item)
        }

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        self.openPreferences()
        return true
    }

    @objc private func showPreferences() {
        self.openPreferences()
    }

    @objc private func showAbout() {
        self.openPreferences(at: .about)
    }

    private func openPreferences(at pane: SettingsPane? = nil) {
        if self.preferencesWindowController == nil {
            self.preferencesWindowController = PreferencesWindowController()
        }

        if let pane {
            self.preferencesWindowController?.select(pane)
        }

        self.show(self.preferencesWindowController)
    }

    private func openOnboarding() {
        if self.onboardingWindowController == nil {
            self.onboardingWindowController = OnboardingWindowController()
        }

        self.show(self.onboardingWindowController)
    }

    private func show(_ controller: NSWindowController?) {
        guard let controller,
              let window = controller.window else {
            return
        }

        if self.dockWindows.insert(ObjectIdentifier(window)).inserted {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.dockWindowWillClose),
                                                   name: NSWindow.willCloseNotification,
                                                   object: window)
        }

        NSApp.setActivationPolicy(.regular)

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        // GH-ISSUE #1
        // Since macOS 14, activation is only a request that can be declined,
        // e.g., when the launch wasn't user-initiated or the active app doesn't yield.
        // `makeKeyAndOrderFront` alone would then leave the window behind that app's
        // windows, so it's put on top regardless and becomes key on the first click.
        window.orderFrontRegardless()
        NSApp.activate()

        self.confirmActivation(for: window)
    }

    /// Declined activations are otherwise invisible, which makes them hard to pin down:
    /// log stream --predicate 'subsystem == "net.netzgut.focustool37" && category == "windows"'
    private func confirmActivation(for window: NSWindow) {
        Task { [weak window] in
            try? await Task.sleep(for: .milliseconds(300))

            guard let window,
                  window.isVisible,
                  !NSApp.isActive else {
                return
            }

            Self.log.info("""
            Activation declined for \(window.title, privacy: .public), \
            \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public) \
            stayed frontmost; retrying
            """)

            NSApp.activate()
        }
    }

    @objc private func dockWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification,
                                                  object: window)

        self.dockWindows.remove(ObjectIdentifier(window))

        if self.dockWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func permissionGranted() {
        self.hasAccessibility = true
        self.statusItemController?.permissionState = .granted

        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)

        VoiceOver.announce(String(localized: "a11y.permission-granted"))

        self.reconfigureEngines()
    }

    @objc private func preferencesChanged() {
        self.reconfigureEngines()
    }

    /// Engines start/stop purely from the current prefs: the single source of truth.
    /// Menu and (later) prefs window just write to Preferences.
    private func reconfigureEngines() {
        guard self.hasAccessibility else {
            return
        }

        guard Preferences.shared.focusEnabled else {
            self.hotKeyManager?.stop()
            self.hotKeyManager = nil
            self.keyboardEngine = nil
            return
        }

        if self.keyboardEngine == nil {
            let engine = KeyboardFocusEngine()
            engine.onDidMove = { [weak self] direction in
                self?.statusItemController?.showMove(direction)
            }

            self.keyboardEngine = engine

            let manager = HotKeyManager()
            manager.handler = { [weak self] action in
                guard let self else {
                    return
                }

                self.verifyPermission()
                self.keyboardEngine?.perform(action)
            }

            self.hotKeyManager = manager
        }
        // Presets may have changed, registrations are torn down and rebuilt on every prefs change.
        self.hotKeyManager?.rebuild()
    }
}
