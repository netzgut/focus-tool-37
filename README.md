# Focus Tool 37

A macOS tool for moving application focus with directional keyboard shortcuts, bringing the mouse cursor along.

Press <kbd>⌥⌘L</kbd> and focus jumps to the nearest window to the right, across every window on the current Space, on every display.
The mouse pointer lands in the middle of it, so switching to the mouse doesn't require following the focus by hand.

_Focus Tool 37_ is a menu-bar agent: no Dock icon and no app switcher entry, except while its settings window is open.

## Requirements

- macOS 14 or later
- Granting _Accessibility permission_ is mandatory.\
  _Focus Tool 37_ reads other apps' window geometry and raises windows, and macOS gates both behind it.

## How it works

On first launch a welcome window explains why Accessibility is needed, and its **Open System Settings...** button opens the right pane.
If you close it, the menu bar item and the settings window will offer the same shortcut.

The tool starts working the moment the grant lands, no relaunch required.

The grant is tied to the app's code signature, so keep a stable signing identity or macOS will ask again after every rebuild.

## Install

```sh
open FocusTool37.xcodeproj      # set your signing team, then Run
```

If there is an issue with the Accessibility permission, you can easily reset it:

```sh
tccutil reset Accessibility net.netzgut.focustool37
```

## Shortcuts

| Action                           | Vim keys               | Arrow keys             |
| -------------------------------- | ---------------------- | ---------------------- |
| Focus left / down / up / right   | <kbd>⌥⌘</kbd> H J K L  | <kbd>⌥⌘</kbd> ← ↓ ↑ →  |
| Same-app only _(off by default)_ | <kbd>⌥⌘⇧</kbd> H J K L | <kbd>⌥⌘⇧</kbd> ← ↓ ↑ → |

Both presets are on by default and work at the same time.

Bindings are _physical key positions_, not the actual characters.
So <kbd>⌥⌘</kbd>HJKL sits under the same fingers on any layout.

_Same-app navigation_ restricts the focus targets to the frontmost app's windows.
It's off by default so the eight <kbd>⌥⌘⇧</kbd> bindings stay available to other apps.

Recording a custom shortcut in Preferences adds to the activated presets.
Focus Tool 37 warns before saving a combo that collides with a system shortcut, and reports inline if another running app already owns one.

## Focus outline

The outline traces the newly focused window's frame with a colored border.
The setting **Match window corners** is on (the default), which means Focus Tool 37 tries to follow the corner radius of the target window's border, since macOS has no API that reports it:

| Window                  | Radius                  |
| ----------------------- | ----------------------- |
| Toolbar                 | 26 pt                   |
| Compact toolbar         | 20 pt                   |
| Title bar only          | 16 pt                   |
| Full screen             | 0 pt                    |
| Dialogs, panels, etc.   | the corner radius set   |

Turn it off and every window gets the corner radius set in Feedback.

## How the target window is chosen

The target is calculated by pure geometry over the visible windows, in three passes:

1. **Overlapping windows** whose centre lies beyond the source's centre in the direction of travel.
   The nearest centre wins, so repeated presses walk through a stack window by window.
   Ranking is spatial, never by stacking order, otherwise a full-screen window in the background would shadow everything on top of it.

2. **The edge band**:
   Windows strictly beyond the source's edge whose perpendicular extent overlaps it.
   Smallest gap wins.

3. **A ±45° cone**: A fallback, when nothing lies squarely in that direction.

Windows hidden behind others are deliberately valid targets.
There is no occlusion model, and directional navigation doubles as a window switcher.
A dead end is a silent no-op: no wrap-around, matching how tiling window managers behave at a screen edge.
Because candidates span every display, moving right simply continues onto the next monitor when the current one runs out.

Two settings can tune the behavior:

* **Edge slop**: How much overlap still counts as a clean neighbour (default: 8 pt)
* **Cone angle**: The fallback search cone (default: 45°)

## Accessibility

Focus Tool 37 moves keyboard focus for a living, so it tries not to be unusable with assistive tech.
Every control in Preferences is labelled for VoiceOver.
Sliders and shortcut slots speak their values in words.
The decorative overlays are excluded from the accessibility tree, and a keyboard-driven focus move is announced with the app and window title.

## Languages

English and German.
Translation PRs are welcome.

## Project layout

```text
Sources/
  App/          lifecycle and state
  Focus/        the feature itself: scoring, enumeration, hotkeys
  Feedback/     outline, cursor pulse, VoiceOver announcements
  Interface/    menu bar and settings window
  System/       thin wrappers over macOS APIs
Tests/          scoring, hotkey-planning and key-label tests, no window server required
```

```sh
xcodebuild -project FocusTool37.xcodeproj -scheme FocusTool37 test
```

The scoring logic is pure geometry over plain rectangles, so it's unit-tested against synthetic window layouts without a running window server. Hotkey planning (which combo triggers which action) is pure as well and tested the same way.

## AI Disclosure

This project was built with the help of Claude.
I've developed quite a few different iOS apps, starting in Swift-less times, but I had no prior experience with developing AppKit apps.
That's why AI can bridge the gap to get the project up and running and help with implementing the details, creating a learning experience.
It's a tool, and should be used as such, not as a replacement for the full process.

## License

Copyright © 2026 Netzgut GmbH.

Licensed under the [Apache License, Version 2.0](LICENSE).
See [`NOTICE`](NOTICE) for attribution.
