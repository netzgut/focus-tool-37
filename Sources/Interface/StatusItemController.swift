//
//  StatusItemController.swift
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

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    enum PermissionState {
        case waiting
        case granted
    }

    var permissionState: PermissionState = .waiting {
        didSet {
            self.updatePermissionItems()
            self.updateStatusIcon()
        }
    }

    var onOpenPreferences: (() -> Void)?

    /// Lets the app delegate re-check state the menu shows before it opens
    var onMenuNeedsUpdate: (() -> Void)?

    private let prefs = Preferences.shared
    private let statusItem: NSStatusItem

    private let permissionItem: NSMenuItem
    private let permissionActionItem: NSMenuItem
    private let permissionSeparator: NSMenuItem
    private let focusEnabledItem: NSMenuItem

    /// The last jump, shown as a ray off the dot until `moveDisplayTime` passes
    private var lastMove: Direction?
    private var lastMoveReset: Task<Void, Never>?
    private static let moveDisplayTime: Duration = .milliseconds(150)

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        self.permissionItem = NSMenuItem(title: String(localized: "menu-item.permission-needed"),
                                         action: nil,
                                         keyEquivalent: "")
        self.permissionItem.isEnabled = false

        // The system prompt shows once and is easy to dismiss; without a way
        // back the app just sits there doing nothing (§2).
        self.permissionActionItem = NSMenuItem(title: String(localized: "action.open-system-settings"),
                                               action: #selector(self.openAccessibilitySettings),
                                               keyEquivalent: "")
        self.permissionSeparator = .separator()

        self.focusEnabledItem = NSMenuItem(title: String(localized: "menu-item.focus-enabled"),
                                           action: #selector(self.toggleFocusEnabled),
                                           keyEquivalent: "")

        super.init()

        self.focusEnabledItem.target = self
        self.permissionActionItem.target = self

        self.permissionItem.image = Self.icon("exclamationmark.triangle")
        self.permissionActionItem.image = Self.icon("gear.badge")
        self.focusEnabledItem.image = Self.icon("keyboard")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(self.permissionItem)
        menu.addItem(self.permissionActionItem)
        menu.addItem(self.permissionSeparator)
        menu.addItem(self.focusEnabledItem)
        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: String(localized: "menu-item.preferences"),
                                   action: #selector(self.openPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.image = Self.icon("switch.2")
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "menu-item.quit"),
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.image = Self.icon("power")
        menu.addItem(quitItem)

        self.statusItem.menu = menu

        // The glyph tracks the master switch, which the prefs window can flip
        // too.
        // menuNeedsUpdate alone would only catch menu-driven changes.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.preferencesChanged),
                                               name: .preferencesChanged,
                                               object: nil)
        refreshState()
    }

    /// Briefly points the status glyph's ray the way focus just went.
    /// Another jump inside the window restarts the timer.
    func showMove(_ direction: Direction) {
        self.lastMove = direction

        updateStatusIcon()

        self.lastMoveReset?.cancel()
        self.lastMoveReset = Task { [weak self] in
            try? await Task.sleep(for: Self.moveDisplayTime)
            guard !Task.isCancelled, let self else {
                return
            }
            self.lastMove = nil
            self.updateStatusIcon()
        }
    }

    /// The status glyph says whether Focus Tool 37 is working: the viewfinder
    /// has a dot while it is, and is empty while it's switched off or still
    /// waiting for Accessibility access, so the state reads from the menu bar
    /// without opening anything.
    /// Right after a jump a ray leaves the dot in that direction.
    private func updateStatusIcon() {
        let granted = self.permissionState == .granted
        let working = granted && self.prefs.focusEnabled
        let glyph: StatusGlyph = working ? .dot(ray: self.lastMove) : .frame

        self.statusItem.button?.image = glyph.image

        // The glyph alone says nothing to VoiceOver, spell out both the app
        // and the state it's showing.
        let state = if !granted {
            String(localized: "menu-item.permission-needed")
        } else if self.prefs.focusEnabled {
            String(localized: "a11y.status.on")
        } else {
            String(localized: "a11y.status.off")
        }
        self.statusItem.button?.setAccessibilityLabel(Bundle.main.displayName)
        self.statusItem.button?.setAccessibilityValueDescription(state)
    }

    private static func icon(_ symbolName: String) -> NSImage? {
        let conf = NSImage.SymbolConfiguration(pointSize: 13.0,
                                               weight: .regular)
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: nil)?
            .withSymbolConfiguration(conf)
        image?.isTemplate = true
        return image
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_: NSMenu) {
        onMenuNeedsUpdate?()
        refreshState()
    }

    @objc private func preferencesChanged() {
        refreshState()
    }

    private func refreshState() {
        updateStatusIcon()

        self.focusEnabledItem.state = self.prefs.focusEnabled ? .on : .off
    }

    private func updatePermissionItems() {
        let granted = self.permissionState == .granted
        self.permissionItem.isHidden = granted
        self.permissionActionItem.isHidden = granted
        self.permissionSeparator.isHidden = granted
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    // MARK: - Actions

    @objc private func toggleFocusEnabled() {
        self.prefs.focusEnabled.toggle()
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }
}

