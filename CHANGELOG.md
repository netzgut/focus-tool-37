# Changelog

All notable changes to Focus Tool 37 are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-11-07

### Added

- _Show in menu bar_ setting under _Settings > General_ to hide the menu bar icon.
  Opening the app again while it's running shows the settings window.
  ⌘-dragging the icon out of the menu bar turns the setting off as well.
  The icon stays visible while Accessibility access is missing, since its menu leads to the right System Settings pane.

- _Quit Focus Tool 37_ button in the bottom-right corner of the _General_ settings pane, so the app can be quit without the menu bar icon.

### Fixed

- Settings and welcome windows could open behind the frontmost app when macOS declined to activate Focus Tool 37 ([#1](https://github.com/netzgut/focus-tool-37/issues/1)).

## [0.1.0] - 2026-10-28

Initial release.

[0.1.1]: https://github.com/netzgut/focus-tool-37/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/netzgut/focus-tool-37/releases/tag/v0.1.0
