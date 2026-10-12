//
//  SettingsDetailViewController.swift
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

/// The right-hand side of the settings window:
/// an optional pinned banner over one scrolling pane.
///
/// Panes are swapped by replacing the scroll view's document view.
/// Each pane gets its own document view, built once on first show and kept, so the
/// scroll position of a pane survives switching away and back.
@MainActor
final class SettingsDetailViewController: NSViewController {

    /// Matches the width the panes were laid out against.
    var contentWidth: CGFloat = 520.0

    private static let margin: CGFloat = 20.0

    /// The window draws its content under a transparent title bar, so the
    /// pane heading needs to clear it by hand.
    private static let titleBarInset: CGFloat = 28.0

    private let bannerContainer = NSView()
    private let scrollView = NSScrollView()
    private var documents: [ObjectIdentifier: NSView] = [:]

    /// Pinned above the pane rather than placed in one: it gates every feature
    /// in the window, so a pane switch must not be able to hide it.
    var banner: NSView? {
        didSet {
            oldValue?.removeFromSuperview()

            guard let banner else {
                return
            }

            banner.translatesAutoresizingMaskIntoConstraints = false
            self.bannerContainer.addSubview(banner)

            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: self.bannerContainer.leadingAnchor,
                                                constant: Self.margin),
                banner.trailingAnchor.constraint(equalTo: self.bannerContainer.trailingAnchor,
                                                 constant: -Self.margin),
                banner.topAnchor.constraint(equalTo: self.bannerContainer.topAnchor,
                                            constant: Self.margin),
                banner.bottomAnchor.constraint(equalTo: self.bannerContainer.bottomAnchor)
            ])
        }
    }

    /// Hiding an arranged subview takes it out of the stack's layout, so the
    /// pane closes the gap once the grant lands.
    var isBannerHidden: Bool {
        get {
            self.bannerContainer.isHidden
        }
        set {
            self.bannerContainer.isHidden = newValue
        }
    }

    override func loadView() {
        self.scrollView.hasVerticalScroller = true
        self.scrollView.autohidesScrollers = true
        self.scrollView.drawsBackground = false
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false

        self.bannerContainer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            self.bannerContainer,
            self.scrollView
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = .zero
        stack.edgeInsets = NSEdgeInsets(top: Self.titleBarInset,
                                        left: .zero,
                                        bottom: .zero,
                                        right: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            self.bannerContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            self.scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        self.view = stack
    }

    func show(_ pane: NSView) {
        let document = self.document(for: pane)
        resize(document,
               toFit: pane)
        self.scrollView.documentView = document

        // Every pane opens at its top
        self.scrollView.contentView.scroll(to: .zero)
        self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
    }

    /// Height the window needs to show `pane` without scrolling, banner aside.
    func height(for pane: NSView) -> CGFloat {
        let document = self.document(for: pane)
        resize(document,
               toFit: pane)
        return document.frame.height + Self.titleBarInset
    }

    /// Panes are measured before the window has ever laid out, when wrapping
    /// labels still report a one-line height.
    /// Re-measuring on every show is what keeps a two-line subtitle from being
    /// clipped by a frame that was decided too early.
    private func resize(_ document: NSView,
                        toFit pane: NSView) {
        pane.layoutSubtreeIfNeeded()

        let height = pane.fittingSize.height + 2.0 * Self.margin
        guard abs(document.frame.height - height) > 0.5 else {
            return
        }

        let frameSize = NSSize(width: document.frame.width,
                               height: height)
        document.setFrameSize(frameSize)
    }

    /// The document view carries an explicit frame rather than constraints to
    /// the clip view: tying its height into the constraint system makes the
    /// window adopt the full content height instead of scrolling.
    private func document(for pane: NSView) -> NSView {
        let key = ObjectIdentifier(pane)
        if let existing = self.documents[key] {
            return existing
        }

        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(equalToConstant: self.contentWidth - 2.0 * Self.margin).isActive = true
        pane.layoutSubtreeIfNeeded()

        let document = FlippedView(frame: NSRect(x: .zero,
                                                 y: .zero,
                                                 width: self.contentWidth,
                                                 height: pane.fittingSize.height + 2.0 * Self.margin))

        document.autoresizingMask = [.width]
        document.addSubview(pane)

        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: document.leadingAnchor,
                                          constant: Self.margin),
            pane.topAnchor.constraint(equalTo: document.topAnchor,
                                      constant: Self.margin)
        ])

        self.documents[key] = document

        return document
    }
}

/// Document views scroll from the top down only when flipped.
private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
