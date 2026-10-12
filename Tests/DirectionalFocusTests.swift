//
//  DirectionalFocusTests.swift
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

import CoreGraphics
import XCTest

/// Synthetic rect layouts in global top-left coordinates.
/// +y is DOWN.
final class DirectionalFocusTests: XCTestCase {

    private let source = CGRect(x: .zero,
                                y: .zero,
                                width: 100.0,
                                height: 100.0)

    private func pick(_ direction: Direction,
                      in candidates: [CGRect],
                      from source: CGRect? = nil,
                      slop: CGFloat = 8.0,
                      cone: CGFloat = 45.0) -> Int? {

        DirectionalFocus.pick(from: source ?? self.source,
                              direction: direction,
                              candidates: candidates,
                              edgeSlop: slop,
                              coneAngleDeg: cone)
    }

    func testBandPicksSmallestGap() {
        // ARRANGE
        let near = CGRect(x: 120.0,
                          y: 10.0,
                          width: 100.0,
                          height: 100.0)
        let far = CGRect(x: 300.0,
                         y: 10.0,
                         width: 100.0,
                         height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [far, near])

        // ASSERT
        XCTAssertEqual(result, 1)
    }

    func testTopLeftOriginDownMeansIncreasingY() {
        // ARRANGE
        let below = CGRect(x: .zero,
                           y: 150.0,
                           width: 100.0,
                           height: 100.0)

        // ACT
        let resultDown = pick(.down,
                              in: [below])
        let resultUp = pick(.up,
                            in: [below])

        // ASSERT
        XCTAssertEqual(resultDown, 0)
        XCTAssertNil(resultUp)
    }

    func testLeftAndUpMirror() {
        // ARRANGE
        let leftOf = CGRect(x: -150.0,
                            y: .zero,
                            width: 100.0,
                            height: 100.0)
        let above = CGRect(x: .zero,
                           y: -150.0,
                           width: 100.0,
                           height: 100.0)

        // ACT
        let resultLeft = pick(.left,
                              in: [leftOf, above])
        let resultUp = pick(.up,
                            in: [leftOf, above])

        // ASSERT
        XCTAssertEqual(resultLeft, 0)
        XCTAssertEqual(resultUp, 1)
    }

    func testBandRequiresPerpendicularOverlap() {
        // ARRANGE
        // No y-overlap and 59° off-axis: fails the band AND the cone
        let wideDiagonal = CGRect(x: 120.0,
                                  y: 200.0,
                                  width: 100.0,
                                  height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [wideDiagonal])

        // ASSERT
        XCTAssertNil(result)
    }

    func testConeFallbackPicksDiagonal() {
        // ARRANGE
        // No y-overlap but ~39° off-axis: band empty, cone catches it
        let diagonal = CGRect(x: 150.0,
                              y: 120.0,
                              width: 100.00,
                              height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [diagonal])

        // ASSERT
        XCTAssertEqual(result, 0)
    }

    func testBandBeatsCloserDiagonal() {
        // ARRANGE
        let bandedFar = CGRect(x: 400.0,
                               y: 20.0,
                               width: 100.0,
                               height: 100.0)
        let diagonalNear = CGRect(x: 120.0,
                                  y: 130.0,
                                  width: 100.0,
                                  height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [diagonalNear, bandedFar])

        // ASSERT
        XCTAssertEqual(result, 1)
    }

    func testNearFlushNeighbourBeatsFartherBandCandidate() {
        // ARRANGE
        // 5 pt overlap along x. Inside the default 8 pt slop it's a band
        // candidate winning by smallest gap.
        // With slop 0 it reclassifies as a pass-0 overlap (it overlaps and
        // extends beyond the edge).
        // Either way it beats the farther clean neighbour.
        let flush = CGRect(x: 95.0,
                           y: .zero,
                           width: 100.0,
                           height: 100.0)
        let banded = CGRect(x: 150.0,
                            y: .zero,
                            width: 100.0,
                            height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [banded, flush])
        let resultSlopZero = pick(.right,
                                  in: [banded, flush],
                                  slop: 0)

        // ASSERT
        XCTAssertEqual(result, 1)
        XCTAssertEqual(resultSlopZero, 1)
    }

