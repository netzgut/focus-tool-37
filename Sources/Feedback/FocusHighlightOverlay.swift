//
//  FocusHighlightOverlay.swift
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

/// Borderless click-through window that traces the newly focused window's frame in the accent colour for ~150 ms
@MainActor
final class FocusHighlightOverlay {

    private var window: NSWindow?
    private var fadeTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "net.netzgut.focustool37",
                                    category: "highlight")

    func flash(around cgFrame: CGRect,
               window target: AXUIElement) {
        guard Preferences.shared.showFocusHighlight else {
            return
        }

        let window = self.window ?? Self.makeWindow()
        self.window = window

        self.fadeTask?.cancel()

        // Resolved per flash: the colour can change in preferences, and a
        // dynamic NSColor also needs re-resolving when the appearance flips.
        let outline = Preferences.shared.highlightColor ?? .controlAccentColor
        window.contentView?.layer?.borderColor = outline.cgColor
        window.contentView?.layer?.borderWidth = Preferences.shared.highlightBorderWidth
        window.contentView?.layer?.cornerRadius = Self.cornerRadius(of: target)
        window.setFrame(CocoaCoords.rect(fromCG: cgFrame), display: false)
        window.alphaValue = 1
        window.orderFrontRegardless()

        self.fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))

            guard !Task.isCancelled else {
                return
            }

            self?.beginFade()

            try? await Task.sleep(for: .milliseconds(160))

            guard !Task.isCancelled else {
                return
            }

            self?.window?.orderOut(nil)
        }
    }

    /// No API reports a window's corner radius, but on macOS 26 a standard
    /// window's radius follows its chrome:
    /// - 26 pt with a toolbar
    /// - 20 pt with a compact one
    /// - 16 pt with only a title bar.
    /// Dialogs, panels and apps that draw their own frame keep the user's radius.
    private static func cornerRadius(of window: AXUIElement) -> CGFloat {
        let prefs = Preferences.shared
        guard prefs.highlightCornerRadiusAutomatic else {
            return prefs.highlightCornerRadius
        }

        let subrole = AX.subrole(of: window)
        let toolbar = AX.toolbarHeight(of: window)
        let radius: CGFloat = if AX.isFullScreen(window) {
            0
        } else if subrole != kAXStandardWindowSubrole {
            prefs.highlightCornerRadius
        } else if let toolbar {
            toolbar >= Self.regularToolbarHeight ? 26 : 20
        } else {
            16
        }

        // For calibrating against apps that don't fit the table:
        // log stream --level debug --predicate 'category == "highlight"'
        Self.log.debug("""
        subrole \(subrole ?? "none", privacy: .public), \
        toolbar \(toolbar.map { "\($0) pt" } ?? "none", privacy: .public) → radius \(radius) pt
        """)
        return radius
    }

    /// Compact toolbars sit around 38 pt tall, regular ones around 52 pt.
    private static let regularToolbarHeight: CGFloat = 45

    private func beginFade() {
        guard let window else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle
        ]

        let view = NSView()

        // Decoration, not content
        view.setAccessibilityElement(false)
        view.setAccessibilityRole(.unknown)

        view.wantsLayer = true

        window.contentView = view

        return window
    }
}
