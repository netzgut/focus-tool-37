//
//  IgnoredAppsView.swift
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
import UniformTypeIdentifiers

/// User-editable exclusion list.
/// One card row per ignored app, each with its own remove button, and an "Add App…" row at the end.
///
/// Stores bundle IDs in `Preferences.ignoredBundleIDs`
@MainActor
final class IgnoredAppsView: NSView {
    private let prefs = Preferences.shared
    private var card: NSView?
    private var shownIDs: [String]?

    init() {
        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.preferencesChanged),
                                               name: .preferencesChanged,
                                               object: nil)
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func preferencesChanged() {
        reload()
    }

    /// Rebuilds the card, but only when the list itself changed: every other
    /// preference posts the same notification.
    private func reload() {
        let ids = self.prefs.ignoredBundleIDs
        guard ids != self.shownIDs else {
            return
        }
        self.shownIDs = ids

        var rows: [NSView] = Self.apps(for: ids).map { app in
            AppRow(app: app,
                   target: self,
                   action: #selector(self.remove(_:)))
        }

        if rows.isEmpty {
            rows.append(Self.emptyRow())
        }
        rows.append(addRow())

        self.card?.removeFromSuperview()
        let card = Settings.card(rows)

        addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        self.card = card
    }

    // MARK: - Rows

    private static func emptyRow() -> NSView {
        let label = NSTextField(labelWithString: String(localized: "settings.ignored-apps.empty"))
        label.textColor = .secondaryLabelColor
        return Self.padded(label)
    }

    private func addRow() -> NSView {
        let button = NSButton(title: String(localized: "settings.ignored-apps.add"),
                              target: self,
                              action: #selector(self.add))
        button.controlSize = .small
        button.bezelStyle = .rounded

        let row = NSView()
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor,
                                             constant: -Settings.rowInset),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: Settings.minRowHeight)
        ])

        return row
    }

    private static func padded(_ view: NSView) -> NSView {
        let row = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: row.leadingAnchor,
                                          constant: Settings.rowInset),
            view.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor,
                                           constant: -Settings.rowInset),
            view.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: Settings.minRowHeight)
        ])

        return row
    }

    // MARK: - Actions

    @objc private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = String(localized: "settings.ignored-apps.choose")
        panel.prompt = String(localized: "settings.ignored-apps.choose-button")

        let apply: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let self, let urls = panel?.urls else {
                return
            }

            self.ignore(urls)
        }

        if let window {
            panel.beginSheetModal(for: window,
                                  completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }

    /// Apps already excluded by the hardcoded floor are skipped: listing them
    /// would suggest that removing the row brings them back.
    private func ignore(_ urls: [URL]) {
        var ids = self.prefs.ignoredBundleIDs
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !ids.contains(id),
                  !Preferences.hardcodedExclusions.contains(id) else {
                continue
            }
            ids.append(id)
        }

        if ids != self.prefs.ignoredBundleIDs {
            self.prefs.ignoredBundleIDs = ids
        }
    }

    @objc private func remove(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else {
            return
        }

        self.prefs.ignoredBundleIDs.removeAll { $0 == id }
    }

    // MARK: - App lookup

    fileprivate struct App {
        let bundleID: String
        let name: String
        let icon: NSImage
    }

    /// Sorted by name, the order people scan a list of apps in.
    private static func apps(for ids: [String]) -> [App] {
        ids.map { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return App(bundleID: id,
                           name: id,
                           icon: NSWorkspace.shared.icon(for: .applicationBundle))
            }

            // displayName is localized, but keeps the extension when Finder shows all extensions.
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                name.removeLast(4)
            }

            return App(bundleID: id,
                       name: name,
                       icon: NSWorkspace.shared.icon(forFile: url.path))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Icon, name and remove button.
/// The button carries the bundle ID as its identifier, so one action serves every row.
private final class AppRow: NSView {

    init(app: IgnoredAppsView.App,
         target: AnyObject,
         action: Selector) {
        super.init(frame: .zero)

        let icon = NSImageView(image: app.icon)
        icon.setAccessibilityElement(false)

        let name = NSTextField(labelWithString: app.name)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow,
                                                     for: .horizontal)

        let remove = NSButton(image: NSImage(systemSymbolName: "minus.circle",
                                             accessibilityDescription: nil)!,
                              target: target,
                              action: action)
        remove.bezelStyle = .accessoryBar
        remove.identifier = NSUserInterfaceItemIdentifier(app.bundleID)
        let label = String(format: String(localized: "settings.ignored-apps.remove"),
                           app.name)
        remove.toolTip = label
        remove.setAccessibilityLabel(label)

        for view in [icon, name, remove] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor,
                                          constant: Settings.rowInset),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24.0),
            icon.heightAnchor.constraint(equalToConstant: 24.0),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor,
                                          constant: 8.0),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor,
                                           constant: -8.0),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor,
                                             constant: -Settings.rowInset),
            remove.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Settings.minRowHeight)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
