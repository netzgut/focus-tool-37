//
//  KeyboardFocusEngine.swift
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

/// Hotkey -> enumerate -> score -> AX resolve -> raise / activate / warp
@MainActor
final class KeyboardFocusEngine {

    private let prefs = Preferences.shared
    private let highlight = FocusHighlightOverlay()
    private var lastActionTime: ContinuousClock.Instant?
    private var activationCheck: Task<Void, Never>?

    private static let log = Logger(subsystem: "net.netzgut.focustool37", category: "focus")

    /// How long a regular activation gets before the AX fallback steps in
    private static let activationGrace: Duration = .milliseconds(150)

    /// Fired after focus actually landed on a window in that direction, so the
    /// status item can point the way.
    /// Dead ends and vanished targets stay quiet.
    var onDidMove: ((Direction) -> Void)?

    func perform(_ action: HotKeyManager.Action) {
        guard self.prefs.focusEnabled else {
            return
        }

        // A stuck key must not stampede through every window.
        let now = ContinuousClock.now
        if let last = self.lastActionTime,
           now - last < .milliseconds(80) {
            return
        }

        self.lastActionTime = now

        switch action {
        case let .focus(direction):
            move(direction,
                 sameAppOnly: false)
        case let .focusSameApp(direction):
            move(direction,
                 sameAppOnly: true)
        }
    }

    // MARK: - Directional move

    private func move(_ direction: Direction,
                      sameAppOnly: Bool) {
        let windows = WindowEnumerator.onScreenWindows()
        guard !windows.isEmpty else {
            return
        }

        var sourceFrame: CGRect?
        var sourceID: CGWindowID?
        var sourcePID: pid_t?

        if let app = NSWorkspace.shared.frontmostApplication,
           let axWindow = AX.focusedWindow(ofPID: app.processIdentifier),
           let axFrame = AX.frame(of: axWindow) {

            sourcePID = app.processIdentifier

            // Resolve into the CG snapshot: the matched entry's bounds become
            // the source rect and its windowID the exclusion key.
            if let match = windows.first(where: {
                $0.pid == app.processIdentifier && AX.framesMatch($0.frame, axFrame)
            }) {
                sourceFrame = match.frame
                sourceID = match.windowID
            } else {
                sourceFrame = axFrame // rare: mid-animation
            }
        }

        if sourceFrame == nil {
            // Nothing focused: frontmost window on the cursor's display.
            let cursorDisplay = Displays.id(containing: CursorWarp.location)
            if let match = windows.first(where: {
                Displays.id(containing: CGPoint(x: $0.frame.midX, y: $0.frame.midY)) == cursorDisplay
            }) {
                sourceFrame = match.frame
                sourceID = match.windowID
                sourcePID = match.pid
            }
        }

        guard let source = sourceFrame else {
            return
        }

        var candidates = windows

        if let sourceID {
            candidates.removeAll { $0.windowID == sourceID }
        } else {
            candidates.removeAll { AX.framesMatch($0.frame, source) }
        }

        if sameAppOnly, let sourcePID {
            // ⇧ variant: same scoring, one pid
            candidates.removeAll { $0.pid != sourcePID }
        }

        guard let index = DirectionalFocus.pick(from: source,
                                                direction: direction,
                                                candidates: candidates.map(\.frame),
                                                edgeSlop: CGFloat(prefs.navEdgeSlopPx),
                                                coneAngleDeg: CGFloat(prefs.navConeAngleDeg)) else {
            // dead end: silent no-op, no wrap
            return
        }

        if self.focus(candidates[index]) {
            onDidMove?(direction)
        }
    }

    // MARK: - Acting on the chosen window

    /// Returns false when the target can't be reached any more.
    private func focus(_ target: WindowInfo) -> Bool {
        guard let axWindow = AX.window(pid: target.pid,
                                       matching: target.frame) else {
            return false // target quit between enumeration and raise
        }

        AX.raise(axWindow)
        AX.makeMain(axWindow)

        if target.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let app = NSRunningApplication(processIdentifier: target.pid) {

            // Activation is cooperative since macOS 14: while our own settings
            // window makes us the active app, the request is ignored unless we
            // hand over first.
            // The window would be raised, but we'd stay active, and every next
            // move would start from the settings window again.
            // Yielding while inactive is a no-op.
            NSApp.yieldActivation(to: app)
            app.activate()
            ensureActivated(app)
        }

        self.highlight.flash(around: target.frame,
                             window: axWindow)

        announce(target, axWindow)
        warpIfAllowed(to: target)

        return true
    }

    /// Another app that is active doesn't yield to us, so macOS may ignore the
    /// activation: the window is raised and outlined, but its app never takes
    /// the keyboard, and the next move starts from the old app again.
    /// If the target isn't frontmost after a moment, force it through Accessibility.
    private func ensureActivated(_ app: NSRunningApplication) {
        self.activationCheck?.cancel()
        self.activationCheck = Task { [weak self] in
            try? await Task.sleep(for: Self.activationGrace)
            guard !Task.isCancelled, self != nil else {
                return
            }

            let frontmost = NSWorkspace.shared.frontmostApplication
            guard frontmost?.processIdentifier != app.processIdentifier,
                  !app.isTerminated else {
                return
            }

            Self.log.info("""
            Activation of \(app.bundleIdentifier ?? "?", privacy: .public) ignored, \
            \(frontmost?.bundleIdentifier ?? "?", privacy: .public) stayed frontmost; forcing via AX
            """)

            AX.makeFrontmost(pid: app.processIdentifier)
        }
    }

    private func announce(_ target: WindowInfo,
                          _ axWindow: AXUIElement) {
        guard VoiceOver.isRunning else {
            return
        } // skip the AX title round-trip

        let app = NSRunningApplication(processIdentifier: target.pid)?.localizedName
        let parts = [app, AX.title(of: axWindow)].compactMap(\.self)

        let message = parts.isEmpty ? String(localized: "a11y.focus-moved") : parts.joined(separator: ", ")

        VoiceOver.announce(message)
    }

    /// Both branches warp directly, so ⌥⌘L feels identical whether or not the neighbour belongs to another app.
    /// No heuristic needed: the hotkey is the intent and the target is already known.
    private func warpIfAllowed(to target: WindowInfo) {
        let center = CGPoint(x: target.frame.midX, y:
                                target.frame.midY)
        guard let targetDisplay = Displays.id(containing: center) else {
            return
        }

        let cursor = CursorWarp.location
        if self.prefs.warpAcrossDisplaysOnly,
           Displays.id(containing: cursor) == targetDisplay {
            return // only teleport when otherwise stranded
        }

        CursorWarp.warp(to: center)
        CursorPulse.pulse(at: center)
    }
}
