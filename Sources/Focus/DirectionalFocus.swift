//
//  DirectionalFocus.swift
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

enum Direction: CaseIterable, Sendable {
    case left,
         down,
         up,
         right
}

/// Scoring: pure geometry over global top-left rects.
/// Candidates are in z-order (frontmost first).
/// On exact ties the lower index wins.
enum DirectionalFocus {

    /// Returns the index of the winning candidate, or nil for a dead end
    /// (silent no-op upstream, no wrap-around).
    static func pick(from source: CGRect,
                     direction: Direction,
                     candidates: [CGRect],
                     edgeSlop: CGFloat = 8,
                     coneAngleDeg: CGFloat = 45) -> Int? {

        overlapPick(from: source,
                    direction: direction,
                    candidates: candidates,
                    edgeSlop: edgeSlop)
        ?? bandPick(from: source,
                    direction: direction,
                    candidates: candidates,
                    edgeSlop: edgeSlop)
        ?? conePick(from: source,
                    direction: direction,
                    candidates: candidates,
                    coneAngleDeg: coneAngleDeg)
    }

    // MARK: - Pass 0: overlapping windows, nearest centre advance

    /// A window overlapping the source whose centre lies beyond the source's
    /// centre in the direction of travel.
    /// The smallest centre advance wins, so repeated presses walk through an
    /// overlapping stack window by window.
    /// Ranking is spatial, never z-based: a full-screen window behind
    /// everything must not shadow the windows stacked above it, and fully
    /// covered windows stay reachable.
    /// Z-order only breaks exact ties (perfectly stacked windows).
    private static func overlapPick(from source: CGRect,
                                    direction: Direction,
                                    candidates: [CGRect],
                                    edgeSlop: CGFloat) -> Int? {

        var best: (advance: CGFloat, perpDist: CGFloat, index: Int)?

        for (index, candidate) in candidates.enumerated() {
            let (gap, perpOverlaps, perpDist) = bandValues(direction,
                                                           source: source,
                                                           candidate: candidate)

            // True overlap (more than the band's near-flush slop)...
            guard perpOverlaps, gap < -edgeSlop else {
                continue
            }

            // ...lying in the direction of travel, centre-to-centre.
            let advance = centreAdvance(direction,
                                        source: source,
                                        candidate: candidate)
            guard advance > 0 else {
                continue
            }

            if let current = best {
                if (advance, perpDist) < (current.advance, current.perpDist) {
                    best = (advance, perpDist, index)
                }
            } else {
                best = (advance, perpDist, index)
            }
        }

        return best?.index
    }

    /// How far the candidate's centre lies beyond the source's centre along
    /// the direction axis.
    /// Top-left origin: down = +y.
    private static func centreAdvance(_ direction: Direction,
                                      source s: CGRect,
                                      candidate c: CGRect) -> CGFloat {
        switch direction {
        case .right: c.midX - s.midX
        case .left: s.midX - c.midX
        case .down: c.midY - s.midY
        case .up: s.midY - c.midY
        }
    }

    // MARK: - Pass 1: edge band

    private static func bandPick(from source: CGRect,
                                 direction: Direction,
                                 candidates: [CGRect],
                                 edgeSlop: CGFloat) -> Int? {
        var best: (gap: CGFloat, perpDist: CGFloat, index: Int)?

        for (index, candidate) in candidates.enumerated() {
            let (gap, perpOverlaps, perpDist) = bandValues(direction,
                                                           source: source,
                                                           candidate: candidate)
            guard gap >= -edgeSlop, perpOverlaps else {
                continue
            }

            if let current = best {
                if (gap, perpDist) < (current.gap, current.perpDist) {
                    best = (gap, perpDist, index)
                }
            } else {
                best = (gap, perpDist, index)
            }
        }

        return best?.index
    }

    /// Gap along the direction axis, whether the candidate's perpendicular
    /// extent intersects the source's band, and the perpendicular distance
    /// between centres.
    /// Top-left origin: down = +y.
    private static func bandValues(_ direction: Direction,
                                   source s: CGRect,
                                   candidate c: CGRect) -> (gap: CGFloat, perpOverlaps: Bool, perpDist: CGFloat) {
        switch direction {
        case .right: (c.minX - s.maxX, c.maxY > s.minY && c.minY < s.maxY, abs(c.midY - s.midY))
        case .left: (s.minX - c.maxX, c.maxY > s.minY && c.minY < s.maxY, abs(c.midY - s.midY))
        case .down: (c.minY - s.maxY, c.maxX > s.minX && c.minX < s.maxX, abs(c.midX - s.midX))
        case .up: (s.minY - c.maxY, c.maxX > s.minX && c.minX < s.maxX, abs(c.midX - s.midX))
        }
    }

    // MARK: - Pass 2: cone fallback

    private static func conePick(from source: CGRect,
                                 direction: Direction,
                                 candidates: [CGRect],
                                 coneAngleDeg: CGFloat) -> Int? {
        let dir = switch direction {
        case .right: CGVector(dx: 1, dy: 0)
        case .left: CGVector(dx: -1, dy: 0)
        case .down: CGVector(dx: 0, dy: 1)
        case .up: CGVector(dx: 0, dy: -1)
        }

        let sourceCenter = CGPoint(x: source.midX,
                                   y: source.midY)

        var best: (score: CGFloat, index: Int)?

        for (index, candidate) in candidates.enumerated() {
            let v = CGVector(dx: candidate.midX - sourceCenter.x,
                             dy: candidate.midY - sourceCenter.y)

            let along = v.dx * dir.dx + v.dy * dir.dy
            guard along > 0 else {
                continue
            }

            let perp = abs(v.dx * dir.dy - v.dy * dir.dx)
            let angle = atan2(perp, along) * 180 / .pi

            guard angle <= coneAngleDeg else {
                continue
            }

            // On-axis wins over diagonal at equal distance
            let score = hypot(v.dx, v.dy) * (1 + angle / 45)
            if best == nil || score < best!.score {
                best = (score, index)
            }
        }

        return best?.index
    }
}
