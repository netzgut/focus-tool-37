//
//  SettingsSidebarViewController.swift
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
final class SettingsSidebarViewController: NSViewController {
    var onSelect: ((SettingsPane) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    private static let rowHeight: CGFloat = 32.0

    override func loadView() {
        self.tableView.style = .sourceList
        self.tableView.headerView = nil
        self.tableView.rowHeight = Self.rowHeight
        self.tableView.backgroundColor = .clear
        self.tableView.selectionHighlightStyle = .regular
        self.tableView.allowsEmptySelection = false
        self.tableView.allowsMultipleSelection = false
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane")))

        // Announced as a list of panes rather than an unlabelled table (§18).
        self.tableView.setAccessibilityLabel(String(localized: "a11y.settings-sections"))

        self.scrollView.documentView = self.tableView
        self.scrollView.drawsBackground = false
        self.scrollView.hasVerticalScroller = true
        self.scrollView.autohidesScrollers = true

        self.view = self.scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.select(.general)
    }

    var selectedPane: SettingsPane {
        SettingsPane(rawValue: self.tableView.selectedRow) ?? .general
    }

    func select(_ pane: SettingsPane) {
        self.tableView.selectRowIndexes(IndexSet(integer: pane.rawValue),
                                        byExtendingSelection: false)
    }

    /// The table is what should take the window's first key press before the user has clicked anything.
    var firstResponderCandidate: NSView {
        self.tableView
    }
}

extension SettingsSidebarViewController: NSTableViewDataSource {

    func numberOfRows(in _: NSTableView) -> Int {
        SettingsPane.allCases.count
    }
}

extension SettingsSidebarViewController: NSTableViewDelegate {

    func tableView(_: NSTableView,
                   viewFor _: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let pane = SettingsPane(rawValue: row) else {
            return nil
        }

        let image = NSImageView()
        image.image = NSImage(systemSymbolName: pane.symbolName,
                              accessibilityDescription: nil)
        image.contentTintColor = .controlAccentColor
        image.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: pane.title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        // Assigning imageView/textField is what lets the cell follow the
        // source list's selection tinting instead of staying stubbornly black.
        let cell = NSTableCellView()
        cell.imageView = image
        cell.textField = label
        cell.addSubview(image)
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor,
                                           constant: 4.0),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 20.0),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor,
                                           constant: 8.0),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor,
                                            constant: -8.0),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        self.onSelect?(self.selectedPane)
    }
}
