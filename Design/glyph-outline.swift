//
//  glyph-outline.swift
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

// Prints SVG path data for a string set in SF Pro Rounded Heavy, with its
// optical bounding box centered on (cx, cy). Used by generate-icons.py so the
// icon's "37" ships as outlines and doesn't depend on installed fonts.
//
//   swift glyph-outline.swift <text> <size> <tracking> <cx> <cy>

import AppKit

let args = CommandLine.arguments
let text = args[1]
let size = CGFloat(Double(args[2])!)
let tracking = CGFloat(Double(args[3])!)
let cx = CGFloat(Double(args[4])!), cy = CGFloat(Double(args[5])!)

var font = NSFont.systemFont(ofSize: size, weight: .heavy)
if let rounded = font.fontDescriptor.withDesign(.rounded) {
    font = NSFont(descriptor: rounded, size: size)!
}

let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: tracking])
let line = CTLineCreateWithAttributedString(attributed)
let path = CGMutablePath()
for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
    // NSFont and CTFont are toll-free bridged; a run without one keeps the base font.
    let runFont = ((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as? NSFont ?? font) as CTFont
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    for (glyph, position) in zip(glyphs, positions) {
        guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
        path.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y))
    }
}

// Flip to SVG's y-down space and center the ink box.
let box = path.boundingBoxOfPath
let toSVG = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: cx - box.midX, ty: cy + box.midY)
let svgPath = path.copy(using: [toSVG])!

func f(_ p: CGPoint) -> String {
    String(format: "%.2f %.2f", p.x, p.y)
}

var d = ""
svgPath.applyWithBlock { element in
    let e = element.pointee
    switch e.type {
    case .moveToPoint: d += "M\(f(e.points[0]))"
    case .addLineToPoint: d += "L\(f(e.points[0]))"
    case .addQuadCurveToPoint: d += "Q\(f(e.points[0])) \(f(e.points[1]))"
    case .addCurveToPoint: d += "C\(f(e.points[0])) \(f(e.points[1])) \(f(e.points[2]))"
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}

print(d)
