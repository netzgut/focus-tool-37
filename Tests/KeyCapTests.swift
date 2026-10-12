//
//  KeyCapTests.swift
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
import XCTest

/// Only the layout-independent parts: labels of character keys depend on the
/// active input source of whatever machine runs the tests.
final class KeyCapTests: XCTestCase {

    func testModifierSymbolsFollowSystemOrder() {
        // ACT
        let symbols = KeyCap.modifierSymbols(cmdKey | shiftKey | optionKey | controlKey)

        // ASSERT
        XCTAssertEqual(symbols, "⌃⌥⇧⌘")
    }

    func testModifierSymbolsSkipUnsetModifiers() {
        XCTAssertEqual(KeyCap.modifierSymbols(cmdKey | optionKey), "⌥⌘")
        XCTAssertEqual(KeyCap.modifierSymbols(controlKey | shiftKey), "⌃⇧")
        XCTAssertEqual(KeyCap.modifierSymbols(0), "")
    }

    func testGlyphKeysAreLabelledWithoutTheLayout() {
        // ARRANGE
        let binding = KeyBinding(keyCode: kVK_LeftArrow,
                                 modifiers: optionKey | cmdKey)

        // ACT
        let label = KeyCap.label(for: binding)

        // ASSERT
        XCTAssertEqual(label, "⌥⌘←")
        XCTAssertEqual(KeyCap.keyLabel(forKeyCode: kVK_F12), "F12")
        XCTAssertEqual(KeyCap.keyLabel(forKeyCode: kVK_Return), "↩")
    }

    func testCarbonModifiersFromEventFlags() {
        // ACT
        let carbon = KeyCap.carbonModifiers(from: [.command, .option, .shift, .control])

        // ASSERT
        XCTAssertEqual(carbon, cmdKey | optionKey | shiftKey | controlKey)
    }

    func testCarbonModifiersIgnoreUnrelatedFlags() {
        // ACT: caps lock and fn must not end up in a stored binding
        let carbon = KeyCap.carbonModifiers(from: [.option, .capsLock, .function])

        // ASSERT
        XCTAssertEqual(carbon, optionKey)
    }

    func testCarbonModifiersRoundTripThroughSymbols() {
        // ACT
        let carbon = KeyCap.carbonModifiers(from: [.control, .command])

        // ASSERT
        XCTAssertEqual(KeyCap.modifierSymbols(carbon), "⌃⌘")
    }
}
