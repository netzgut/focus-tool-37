//
//  HotKeyPlanTests.swift
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

import Carbon.HIToolbox
import XCTest

/// Which combo gets which action: custom slots first, presets skip what's
/// claimed, ⇧ variants only for presets.
final class HotKeyPlanTests: XCTestCase {

    private func plan(vim: Bool = false,
                      arrows: Bool = false,
                      sameApp: Bool = false,
                      custom: [String: KeyBinding] = [:]) -> [HotKeyPlan.Entry] {

        HotKeyPlan.entries(for: HotKeyPlan.Inputs(vimKeys: vim,
                                                  arrowKeys: arrows,
                                                  sameApp: sameApp,
                                                  custom: custom))
    }

    private func optCmd(_ keyCode: Int) -> KeyBinding {
        KeyBinding(keyCode: keyCode,
                   modifiers: HotKeyPlan.optCmd)
    }

    private func optCmdShift(_ keyCode: Int) -> KeyBinding {
        KeyBinding(keyCode: keyCode,
                   modifiers: HotKeyPlan.optCmdShift)
    }

    func testNothingEnabledPlansNothing() {
        // ACT
        let entries = plan()

        // ASSERT
        XCTAssertTrue(entries.isEmpty)
    }

    func testBothPresetsPlanEight() {
        // ACT
        let entries = plan(vim: true,
                           arrows: true)

        // ASSERT
        XCTAssertEqual(entries.count, 8)
        XCTAssertTrue(entries.allSatisfy { $0.customSlot == nil })
        XCTAssertTrue(entries.contains(HotKeyPlan.Entry(binding: optCmd(kVK_ANSI_L),
                                                        action: .focus(.right),
                                                        customSlot: nil)))
        XCTAssertTrue(entries.contains(HotKeyPlan.Entry(binding: optCmd(kVK_DownArrow),
                                                        action: .focus(.down),
                                                        customSlot: nil)))
    }

    func testSameAppAddsShiftVariants() {
        // ACT
        let entries = plan(vim: true,
                           arrows: true,
                           sameApp: true)

        // ASSERT
        XCTAssertEqual(entries.count, 16)
        XCTAssertTrue(entries.contains(HotKeyPlan.Entry(binding: optCmdShift(kVK_ANSI_H),
                                                        action: .focusSameApp(.left),
                                                        customSlot: nil)))
    }

    func testCustomOnly() {
        // ARRANGE
        let binding = KeyBinding(keyCode: kVK_ANSI_A,
                                 modifiers: controlKey | optionKey)

        // ACT
        let entries = plan(custom: ["left": binding])

        // ASSERT
        XCTAssertEqual(entries, [
            HotKeyPlan.Entry(binding: binding,
                             action: .focus(.left),
                             customSlot: "left")
        ])
    }

    func testCustomTakesPresetComboAndPresetSkipsIt() {
        // ARRANGE: ⌥⌘J is vim's "down"
        let custom = ["left": optCmd(kVK_ANSI_J)]

        // ACT
        let entries = plan(vim: true,
                           custom: custom)

        // ASSERT
        let onJ = entries.filter { $0.binding == optCmd(kVK_ANSI_J) }
        XCTAssertEqual(onJ, [
            HotKeyPlan.Entry(binding: optCmd(kVK_ANSI_J),
                             action: .focus(.left),
                             customSlot: "left")
        ])
        XCTAssertEqual(entries.count, 4) // the custom slot + vim's other three
    }

    func testCustomTakesShiftVariant() {
        // ARRANGE: ⌥⌘⇧H is vim's same-app "left"
        let custom = ["right": optCmdShift(kVK_ANSI_H)]

        // ACT
        let entries = plan(vim: true,
                           sameApp: true,
                           custom: custom)

        // ASSERT
        let onShiftH = entries.filter { $0.binding == optCmdShift(kVK_ANSI_H) }
        XCTAssertEqual(onShiftH.map(\.action), [.focus(.right)])
        XCTAssertEqual(entries.count, 8)
    }

    func testSameAppVariantsArePresetOnly() {
        // ARRANGE
        let custom = ["up": KeyBinding(keyCode: kVK_ANSI_W,
                                       modifiers: controlKey | optionKey)]

        // ACT
        let entries = plan(sameApp: true,
                           custom: custom)

        // ASSERT
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries.contains { $0.binding.modifiers & shiftKey != 0 })
    }

    func testDuplicateCustomComboGoesToFirstSlot() {
        // ARRANGE: saved before "Use anyway" moved combos between slots
        let binding = KeyBinding(keyCode: kVK_ANSI_X,
                                 modifiers: controlKey | optionKey)

        // ACT
        let entries = plan(custom: [
            "up": binding,
            "left": binding
        ])

        // ASSERT: slot order is left, down, up, right
        XCTAssertEqual(entries, [
            HotKeyPlan.Entry(binding: binding,
                             action: .focus(.left),
                             customSlot: "left")
        ])
    }
}
