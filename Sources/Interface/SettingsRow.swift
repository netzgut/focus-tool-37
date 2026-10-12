//
//  SettingsRow.swift
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

/// Building blocks for the grouped-inset preferences layout:
/// A section header over a rounded card of rows, each row a title (with an optional
/// explanation) on the left and its control on the right , similar to the shape macOS
/// System Settings uses.
@MainActor
enum Settings {
    static let cardCornerRadius: CGFloat = 10.0
    static let rowInset: CGFloat = 16.0
    static let rowVerticalPadding: CGFloat = 9.0
    static let minRowHeight: CGFloat = 42.0

    /// Cards must **not** use `controlBackgroundColor`!
    /// It resolves to exactly the window background in both appearances
    /// (`#FFFFFF` light, `#1E1E1E` dark), so the groups render invisible
    /// and only the hairlines and headers suggest any grouping.
    /// Instead, a translucent overlay: darker than the window in light mode,
    /// lighter in dark, which is what makes each group read as its own panel.
    ///
    /// AppKit has no grouped-table control.
    /// System Settings gets this look from SwiftUI's `Form(.formStyle(.grouped))`.
    static let cardFill = NSColor(name: "FocusTool37CardFill") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(white: 1.0, alpha: 0.07)
        : NSColor(white: .zero, alpha: 0.045)
    }

    /// Rounded card holding `rows`, hairline-separated.
    static func card(_ rows: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = .zero
        box.cornerRadius = self.cardCornerRadius

        // Dynamic NSColor via NSBox, so light/dark switches redraw for free
        box.fillColor = self.cardFill
        box.contentViewMargins = .zero
        box.translatesAutoresizingMaskIntoConstraints = false

        // Announced as one group, so VoiceOver users can skip a whole section.
        box.setAccessibilityRole(.group)

        guard let content = box.contentView else {
            return box
        }

        var previous: NSView?
        for row in rows {
            if let above = previous {
                let separator = NSBox()
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(separator)

                NSLayoutConstraint.activate([
                    separator.topAnchor.constraint(equalTo: above.bottomAnchor),
                    separator.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                       constant: self.rowInset),
                    separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    separator.heightAnchor.constraint(equalToConstant: 1.0)
                ])

                previous = separator
            }

            row.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? content.topAnchor),
                row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: content.trailingAnchor)
            ])

            previous = row
        }

        if let previous {
            previous.bottomAnchor.constraint(equalTo: content.bottomAnchor).isActive = true
        }

        return box
    }

    /// Header + card + optional footnote, stacked
    static func section(_ title: String,
                        rows: [NSView],
                        footnote: SettingsFootnote? = nil) -> NSView {
        section(title,
                card: self.card(rows),
                footnote: footnote)
    }

    /// Same, around a card built elsewhere.
    /// For one whose rows change while the window is open, like the ignored-apps list.
    static func section(_ title: String,
                        card box: NSView,
                        footnote: SettingsFootnote? = nil) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: NSFont.systemFontSize,
                                  weight: .bold)

        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(header)

        NSLayoutConstraint.activate([
            // Headers line up with the row titles inside the card, not its edge.
            header.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor,
                                            constant: self.rowInset),
            header.trailingAnchor.constraint(lessThanOrEqualTo: headerRow.trailingAnchor),
            header.topAnchor.constraint(equalTo: headerRow.topAnchor),
            header.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor)
        ])

        box.setAccessibilityLabel(title)

        var views: [NSView] = [headerRow, box]
        if let footnote {
            views.append(footnote)
        }

        let stack = column(views,
                           spacing: 6.0)
        stack.setCustomSpacing(14.0,
                               after: headerRow)
        return stack
    }

    /// A pane with its title over its groups .
    static func pane(_ title: String,
                     groups: [NSView]) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 20.0,
                                  weight: .bold)

        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(header)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor,
                                            constant: self.rowInset),
            header.trailingAnchor.constraint(lessThanOrEqualTo: headerRow.trailingAnchor),
            header.topAnchor.constraint(equalTo: headerRow.topAnchor),
            header.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor)
        ])

        let stack = column([headerRow] + groups,
                           spacing: 22.0)
        stack.setCustomSpacing(16.0,
                               after: headerRow)
        return stack
    }

    /// A card with no header of its own, for a group the pane title already
    /// names.
    /// Same shape as `section`, minus the duplicate label.
    static func group(rows: [NSView],
                      footnote: SettingsFootnote? = nil) -> NSView {
        let box = card(rows)

        guard let footnote else {
            return box
        }

        return self.column([box, footnote],
                           spacing: 6.0)
    }

    /// Vertical stack whose children each span the full width.
    /// NSStackView's `.width` alignment doesn't bind reliably on nested stacks,
    /// so the equal-width constraints are stated outright.
    static func column(_ views: [NSView],
                       spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing

        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return stack
    }
}

