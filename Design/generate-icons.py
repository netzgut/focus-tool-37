#!/usr/bin/env python3
#
#  generate-icons.py
#  FocusTool37
#
#  Copyright © 2026 Netzgut GmbH.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

"""Generates the app icon: an Icon Composer document with the viewfinder layers.

    python3 Design/generate-icons.py

Writes Resources/AppIcon.icon.

The frame is drawn on an 18-unit viewfinder grid: four corner brackets from
(2,2) to (16,16) with arms 4.5 long, the same proportions the menu bar glyph
(StatusGlyph in StatusItemController.swift) uses. The stroke is emitted as a
filled outline so the layer renders the same everywhere.

The layers are 1024-point canvases cropped from a 1024 design space whose
squircle spans 100…924, so they fill Icon Composer's canvas edge to edge.
Edit the document in Icon Composer afterwards if you like; rerunning this
script overwrites it.
"""

import json
import math
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Resources" / "AppIcon.icon"


# Geometry -------------------------------------------------------------------

def arc(cx, cy, r, a0, a1):
    """Cubic Bézier segments for a circular arc, angles in degrees, y down."""
    segments = max(1, math.ceil(abs(a1 - a0) / 90 - 1e-9))
    step = math.radians((a1 - a0) / segments)
    k = 4 / 3 * math.tan(step / 4)
    out = []
    t = math.radians(a0)
    for _ in range(segments):
        t2 = t + step
        p0 = (cx + r * math.cos(t), cy + r * math.sin(t))
        p3 = (cx + r * math.cos(t2), cy + r * math.sin(t2))
        c1 = (p0[0] - k * r * math.sin(t), p0[1] + k * r * math.cos(t))
        c2 = (p3[0] + k * r * math.sin(t2), p3[1] - k * r * math.cos(t2))
        out.append((c1, c2, p3))
        t = t2
    return out


class Outline:
    def __init__(self, transform):
        self.t = transform
        self.d = []

    def fmt(self, p):
        x, y = self.t(p)
        return f"{x:.3f} {y:.3f}"

    def move(self, p):
        self.d.append("M" + self.fmt(p))

    def line(self, p):
        self.d.append("L" + self.fmt(p))

    def arc(self, cx, cy, r, a0, a1):
        for c1, c2, p in arc(cx, cy, r, a0, a1):
            self.d.append("C" + " ".join(self.fmt(q) for q in (c1, c2, p)))

    def close(self):
        self.d.append("Z")

    def __str__(self):
        return "".join(self.d)


# The four corners as (corner point, first arm direction, second arm direction).
# All four share the top-left corner's orientation, so the outlines wind alike.
CORNERS = [((2, 2), (1, 0), (0, 1)), ((16, 2), (0, 1), (-1, 0)),
           ((16, 16), (-1, 0), (0, -1)), ((2, 16), (0, -1), (1, 0))]
ARM = 4.5


def frame_path(place, h):
    """Corner brackets with round caps and joins; h is half the stroke width in grid units."""
    path = Outline(place)
    for corner, d1, d2 in CORNERS:
        def local(p, corner=corner, d1=d1, d2=d2):
            u, v = p
            return (corner[0] + u * d1[0] + v * d2[0], corner[1] + u * d1[1] + v * d2[1])
        sub = Outline(lambda p, local=local: place(local(p)))
        sub.move((ARM, -h))
        sub.arc(ARM, 0, h, -90, 90)
        sub.line((h, h))
        sub.line((h, ARM))
        sub.arc(0, ARM, h, 0, 180)
        sub.line((-h, 0))
        sub.arc(0, 0, h, 180, 270)
        sub.close()
        path.d.extend(sub.d)
    return str(path)


# App icon --------------------------------------------------------------------

# Design space: 1024 square, squircle from 100 to 924. The frame spans 262…762
# with arms of 138, i.e. the symbol grid scaled by 500/14 around the center.
ICON_SCALE = 500 / 14
ICON_HALF = 27 / ICON_SCALE  # 54-unit stroke, in grid units

# The apps you move focus between: (x, y, radius, opacity, color).
BOKEH = [(250, 290, 62, .7, "#f2c38b"), (735, 295, 118, .58, "#9fd8e6"),
         (800, 770, 72, .65, "#f2c38b"), (320, 755, 138, .52, "#9fd8e6")]
BACKGROUND = "srgb:0.16471,0.41961,0.50196,1.00000"  # #2a6b80; Icon Composer derives the gradient


def icon_place(p):
    x, y = p
    return (512 + (x - 9) * ICON_SCALE, 512 + (y - 9) * ICON_SCALE)


def layer_svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="100 100 824 824">\n'
            f'{body}\n</svg>\n')


def write_icon():
    shutil.rmtree(ICON, ignore_errors=True)
    assets = ICON / "Assets"
    assets.mkdir(parents=True)

    (assets / "frame.svg").write_text(layer_svg(f'<path fill="#ffffff" d="{frame_path(icon_place, ICON_HALF)}"/>'))

    glyph = subprocess.run(["swift", str(Path(__file__).with_name("glyph-outline.swift")), "37", "250", "-6", "512", "512"],
                           check=True, capture_output=True, text=True).stdout.strip()
    (assets / "37.svg").write_text(layer_svg(f'<path fill="#ffffff" d="{glyph}"/>'))

    # The blur is baked into a PNG: layer SVGs don't carry filters into Icon Composer.
    discs = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}" opacity="{o}"/>' for x, y, r, o, c in BOKEH)
    bokeh_svg = layer_svg('<filter id="b" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="22"/></filter>'
                          f'<g filter="url(#b)">{discs}</g>')
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-o", str(assets / "bokeh.png")],
                   input=bokeh_svg, text=True, check=True)

    def group(layer, image, glass, shadow):
        return {"layers": [{"image-name": image, "name": layer, "glass": glass}],
                "shadow": {"kind": "neutral" if shadow else "none", "opacity": 0.5},
                "translucency": {"enabled": glass, "value": 0.3}}

    # Front to back.
    (ICON / "icon.json").write_text(json.dumps({
        "fill": {"automatic-gradient": BACKGROUND},
        "groups": [group("37", "37.svg", True, True),
                   group("frame", "frame.svg", True, True),
                   group("bokeh", "bokeh.png", False, False)],
        "supported-platforms": {"squares": "shared"},
    }, indent=2) + "\n")


if __name__ == "__main__":
    write_icon()