    func testPerpendicularCentreTieBreak() {
        // ARRANGE
        let aligned = CGRect(x: 150.0,
                             y: .zero,
                             width: 100.0,
                             height: 100.0)
        let offset = CGRect(x: 150.0,
                            y: 80.0,
                            width: 100.0,
                            height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [offset, aligned])

        // ASSERT
        XCTAssertEqual(result, 1)
    }

    func testZOrderTieBreak() {
        // ARRANGE
        // Perfectly stacked candidates: the frontmost (lower index) wins
        let stacked = CGRect(x: 150.0,
                             y: .zero,
                             width: 100.0,
                             height: 100.00)

        // ACT
        let result = pick(.right,
                          in: [stacked, stacked])

        // ASSERT
        XCTAssertEqual(result, 0)
    }

    func testDeadEndIsNil() {
        // ARRANGE
        let rightOnly = CGRect(x: 200.0,
                               y: .zero,
                               width: 100.0,
                               height: 100.0)

        // ACT
        let resultLeftOnly = pick(.left,
                                  in: [])
        let resultRightOnly = pick(.left,
                                   in: [rightOnly])

        // ASSERT
        XCTAssertNil(resultLeftOnly)
        XCTAssertNil(resultRightOnly)
    }

    func testCrossDisplayContinuation() {
        // ARRANGE
        // The band doesn't care about display boundaries
        let rightHalfOfDisplay1 = CGRect(x: 1000.0,
                                         y: .zero,
                                         width: 600.0,
                                         height: 900.0)
        let onDisplay2 = CGRect(x: 1700.0,
                                y: 100.0,
                                width: 800.0,
                                height: 700.0)

        // ACT
        let result = pick(.right,
                          in: [onDisplay2],
                          from: rightHalfOfDisplay1)

        // ASSERT
        XCTAssertEqual(result, 0)
    }

    func testOverlappingWindowInDirectionOfTravelWinsFirst() {
        // ARRANGE
        // A window underneath the source whose centre lies to the right beats
        // the clean neighbour farther right — but only in that direction.
        let underneath = CGRect(x: 50.0,
                                y: 20.0,
                                width: 300.0,
                                height: 100.0)
        let neighbour = CGRect(x: 120.0,
                               y: .zero,
                               width: 100.0,
                               height: 100.0)

        // ACT
        let resultRight = pick(.right,
                               in: [neighbour, underneath])
        let resultLeft = pick(.left,
                              in: [underneath])

        // ASSERT
        XCTAssertEqual(resultRight, 1)
        XCTAssertNil(resultLeft)
    }

    func testCentredOverlappingWindowIsNoTarget() {
        // ARRANGE
        // Centred exactly on the source: zero advance in every direction
        let inside = CGRect(x: 10.0,
                            y: 10.0,
                            width: 80.0,
                            height: 80.0)
        let neighbour = CGRect(x: 150.0,
                               y: .zero,
                               width: 100.0,
                               height: 100.0)

        // ACT
        let result = pick(.right,
                          in: [inside, neighbour])

        // ASSERT
        XCTAssertEqual(result, 1)
    }

    func testOffsetInsideWindowIsATarget() {
        // ARRANGE
        // Fully inside the source but shifted right: reachable going right,
        // invisible going left — each window lies in exactly one direction.
        let insideRight = CGRect(x: 40.0,
                                 y: 20.0,
                                 width: 50.0,
                                 height: 50.0)

        // ACT
        let resultRight = pick(.right,
                               in: [insideRight])
        let resultLeft = pick(.left,
                              in: [insideRight])

        // ASSERT
        XCTAssertEqual(resultRight, 0)
        XCTAssertNil(resultLeft)
    }

    func testNearestCentreWinsAmongOverlapping_zOrderIrrelevant() {
        // ARRANGE
        // Advance ranking, not z-order: the window with the nearer centre
        // wins from either position in the candidate list.
        let near = CGRect(x: 60.0,
                          y: 5.0,
                          width: 300.0,
                          height: 100.0) // centre x 210
        let far = CGRect(x: 40.0,
                         y: 10.0,
                         width: 400.0,
                         height: 120.0) // centre x 240

        // ACT
        let result1 = pick(.right,
                           in: [near, far])
        let result2 = pick(.right,
                           in: [far, near])

        // ASSERT
        XCTAssertEqual(result1, 0)
        XCTAssertEqual(result2, 1)
    }