/// One preferences row.
/// `isEnabled` dims the text along with the control, so a row gated by another
/// setting reads as unavailable rather than merely unresponsive.
@MainActor
final class SettingsRow: NSView {
    let control: NSView

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    init(title: String,
         subtitle: String? = nil,
         control: NSView) {

        self.control = control

        super.init(frame: .zero)

        self.titleLabel.stringValue = title
        self.subtitleLabel.font = .systemFont(ofSize: 11.0)
        self.subtitleLabel.textColor = .secondaryLabelColor
        self.subtitleLabel.preferredMaxLayoutWidth = 300.0
        self.subtitle = subtitle

        // A switch or slider carries no visible label of its own, so VoiceOver
        // would announce "on, switch" with no clue what it toggles (§18). The
        // control may be wrapped (slider + readout, recorder + button), so the
        // label lands on the first real control inside.
        Self.control(in: control).setAccessibilityLabel(title)
        Self.control(in: control).setAccessibilityHelp(subtitle)

        let text = NSStackView(views: [
            self.titleLabel,
            self.subtitleLabel
        ])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2.0
        text.translatesAutoresizingMaskIntoConstraints = false
        // Above the low-priority top pin below, so the stack keeps its text
        // height instead of stretching (and parking the title at its top).
        // (NSStackView's own hugging API, not setContentHuggingPriority.)
        text.setHuggingPriority(.defaultHigh,
                                for: .vertical)

        control.translatesAutoresizingMaskIntoConstraints = false
        // The text column absorbs the slack; the control keeps its own size.
        control.setContentHuggingPriority(.required,
                                          for: .horizontal)
        control.setContentCompressionResistancePriority(.required,
                                                        for: .horizontal)

        addSubview(text)
        addSubview(control)

        // Centered rather than pinned top and bottom: a title-only row is
        // shorter than minRowHeight, and the stretched stack would park the
        // title at its top. The low-priority pin keeps taller rows hugging
        // their text.
        let textTop = text.topAnchor.constraint(equalTo: topAnchor,
                                                constant: Settings.rowVerticalPadding)
        textTop.priority = .defaultLow

        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor,
                                          constant: Settings.rowInset),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor,
                                      constant: Settings.rowVerticalPadding),
            textTop,
            text.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor,
                                         constant: -Settings.rowVerticalPadding),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor,
                                             constant: 12.0),
            control.trailingAnchor.constraint(equalTo: trailingAnchor,
                                              constant: -Settings.rowInset),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor,
                                         constant: 6.0),
            control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor,
                                            constant: -6.0),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Settings.minRowHeight)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// The row's control, reaching inside wrappers like the slider + readout
    /// pair so accessibility attributes land on something focusable.
    private static func control(in view: NSView) -> NSView {
        if view is NSControl {
            return view
        }

        return view.subviews.first { $0 is NSControl } ?? view
    }

    /// Settable after the fact: the binding rows show registration failures here.
    var subtitle: String? {
        get {
            self.subtitleLabel.isHidden ? nil : self.subtitleLabel.stringValue
        }
        set {
            self.subtitleLabel.stringValue = newValue ?? ""
            self.subtitleLabel.isHidden = (newValue ?? "").isEmpty
            // Keep the spoken explanation in step with the visible one.
            Self.control(in: self.control).setAccessibilityHelp(newValue)
        }
    }

    var subtitleColor: NSColor {
        get {
            self.subtitleLabel.textColor ?? .secondaryLabelColor
        }
        set {
            self.subtitleLabel.textColor = newValue
        }
    }

    var isEnabled = true {
        didSet {
            (self.control as? NSControl)?.isEnabled = self.isEnabled
            for view in self.control.subviews.compactMap({ $0 as? NSControl }) {
                view.isEnabled = self.isEnabled
            }

            self.titleLabel.textColor = self.isEnabled ? .labelColor : .tertiaryLabelColor
            self.subtitleLabel.textColor = self.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        }
    }
}

/// Small secondary text under a card, inset to line up with the row titles.
/// It hides *itself* when empty.
@MainActor
final class SettingsFootnote: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    init(_ text: String = "") {
        super.init(frame: .zero)

        self.label.font = .systemFont(ofSize: 11.0)
        self.label.textColor = .secondaryLabelColor
        self.label.preferredMaxLayoutWidth = 440.0
        self.label.translatesAutoresizingMaskIntoConstraints = false

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(self.label)

        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                constant: Settings.rowInset),
            self.label.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                 constant: -Settings.rowInset),
            self.label.topAnchor.constraint(equalTo: topAnchor),
            self.label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.text = text
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    var text: String {
        get {
            self.label.stringValue
        }
        set {
            self.label.stringValue = newValue
            self.isHidden = newValue.isEmpty
        }
    }

    var textColor: NSColor {
        get {
            self.label.textColor ?? .secondaryLabelColor
        }
        set {
            self.label.textColor = newValue
        }
    }
}
