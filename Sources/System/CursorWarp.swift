//
//  CursorWarp.swift
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

@MainActor
enum CursorWarp {

    /// Global top-left coordinates, like everything else in this app
    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)

        // A warp briefly detaches the cursor from the physical mouse.
        // Re-associate so the next real movement isn't swallowed.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Current cursor position in global top-left coordinates.
    /// (Deliberately not NSEvent.mouseLocation, which is bottom-left.)
    static var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
