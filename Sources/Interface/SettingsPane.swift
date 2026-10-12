//
//  SettingsPane.swift
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

enum SettingsPane: Int, CaseIterable {
    case general
    case keyboard
    case shortcuts
    case feedback
    case advanced
    case about

    var title: String {
        switch self {
        case .general: String(localized: "settings.section.general")
        case .keyboard: String(localized: "settings.section.keyboard")
        case .shortcuts: String(localized: "settings.section.custom-shortcuts")
        case .feedback: String(localized: "settings.section.feedback")
        case .advanced: String(localized: "settings.section.advanced")
        case .about: String(localized: "settings.section.about")
        }
    }

    /// Accent-tinted in the list, which is the source-list idiom. `dpad` is
    /// the status item's own glyph — directional navigation is the app, so the
    /// row that configures it carries the same symbol.
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .keyboard: "dpad"
        case .shortcuts: "keyboard"
        case .feedback: "sparkles"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}