/// The menu bar viewfinder, drawn instead of loaded as a symbol: every edge
/// snaps to device pixels at draw time, so the brackets stay sharp at 1× and
/// 2×. A symbol's straight strokes land between pixels at menu bar size and
/// look soft.
private enum StatusGlyph {
    case frame
    case dot(ray: Direction?)

    /// The canvas is whole points so the status button can center it on whole
    /// pixels. The glyph inside spans 14.5 pt starting half a point in: 29 px
    /// at 2×, an odd count, so the center lands on a pixel's middle and the
    /// 3 px ray lines up with the dot.
    private static let canvas: CGFloat = 16.0
    private static let origin: CGFloat = 0.5
    private static let extent: CGFloat = 14.5
    private static let inset: CGFloat = 0.5
    private static let arm: CGFloat = 4.5
    private static let stroke: CGFloat = 1.5
    private static let dotRadius: CGFloat = 2.25

    var image: NSImage {
        let size = NSSize(width: Self.canvas, height: Self.canvas)
        let image = NSImage(size: size,
                            flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else {
                return false
            }

            NSColor.black.setFill()
            self.draw(in: ctx)
            return true
        }
        image.isTemplate = true

        return image
    }

    private func draw(in ctx: CGContext) {
        let low = Self.origin + Self.inset
        let high = Self.origin + Self.extent - Self.inset
        let arm = Self.arm
        let stroke = Self.stroke

        // Two overlapping bars per corner; their round ends make the caps and
        // the outer corner.
        [
            CGRect(x: low,
                   y: low,
                   width: arm,
                   height: stroke),
            CGRect(x: low,
                   y: low,
                   width: stroke,
                   height: arm),
            CGRect(x: high - arm,
                   y: low,
                   width: arm,
                   height: stroke),
            CGRect(x: high - stroke,
                   y: low,
                   width: stroke,
                   height: arm),
            CGRect(x: low,
                   y: high - stroke,
                   width: arm,
                   height: stroke),
            CGRect(x: low,
                   y: high - arm,
                   width: stroke,
                   height: arm),
            CGRect(x: high - arm,
                   y: high - stroke,
                   width: arm,
                   height: stroke),
            CGRect(x: high - stroke,
                   y: high - arm,
                   width: stroke,
                   height: arm)
        ].forEach { Self.fillBar($0, in: ctx) }

        guard case let .dot(ray) = self else {
            return
        }

        let center = Self.origin + Self.extent / 2
        let radius = Self.dotRadius
        let dot = CGRect(x: center - radius,
                         y: center - radius,
                         width: 2 * radius,
                         height: 2 * radius)
        NSBezierPath(ovalIn: Self.snapped(dot, in: ctx)).fill()

        guard let ray else {
            return
        }

        // From one stroke width off the dot out to the frame's outer edge.
        let start = radius + stroke
        let length = center - low - start
        let rect = switch ray {
        case .right: CGRect(x: center + start,
                            y: center - stroke / 2.0,
                            width: length,
                            height: stroke)
        case .left: CGRect(x: low,
                           y: center - stroke / 2.0,
                           width: length,
                           height: stroke)
        case .up: CGRect(x: center - stroke / 2.0,
                         y: low,
                         width: stroke,
                         height: length)
        case .down: CGRect(x: center - stroke / 2.0,
                           y: center + start,
                           width: stroke,
                           height: length)
        }

        Self.fillBar(rect, in: ctx)
    }

    /// Round ends need a few pixels to read as round; on a 1× display they
    /// only smear the bar, so thin bars keep square ends.
    private static func fillBar(_ rect: CGRect, in ctx: CGContext) {
        let bar = snapped(rect, in: ctx)
        let device = ctx.convertToDeviceSpace(bar)
        let radius = min(device.width, device.height) >= 3.0 ? min(bar.width, bar.height) / 2.0 : .zero

        NSBezierPath(roundedRect: bar,
                     xRadius: radius,
                     yRadius: radius).fill()
    }

    /// Rounds the rect's edges to whole device pixels, keeping it at least one
    /// pixel thick.
    private static func snapped(_ rect: CGRect, in ctx: CGContext) -> CGRect {
        let device = ctx.convertToDeviceSpace(rect)
        let minX = device.minX.rounded()
        let minY = device.minY.rounded()
        let maxX = max(device.maxX.rounded(),
                       minX + 1)
        let maxY = max(device.maxY.rounded(),
                       minY + 1)

        return ctx.convertToUserSpace(CGRect(x: minX,
                                             y: minY,
                                             width: maxX - minX,
                                             height: maxY - minY))
    }
}
