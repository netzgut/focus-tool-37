//
//  OnboardingWindowController.swift
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
final class OnboardingWindowController: NSWindowController {

    private static let textWidth: CGFloat = 340.0

    init() {
        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "onboarding.window-title")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        super.init(window: window)

        // Sized from Auto Layout, so wrapped text grows the window instead of pushing
        // the buttons off its bottom.
        let content = self.makeContent()
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.center()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.accessibilityStatusChanged),
                                               name: .accessibilityStatusChanged,
                                               object: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func makeContent() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72.0),
            icon.heightAnchor.constraint(equalToConstant: 72.0)
        ])

        // The heading next to it already names the app
        icon.setAccessibilityElement(false)

        let title = NSTextField(wrappingLabelWithString: String(localized: "onboarding.title"))
        title.font = .systemFont(ofSize: 17.0,
                                 weight: .semibold)
        title.preferredMaxLayoutWidth = Self.textWidth

        let body = Self.label(String(localized: "onboarding.body"))

        // A real sequence, so it gets real numbers
        let steps = NSStackView(views: [
            Self.step(1, String(localized: "onboarding.step.open")),
            Self.step(2, String(localized: "onboarding.step.enable")),
            Self.step(3, String(localized: "onboarding.step.done"))
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 6.0

        let open = NSButton(title: String(localized: "action.open-system-settings"),
                            target: self,
                            action: #selector(self.openSystemSettings))
        open.keyEquivalent = "\r"

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 12.0
        buttons.addView(open,
                        in: .trailing)

        let text = NSStackView(views: [title, body, steps, buttons])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 14.0
        text.setCustomSpacing(8.0,
                              after: title)
        text.setCustomSpacing(22.0,
                              after: steps)

        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.trailingAnchor.constraint(equalTo: text.trailingAnchor).isActive = true

        // Explicit constraints rather than an outer stack: a top-aligned
        // stack doesn't hold its bottom inset, so the buttons ended up flush
        // with the window's bottom edge.
        // The text column sets the height.
        let content = NSView()
        text.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(icon)
        content.addSubview(text)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: content.topAnchor,
                                      constant: 36.0),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                          constant: 28.0),
            icon.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor,
                                         constant: -24.0),
            text.topAnchor.constraint(equalTo: content.topAnchor,
                                      constant: 36.0),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor,
                                          constant: 20.0),
            text.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                           constant: -32.0),
            text.bottomAnchor.constraint(equalTo: content.bottomAnchor,
                                         constant: -24.0)
        ])

        return content
    }

    private static func label(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.preferredMaxLayoutWidth = self.textWidth
        return label
    }

    private static func step(_ number: Int, _ string: String) -> NSView {
        let digit = NSTextField(labelWithString: "\(number).")
        digit.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                weight: .semibold)
        digit.textColor = .secondaryLabelColor
        digit.setContentHuggingPriority(.required,
                                        for: .horizontal)

        let text = self.label(string)
        text.preferredMaxLayoutWidth = self.textWidth - 22.0

        let row = NSStackView(views: [digit, text])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 6.0
        return row
    }

    // MARK: - Actions

    @objc private func openSystemSettings() {
        _ = AccessibilityPermission.promptIfNeeded()
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func accessibilityStatusChanged() {
        guard AccessibilityPermission.isTrusted else {
            return
        }

        self.close()
    }
}
