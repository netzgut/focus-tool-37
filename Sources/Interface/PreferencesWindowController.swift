//
//  PreferencesWindowController.swift
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
import Carbon.HIToolbox

/// Programmatic AppKit prefs window: a source-list sidebar beside one pane of
/// grouped cards with trailing switches, the System Settings idiom.
/// Controls write straight to Preferences, the window refreshes from
/// .preferencesChanged.
@MainActor
final class PreferencesWindowController: NSWindowController {

    private let prefs = Preferences.shared

    private let sidebar = SettingsSidebarViewController()
    private let detail = SettingsDetailViewController()

    /// Every pane is built once and kept, so `refresh()` can reach every
    /// control whichever pane happens to be showing.
    private var panes: [SettingsPane: NSView] = [:]

    /// Accessibility permission banner
    private var permissionSection: NSView!

    // General
    private var focusEnabledSwitch: NSSwitch!
    private var loginSwitch: NSSwitch!
    private var warpAcrossSwitch: NSSwitch!
    private var warpAcrossRow: SettingsRow!

    // Keyboard
    private var vimSwitch: NSSwitch!
    private var arrowSwitch: NSSwitch!
    private var sameAppSwitch: NSSwitch!
    private var vimRow: SettingsRow!
    private var arrowRow: SettingsRow!
    private var sameAppRow: SettingsRow!
    private var presetFailureNote: SettingsFootnote!

    // Custom bindings
    private var recorders: [String: ShortcutRecorderView] = [:]
    private var bindingRows: [String: SettingsRow] = [:]

    // Feedback
    private var highlightSwitch: NSSwitch!
    private var pulseSwitch: NSSwitch!
    private var colorWell: NSColorWell!
    private var colorResetButton: NSButton!
    private var colorRow: SettingsRow!
    private var radiusAutomaticSwitch: NSSwitch!
    private var radiusAutomaticRow: SettingsRow!
    private var radiusSlider: NSSlider!
    private var radiusValue: NSTextField!
    private var radiusRow: SettingsRow!
    private var widthSlider: NSSlider!
    private var widthValue: NSTextField!
    private var widthRow: SettingsRow!

    // Advanced
    private var slopSlider: NSSlider!
    private var slopValue: NSTextField!
    private var coneSlider: NSSlider!
    private var coneValue: NSTextField!

    private static let sidebarWidth: CGFloat = 200.0
    private static let contentWidth: CGFloat = 520.0
    private static let minContentHeight: CGFloat = 320.0
    private static let screenMargin: CGFloat = 40.0

