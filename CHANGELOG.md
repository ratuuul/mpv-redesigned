# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version refers to the **configuration package**, not to mpv itself. The
configuration targets mpv 0.37 and newer and is tested against mpv 0.41.

## [Unreleased]

Nothing yet.

## [1.0.0] - 2026-10-21

The first public release. Everything in this list ships in the initial tag.

### Added

- **Liquid Glass skin** - a fork of uosc v5.9.2 with a glass visual layer:
  translucent panels, a hairline accent, centred seek and volume overlays and
  an icon set that is drawn from inline SVG paths.
- **ModernZ skin**, parked and switchable, for the people who prefer a
  full-featured OSC with chapter list, playlist and device menus.
- **Idle photo background** (`scripts/bg.lua`) - a random photograph fills the
  window while mpv has nothing to play, with a welcome overlay typeset in
  Geist SemiBold and Inter Medium.
- **Reopen the last media with a double-click** (`scripts/lasthit.lua`) - the
  last real media that was played is reloaded and resumes at the exact
  position it was left at.
- **YouTube integration** - `ytdl_hook` for playback, a real format picker
  (`F`), a subtitle picker listing every language YouTube offers (`Alt+s`), and
  an automatic subtitle lookup for local files.
- **SponsorBlock** with the full category set and a toggle on `b`.
- **Seek bar thumbnails** (`scripts/thumbfast.lua`) - a second headless mpv
  decodes the preview frames into a pipe.
- **Clip cutter** (`scripts/webm.lua`) - mark in, mark out, encode to WebM.
- **Picture-in-picture mini player** - a borderless always-on-top window
  anchored to the corner of the work area.
- **Downloader** (`scripts/download.lua`) - saves the current stream with
  yt-dlp, asynchronously, without ever overwriting an existing file.
- **Recent files menu** with series and episode awareness.
- **One key map for both skins** (`scripts/nav_shim.lua`) - navigation is
  routed through a shim so the same bindings work with either skin.
- **Profiles** - `fast`, `max-quality`, `cine`, `shaders-anime`,
  `shaders-anime-full`, `shaders-off`, `subs-panel`, `subs-cinema`,
  `loudnorm`, `dynaudnorm`, `gpu-vulkan`, `gpu-d3d11` and `windowed-full`,
  plus two conditional Anime4K profiles.
- **Anime4K and CfL shaders** for line-art restoration and chroma from luma.
- **One-command installers** for Windows (PowerShell) and Linux/macOS (shell),
  both with a dry run, a timestamped backup and an uninstall path.
- **A public documentation set** and a static GitHub Pages site.

### Changed

- The control bar and the timeline follow the mouse instead of staying on
  screen permanently.
- The top bar of the skin - the title, the close button and the maximise
  button - is switched off.
- The volume slider and the mute button got a Liquid Glass hover treatment: a
  soft accent halo behind the track and the skin's icon glow on the button.
- The welcome overlay lost its blurred black vignette and its drop shadow, and
  uses a hairline outline instead so the type stays sharp over a photograph.
- `resume-playback-check-mtime` is off, so a saved position survives for remote
  streams that have no modification time.
- `write-filename-in-watch-later-config` is on, so a watch-later entry can be
  mapped back to the media it belongs to.

### Removed

- The cat and the "Gimme a link will ya" prompt that used to flash on the idle
  screen before the photograph arrived.
- The `cookies-from-browser=firefox` option. It depends on a Firefox profile
  that exists on one machine, and a missing profile takes every YouTube URL
  down with it. The option is documented in `config/mpv.conf` and can be
  switched back on.
- The `loremflickr` and `unsplash` photo sources. Both answer with errors
  today; the script still understands them.

### Security

- The published configuration contains no absolute path, no token and no
  runtime state. A CI job scans every tracked file and fails the build on any
  of them.

[Unreleased]: https://github.com/ratuuul/mpv-redesigned/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ratuuul/mpv-redesigned/releases/tag/v1.0.0