    func testFullScreenBackgroundDoesNotShadowMiddleWindows() {
        // ARRANGE
        // Real-world regression (2026-08-14): Safari left, Xcode and Books in
        // the middle, Eclipse full-screen behind (or in front of) them.
        // Hidden windows are deliberate targets, and z-order must not decide:
        // going right from Safari reaches Xcode in every stacking order.
        let safari = CGRect(x: .zero,
                            y: 31.0,
                            width: 1720.0,
                            height: 1409.0)
        let eclipse = CGRect(x: .zero,
                             y: 31.0,
                             width: 3440.0,
                             height: 1409.0)
        let books = CGRect(x: 1208.0,
                           y: 192.0,
                           width: 1024.0,
                           height: 768.0)
        let xcode = CGRect(x: 972.0,
                           y: 233.0,
                           width: 1400.0,
                           height: 900.0)

        // ACT
        let result1 = pick(.right,
                           in: [eclipse, books, xcode],
                           from: safari)
        let result2 = pick(.right,
                           in: [xcode, eclipse, books],
                           from: safari)
        // Repeated presses walk the stack: Safari -> Xcode -> Eclipse ...
        let result3 = pick(.right,
                           in: [eclipse, books, safari],
                           from: xcode)
        // ... and Books sits above Xcode's centre, reachable going up
        let result4 = pick(.up,
                           in: [eclipse, books, safari],
                           from: xcode)
        // Going left from Eclipse steps to Xcode, not all the way to Safari
        let result5 = pick(.left,
                           in: [safari, books, xcode],
                           from: eclipse)

        // ASSERT
        XCTAssertEqual(result1, 2)
        XCTAssertEqual(result2, 0)
        // Repeated presses walk the stack: Safari -> Xcode -> Eclipse ...
        XCTAssertEqual(result3, 0)
        // ... and Books sits above Xcode's centre, reachable going up
        XCTAssertEqual(result4, 1)
        // Going left from Eclipse steps to Xcode, not all the way to Safari
        XCTAssertEqual(result5, 2)
    }

    func testConeAngleIsConfigurable() {
        // ARRANGE
        // ~39° off-axis: inside the default 45° cone, outside a 30° one
        let diagonal = CGRect(x: 150.0,
                              y: 120.0,
                              width: 100.0,
                              height: 100.0)

        // ACT
        let result1 = pick(.right,
                           in: [diagonal],
                           cone: 45)
        let result2 = pick(.right,
                           in: [diagonal],
                           cone: 30)

        // ASSERT
        XCTAssertEqual(result1, 0)
        XCTAssertNil(result2)
    }

    func testNegativeXDisplayLeftOfPrimary() {
        // ARRANGE: both windows on a display left of the primary one
        let source = CGRect(x: -1000.0,
                            y: 100.0,
                            width: 800.0,
                            height: 600.0)
        let left = CGRect(x: -1920.0,
                          y: 100.0,
                          width: 800.0,
                          height: 600.0)
        let right = CGRect(x: 100.0,
                           y: 100.0,
                           width: 800.0,
                           height: 600.0)

        // ACT
        let resultLeft = pick(.left,
                              in: [right, left],
                              from: source)
        let resultRight = pick(.right,
                               in: [right, left],
                               from: source)

        // ASSERT
        XCTAssertEqual(resultLeft, 1)
        XCTAssertEqual(resultRight, 0)
    }

    func testNegativeYDisplayAbovePrimary() {
        // ARRANGE: a display stacked above the primary one has negative y
        let above = CGRect(x: .zero,
                           y: -1080.0,
                           width: 100.0,
                           height: 900.0)

        // ACT
        let result = pick(.up,
                          in: [above])

        // ASSERT
        XCTAssertEqual(result, 0)
    }

    func testIdenticallyStackedWindowHasNoDirection() {
        // ARRANGE: e.g. two maximized windows on one display
        let stacked = self.source

        // ACT
        let results = Direction.allCases.map {
            pick($0,
                 in: [stacked])
        }

        // ASSERT: reached with ⌘-Tab, not by direction
        XCTAssertEqual(results, [nil, nil, nil, nil])
    }
}