    init() {
        let window = NSWindow(contentRect: NSRect(x: .zero,
                                                  y: .zero,
                                                  width: Self.sidebarWidth + Self.contentWidth,
                                                  height: 480.0),
                              styleMask: [
                                  .titled,
                                  .closable,
                                  .resizable,
                                  .fullSizeContentView
                              ],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "settings.window-title")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        super.init(window: window)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.preferencesChanged),
                                               name: .preferencesChanged,
                                               object: nil)

        // The colour well shows the system accent while no colour is picked,
        // so it has to follow a change in System Settings.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.preferencesChanged),
                                               name: NSColor.systemColorsDidChangeNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.registrationsUpdated),
                                               name: .hotKeyRegistrationsUpdated,
                                               object: nil)

        // Layout-aware labels re-render on input-source switches
        DistributedNotificationCenter.default().addObserver(self,
                                                            selector: #selector(self.inputSourceChanged),
                                                            name: NSNotification
                                                            .Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.accessibilityStatusChanged),
                                               name: .accessibilityStatusChanged,
                                               object: nil)

        self.panes = [
            .general: makeGeneralPane(),
            .keyboard: makeKeyboardPane(),
            .shortcuts: makeShortcutsPane(),
            .feedback: makeFeedbackPane(),
            .advanced: makeAdvancedPane(),
            .about: AboutPane.make()
        ]

        self.detail.contentWidth = Self.contentWidth
        self.detail.banner = makePermissionSection()

        self.sidebar.onSelect = { [weak self] pane in
            self?.showPane(pane)
        }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: self.sidebar)
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        sidebarItem.canCollapse = false

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: self.detail))
        window.contentViewController = split

        // The list takes the first key press, so arrow keys walk the panes before
        // anything has been clicked.
        window.initialFirstResponder = self.sidebar.firstResponderCandidate

        // Before measuring: the failure footnotes and the permission banner
        // are part of how tall a pane is, and both come from current state.
        refresh()

        window.setContentSize(NSSize(width: Self.sidebarWidth + Self.contentWidth,
                                     height: self.tallestPaneHeight(in: window)))

        // Horizontally fixed: both panes have a designed width, and there is
        // nothing useful for extra columns to do.
        window.contentMinSize = NSSize(width: Self.sidebarWidth + Self.contentWidth,
                                       height: Self.minContentHeight)
        window.contentMaxSize = NSSize(width: Self.sidebarWidth + Self.contentWidth,
                                       height: .greatestFiniteMagnitude)

        window.center()
    }

    /// The tallest pane decides the opening height, so switching panes never
    /// resizes the window under the pointer.
    ///
    /// Each pane is shown once to measure it.
    /// `fittingSize` on a pane that has never been in the hierarchy under-reports and a window
    /// sized from that opens short of its own content.
    /// Showing costs one layout pass each, once, at window creation.
    private func tallestPaneHeight(in window: NSWindow) -> CGFloat {
        var tallest: CGFloat = .zero

        for pane in SettingsPane.allCases {
            showPane(pane)
            window.layoutIfNeeded()

            if let view = self.panes[pane] {
                tallest = max(tallest,
                              self.detail.height(for: view))
            }
        }

        showPane(self.sidebar.selectedPane)

        // Not shown yet, so `window.screen` may still be nil.
        let screen = window.screen ?? NSScreen.main
        let available = (screen?.visibleFrame.height ?? .greatestFiniteMagnitude) - 2 * Self.screenMargin

        return min(max(tallest,
                       Self.minContentHeight),
                   max(available,
                       Self.minContentHeight))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Selects a pane from outside (e.g. the app menu's About item)
    func select(_ pane: SettingsPane) {
        self.sidebar.select(pane)
    }

    private func showPane(_ pane: SettingsPane) {
        guard let view = self.panes[pane] else {
            return
        }

        self.detail.show(view)
    }

    // MARK: - Panes

    /// Shown only while the grant is missing, and pinned above the pane rather
    /// than placed in one.
    /// It gates every feature in the window, so it must not be something a pane switch can hide.
    private func makePermissionSection() -> NSView {
        let button = NSButton(title: String(localized: "action.open-system-settings"),
                              target: self,
                              action: #selector(openAccessibilitySettings))
        button.controlSize = .small
        button.bezelStyle = .rounded

        self.permissionSection = Settings.section(String(localized: "settings.section.permission"),
                                                  rows: [
                                                    SettingsRow(title: String(localized: "settings.permission"),
                                                                subtitle: String(localized: "settings.permission.explanation"),
                                                                control: button)
                                                  ])

        return self.permissionSection
    }

    private func makeGeneralPane() -> NSView {
        self.focusEnabledSwitch = toggle(#selector(self.toggleFocusEnabled))
        self.loginSwitch = toggle(#selector(self.toggleLogin))

        return Settings.pane(SettingsPane.general.title, groups: [
            Settings.group(rows: [
                SettingsRow(title: String(localized: "settings.focus-enabled"),
                            control: self.focusEnabledSwitch),
                SettingsRow(title: String(localized: "settings.launch-at-login"),
                            control: self.loginSwitch)
            ])
        ])
    }

    private func makeKeyboardPane() -> NSView {
        self.vimSwitch = toggle(#selector(self.toggleVim))
        self.vimRow = SettingsRow(title: ShortcutNaming.preset(.vim),
                                  subtitle: "⌥⌘ H J K L",
                                  control: self.vimSwitch)

        self.arrowSwitch = toggle(#selector(self.toggleArrows))
        self.arrowRow = SettingsRow(title: ShortcutNaming.preset(.arrows),
                                    subtitle: "⌥⌘ ← ↓ ↑ →",
                                    control: self.arrowSwitch)

        self.sameAppSwitch = toggle(#selector(self.toggleSameApp))
        self.sameAppRow = SettingsRow(title: String(localized: "settings.same-app"),
                                      subtitle: String(localized: "settings.same-app.explanation"),
                                      control: self.sameAppSwitch)

        self.warpAcrossSwitch = toggle(#selector(self.toggleWarpAcross))
        self.warpAcrossRow = SettingsRow(title: String(localized: "settings.warp-across-displays"),
                                         subtitle: String(localized: "settings.warp-across-displays.explanation"),
                                         control: self.warpAcrossSwitch)

        self.presetFailureNote = SettingsFootnote()
        self.presetFailureNote.textColor = .systemRed

        return Settings.pane(SettingsPane.keyboard.title,
                             groups: [
                                Settings.group(rows: [
                                    self.vimRow,
                                    self.arrowRow,
                                    self.sameAppRow,
                                    self.warpAcrossRow
                                ],
                                               footnote: self.presetFailureNote)
                             ])
    }

    private func makeShortcutsPane() -> NSView {
        self.recorders = [:]
        self.bindingRows = [:]

        var rows: [NSView] = []
        for slot in Preferences.customSlots {
            let recorder = ShortcutRecorderView(frame: .zero)
            recorder.onChange = { [weak self] binding in
                self?.customBindingChanged(slot: slot,
                                           binding: binding)
            }

            self.recorders[slot] = recorder
            let row = SettingsRow(title: ShortcutNaming.slot(slot),
                                  control: recorder)
            row.subtitleColor = .systemRed
            self.bindingRows[slot] = row
            rows.append(row)
        }

        // No footnote: the recorder itself prompts with "⎋ cancels, ⌫ clears"
        // while recording.
        return Settings.pane(SettingsPane.shortcuts.title, groups: [
            Settings.group(rows: rows)
        ])
    }

    private func makeFeedbackPane() -> NSView {
        self.highlightSwitch = toggle(#selector(self.toggleHighlight))
        self.pulseSwitch = toggle(#selector(self.togglePulse))

        self.colorWell = NSColorWell()
        self.colorWell.target = self
        self.colorWell.action = #selector(self.highlightColorChanged)
        self.colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.colorWell.widthAnchor.constraint(equalToConstant: 44.0),
            self.colorWell.heightAnchor.constraint(equalToConstant: 24.0)
        ])

        // A colour well can't express "unset", so getting back to the system
        // accent needs its own control.
        self.colorResetButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!,
                                         target: self,
                                         action: #selector(self.resetHighlightColor))
        self.colorResetButton.bezelStyle = .accessoryBar
        self.colorResetButton.toolTip = String(localized: "settings.highlight-colour.reset")

        self.colorRow = SettingsRow(title: String(localized: "settings.highlight-colour"),
                                    subtitle: String(localized: "settings.highlight-colour.explanation"),
                                    control: self.row([
                                        self.colorResetButton,
                                        self.colorWell
                                    ]))

        // SettingsRow labels the first control it finds, which here is the
        // reset button.
        self.colorWell.setAccessibilityLabel(String(localized: "settings.highlight-colour"))
        self.colorResetButton.setAccessibilityLabel(String(localized: "settings.highlight-colour.reset"))

        self.radiusAutomaticSwitch = toggle(#selector(self.toggleRadiusAutomatic))
        self.radiusAutomaticRow = SettingsRow(title: String(localized: "settings.highlight-radius-automatic"),
                                              subtitle: String(localized: "settings.highlight-radius-automatic.explanation"),
                                              control: self.radiusAutomaticSwitch)

        (self.radiusSlider, self.radiusValue) = sliderControl(min: .zero,
                                                              max: 30.0,
                                                              action: #selector(self.radiusChanged))
        self.radiusRow = SettingsRow(title: String(localized: "settings.highlight-radius"),
                                     subtitle: String(localized: "settings.highlight-radius.explanation"),
                                     control: self.row([self.radiusSlider, self.radiusValue]))

        (self.widthSlider, self.widthValue) = sliderControl(min: 1.0,
                                                            max: 8.0,
                                                            action: #selector(self.widthChanged))
        self.widthRow = SettingsRow(title: String(localized: "settings.highlight-width"),
                                    control: self.row([self.widthSlider, self.widthValue]))

        return Settings.pane(SettingsPane.feedback.title,
                             groups: [
                                Settings.group(rows: [
                                    SettingsRow(title: String(localized: "settings.focus-highlight"),
                                                subtitle: String(localized: "settings.focus-highlight.explanation"),
                                                control: self.highlightSwitch),
                                    self.radiusAutomaticRow,
                                    self.radiusRow,
                                    self.widthRow,
                                    SettingsRow(title: String(localized: "settings.cursor-pulse"),
                                                subtitle: String(localized: "settings.cursor-pulse.explanation"),
                                                control: self.pulseSwitch),
                                    self.colorRow
                                ])
                             ])
    }

    private func makeAdvancedPane() -> NSView {
        (self.slopSlider, self.slopValue) = sliderControl(min: .zero,
                                                          max: 40.0,
                                                          action: #selector(self.slopChanged))
        (self.coneSlider, self.coneValue) = sliderControl(min: 15.0,
                                                          max: 75.0,
                                                          action: #selector(self.coneChanged))

        return Settings.pane(SettingsPane.advanced.title,
                             groups: [
                                 Settings.group(rows: [
                                     SettingsRow(title: String(localized: "settings.edge-slop"),
                                                 subtitle: String(localized: "settings.edge-slop.explanation"),
                                                 control: self.row([self.slopSlider, self.slopValue])),
                                     SettingsRow(title: String(localized: "settings.cone-angle"),
                                                 subtitle: String(localized: "settings.cone-angle.explanation"),
                                                 control: self.row([
                                                     self.coneSlider,
                                                     self.coneValue
                                                 ]))
                                 ]),
                                 Settings.section(String(localized: "settings.section.ignored-apps"),
                                                  card: IgnoredAppsView(),
                                                  footnote: SettingsFootnote(String(localized: "settings.ignored-apps.footnote")))
                             ])
    }

    // MARK: - Refresh

    @objc private func preferencesChanged() {
        refresh()
    }

    @objc private func registrationsUpdated() {
        refresh()
    }

    @objc private func inputSourceChanged() {
        for recorder in self.recorders.values {
            recorder.refreshLabel()
        }
    }

    @objc private func accessibilityStatusChanged() {
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    private func refresh() {
        self.detail.isBannerHidden = AccessibilityPermission.isTrusted

        self.focusEnabledSwitch.state = self.prefs.focusEnabled ? .on : .off
        self.loginSwitch.state = LoginItem.isEnabled ? .on : .off

        self.warpAcrossSwitch.state = self.prefs.warpAcrossDisplaysOnly ? .on : .off
        self.warpAcrossRow.isEnabled = self.prefs.focusEnabled

        let custom = self.prefs.navCustomBindings
        self.vimSwitch.state = self.prefs.navVimKeys ? .on : .off
        self.arrowSwitch.state = self.prefs.navArrowKeys ? .on : .off
        self.sameAppSwitch.state = self.prefs.navSameApp ? .on : .off
        self.vimRow.isEnabled = self.prefs.focusEnabled
        self.arrowRow.isEnabled = self.prefs.focusEnabled
        self.sameAppRow.isEnabled = self.prefs.focusEnabled && (self.prefs.navVimKeys || self.prefs.navArrowKeys)

        let failures = AppDelegate.shared?.hotKeyFailures
        for (slot, recorder) in self.recorders {
            recorder.binding = custom[slot]
            self.bindingRows[slot]?.isEnabled = self.prefs.focusEnabled
            let failed = failures?.customSlots.contains(slot) ?? false
            self.bindingRows[slot]?.subtitle = failed ? String(localized: "shortcut.failure.custom") : nil
        }

        let presetFailures = failures?.presetCount ?? 0
        // Setting the text empty hides the footnote and its spacing with it.
        // localizedStringWithFormat resolves the catalog's plural variations.
        self.presetFailureNote.text = presetFailures > 0 ? String.localizedStringWithFormat(String(localized: "shortcut.failure.presets"),
                                                                                            presetFailures) : ""

        self.highlightSwitch.state = self.prefs.showFocusHighlight ? .on : .off
        self.pulseSwitch.state = self.prefs.showCursorPulse ? .on : .off

        self.radiusAutomaticRow.isEnabled = self.prefs.showFocusHighlight
        self.radiusAutomaticSwitch.state = self.prefs.highlightCornerRadiusAutomatic ? .on : .off
        self.radiusRow.isEnabled = self.prefs.showFocusHighlight
        self.radiusSlider.doubleValue = self.prefs.highlightCornerRadius
        self.radiusValue.stringValue = String(format: "%.0f px", self.prefs.highlightCornerRadius)
        self.radiusSlider.setAccessibilityValueDescription(String(format: String(localized: "a11y.value.points"),
                                                                  self.prefs.highlightCornerRadius))

        self.widthRow.isEnabled = self.prefs.showFocusHighlight
        self.widthSlider.doubleValue = self.prefs.highlightBorderWidth
        self.widthValue.stringValue = String(format: "%.0f px", self.prefs.highlightBorderWidth)
        self.widthSlider.setAccessibilityValueDescription(String(format: String(localized: "a11y.value.points"),
                                                                 self.prefs.highlightBorderWidth))

        let customColor = self.prefs.highlightColor
        self.colorWell.color = customColor ?? .controlAccentColor

        // Only pointless when neither cue is drawn.
        let anyCueVisible = self.prefs.showFocusHighlight || self.prefs.showCursorPulse
        self.colorRow.isEnabled = anyCueVisible

        // Nothing to reset while the colour still follows the accent.
        self.colorResetButton.isEnabled = anyCueVisible && customColor != nil

        self.slopSlider.doubleValue = self.prefs.navEdgeSlopPx
        self.slopValue.stringValue = String(format: "%.0f px", self.prefs.navEdgeSlopPx)
        self.coneSlider.doubleValue = self.prefs.navConeAngleDeg
        self.coneValue.stringValue = String(format: "%.0f°", self.prefs.navConeAngleDeg)

        // Otherwise VoiceOver reads a bare "8" and "45".
        self.slopSlider.setAccessibilityValueDescription(String(format: String(localized: "a11y.value.points"), self.prefs.navEdgeSlopPx))
        self.coneSlider.setAccessibilityValueDescription(String(format: String(localized: "a11y.value.degrees"),
                                                                self.prefs.navConeAngleDeg))
    }

    // MARK: - Actions

    @objc private func toggleFocusEnabled() {
        self.prefs.focusEnabled = self.focusEnabledSwitch.state == .on
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(self.loginSwitch.state == .on)
        self.refresh()
    }

    @objc private func toggleWarpAcross() {
        self.prefs.warpAcrossDisplaysOnly = self.warpAcrossSwitch.state == .on
    }

    @objc private func toggleHighlight() {
        self.prefs.showFocusHighlight = self.highlightSwitch.state == .on
    }

    @objc private func togglePulse() {
        self.prefs.showCursorPulse = self.pulseSwitch.state == .on
    }

    @objc private func highlightColorChanged() {
        self.prefs.highlightColor = self.colorWell.color
    }

    @objc private func resetHighlightColor() {
        self.prefs.highlightColor = nil
    }

    @objc private func toggleVim() {
        self.prefs.navVimKeys = self.vimSwitch.state == .on
    }

    @objc private func toggleArrows() {
        self.prefs.navArrowKeys = self.arrowSwitch.state == .on
    }

    @objc private func toggleSameApp() {
        self.prefs.navSameApp = self.sameAppSwitch.state == .on
    }

    @objc private func toggleRadiusAutomatic() {
        self.prefs.highlightCornerRadiusAutomatic = self.radiusAutomaticSwitch.state == .on
    }

    @objc private func radiusChanged() {
        let value = self.radiusSlider.doubleValue.rounded()
        self.radiusValue.stringValue = String(format: "%.0f px", value)
        if !Self.isDraggingSlider {
            self.prefs.highlightCornerRadius = value
        }
    }

    @objc private func widthChanged() {
        let value = self.widthSlider.doubleValue.rounded()
        self.widthValue.stringValue = String(format: "%.0f px", value)
        if !Self.isDraggingSlider {
            self.prefs.highlightBorderWidth = value
        }
    }

    @objc private func slopChanged() {
        let value = self.slopSlider.doubleValue.rounded()
        self.slopValue.stringValue = String(format: "%.0f px", value)
        if !Self.isDraggingSlider {
            self.prefs.navEdgeSlopPx = value
        }
    }

    @objc private func coneChanged() {
        let value = self.coneSlider.doubleValue.rounded()
        self.coneValue.stringValue = String(format: "%.0f°", value)
        if !Self.isDraggingSlider {
            self.prefs.navConeAngleDeg = value
        }
    }

    /// Sliders are continuous so the readout follows the knob, but the value
    /// is only saved once the knob is let go.
    /// Keyboard and VoiceOver steps aren't mouse events, so they save right away.
    private static var isDraggingSlider: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged: true
        default: false
        }
    }

    // MARK: - Custom bindings + conflict pre-check

    private func customBindingChanged(slot: String,
                                      binding: KeyBinding?) {
        guard let binding else {
            var bindings = self.prefs.navCustomBindings
            bindings.removeValue(forKey: slot)
            self.prefs.navCustomBindings = bindings
            return
        }

        if let conflict = ShortcutConflicts.description(for: binding, slot: slot) {
            let alert = NSAlert()
            alert.messageText = String(localized: "conflict.title")
            alert.informativeText = String(format: String(localized: "conflict.message"),
                                           KeyCap.label(for: binding),
                                           conflict)
            alert.addButton(withTitle: String(localized: "conflict.use-anyway"))
            alert.addButton(withTitle: String(localized: "conflict.pick-another"))
            guard alert.runModal() == .alertFirstButtonReturn else {
                refresh() // revert the recorder to the stored binding
                return
            }
        }

        var bindings = self.prefs.navCustomBindings

        // "Use anyway" on another slot's combo moves it here: Carbon refuses a
        // second claim, so keeping both would leave one slot silently dead.
        for (otherSlot, other) in bindings where otherSlot != slot && other == binding {
            bindings.removeValue(forKey: otherSlot)
        }

        bindings[slot] = binding
        self.prefs.navCustomBindings = bindings
    }

    // MARK: - Layout helpers

    private func toggle(_ action: Selector) -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .small
        control.target = self
        control.action = action
        return control
    }

    private func sliderControl(min: Double,
                               max: Double,
                               action: Selector) -> (NSSlider, NSTextField) {
        let slider = NSSlider(value: min,
                              minValue: min,
                              maxValue: max,
                              target: self,
                              action: action)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 120.0).isActive = true

        let value = NSTextField(labelWithString: "")
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        value.textColor = .secondaryLabelColor
        // The slider speaks the same number with better context
        value.setAccessibilityElement(false)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.widthAnchor.constraint(equalToConstant: 44.0).isActive = true

        return (slider, value)
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8.0
        return stack
    }
}
