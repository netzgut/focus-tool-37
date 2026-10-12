//
//  CursorPulse.swift
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

/// Post-warp cursor highlighting.
/// A brief expanding accent ring around the warp destination (~250 ms)
@MainActor
enum CursorPulse {

    static func pulse(at cgPoint: CGPoint) {
        guard Preferences.shared.showCursorPulse else {
            return
        }

        let size: CGFloat = 60
        let cgRect = CGRect(x: cgPoint.x - size / 2,
                            y: cgPoint.y - size / 2,
                            width: size,
                            height: size)

        let window = NSWindow(contentRect: CocoaCoords.rect(fromCG: cgRect),
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

        let view = NSView(frame: CGRect(origin: .zero,
                                        size: CGSize(width: size,
                                                     height: size)))
        view.wantsLayer = true

        // Decoration only, never announced or navigable
        view.setAccessibilityElement(false)
        view.setAccessibilityRole(.unknown)

        let ring = CAShapeLayer()
        let inset: CGFloat = 6
        ring.path = CGPath(ellipseIn: CGRect(x: inset,
                                             y: inset,
                                             width: size - inset * 2,
                                             height: size - inset * 2),
                           transform: nil)
        ring.fillColor = nil
        ring.strokeColor = (Preferences.shared.highlightColor ?? .controlAccentColor).cgColor
        ring.lineWidth = 3
        ring.frame = view.bounds

        view.layer?.addSublayer(ring)
        window.contentView = view
        window.orderFrontRegardless()

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4
        scale.toValue = 1.0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.25
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        ring.add(group, forKey: "pulse")

        // The capture keeps the window alive until the animation is done
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            window.orderOut(nil)
        }
    }
}
