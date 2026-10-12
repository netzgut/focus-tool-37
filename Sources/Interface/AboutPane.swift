//
//  AboutPane.swift
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
enum AboutPane {

    static func make() -> NSView {

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72.0),
            icon.heightAnchor.constraint(equalToConstant: 72.0)
        ])
        icon.setAccessibilityElement(false)

        let info = Bundle.main.infoDictionary ?? [:]

        let name = NSTextField(labelWithString: Bundle.main.displayName)
        name.font = .systemFont(ofSize: 17.0,
                                weight: .semibold)

        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"

        let versionLabel = NSTextField(labelWithString: String(format: String(localized: "about.version"),
                                                               version,
                                                               build))
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true

        let tagline = NSTextField(wrappingLabelWithString: String(localized: "about.tagline"))
        tagline.preferredMaxLayoutWidth = 340.0

        var lines: [NSView] = [name, versionLabel, tagline]
        if let copyright = info["NSHumanReadableCopyright"] as? String {
            let label = NSTextField(labelWithString: copyright)
            label.font = .systemFont(ofSize: 11.0)
            label.textColor = .secondaryLabelColor
            lines.append(label)
        }

        let text = NSStackView(views: lines)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4.0
        text.setCustomSpacing(12.0,
                              after: versionLabel)
        text.setCustomSpacing(12.0,
                              after: tagline)

        let identity = NSStackView(views: [icon, text])
        identity.orientation = .horizontal
        identity.alignment = .top
        identity.spacing = 16
        identity.edgeInsets = NSEdgeInsets(top: .zero,
                                           left: Settings.rowInset,
                                           bottom: .zero,
                                           right: Settings.rowInset)

        return Settings.pane(SettingsPane.about.title,
                             groups: [identity])
    }
}

extension Bundle {

    /// The user-facing app name from Info.plist.
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Focus Tool 37"
    }
}
