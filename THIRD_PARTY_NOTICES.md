# Third-party notices

This repository redistributes a configuration for [mpv](https://mpv.io), which
means it also redistributes the skins, scripts, shaders and fonts that the
configuration loads. Those components are **not** covered by this project's MIT
licence. Each keeps its own.

Every licence below was checked against a file that actually ships in this
repository, or against the upstream project's own licence file at the pinned
commit. The "Verified from" column names the exact evidence. Where a licence
could **not** be verified, the component was excluded from this repository and
is listed under [Excluded](#excluded-from-this-repository) with the reason.

## Not redistributed

| Component | Why |
|---|---|
| **mpv** | Not bundled. `install.ps1` installs it from scoop or the official [shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake). mpv is GPL-2.0-or-later (LGPL-2.1-or-later for some builds); see <https://mpv.io>. |
| **yt-dlp** | Not bundled. `install.ps1` downloads `yt-dlp.exe` from the official [yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases). yt-dlp is Unlicense (public domain). |
| **ffmpeg** | Not bundled. Ships with mpv on Windows. |

## Skins

### uosc - Liquid Glass fork

- **Path:** `config/scripts/uosc/`
- **Upstream:** [tomasklaen/uosc](https://github.com/tomasklaen/uosc), pinned to
  **v5.9.2** (commit `8214fa9d5379c4c1c86e51a16baade95e10f39a5`). The pin is
  also recorded in `config/scripts/uosc/UPSTREAM.md`.
- **Licence:** **LGPL-2.1**. Verified from the licence file the skin itself
  ships, `config/scripts/uosc/LICENSE.LGPL` (verbatim GNU Lesser General
  Public License, Version 2.1, February 1999), and confirmed by the upstream
  repository's `LICENSE.LGPL`. Full text also at
  [`licenses/LGPL-2.1.txt`](licenses/LGPL-2.1.txt).

#### What this fork changes

Verified by diffing the shipped tree against upstream v5.9.2 (commit
`8214fa9d`): 25 of the 49 upstream Lua files are byte-identical, 8 are
modified and 16 are new.

| Upstream file | State here |
|---|---|
| `main.lua` | modified |
| `elements/Controls.lua` | modified (the whole control bar was rebuilt) |
| `elements/Menu.lua` | modified |
| `elements/Timeline.lua` | modified |
| `elements/TopBar.lua` | modified |
| `elements/Volume.lua` | modified |
| `lib/menus.lua` | modified |
| `lib/utils.lua` | modified (idle screen) |
| `elements/BufferingIndicator.lua`, `elements/Button.lua`, `elements/Curtain.lua`, `elements/CycleButton.lua`, `elements/Element.lua`, `elements/Elements.lua`, `elements/ManagedButton.lua`, `elements/PauseIndicator.lua`, `elements/Speed.lua`, `elements/Updater.lua`, `elements/WindowBorder.lua`, `lib/ass.lua`, `lib/buttons.lua`, `lib/char_conv.lua`, `lib/cursor.lua`, `lib/intl.lua`, `lib/std.lua`, `lib/text.lua`, `char-conv/zh.json`, `intl/*.json` | unchanged (byte-identical to upstream) |

New files added by the fork:

| New file | What it is |
|---|---|
| `lib/liquid/glass.lua` | the six-layer glass primitive (blur, tint, border, sheen, shadow) |
| `lib/liquid/theme.lua` | colours, radii and opacity tokens |
| `lib/liquid/layout.lua` | geometry of the control bar, timeline and overlays |
| `lib/liquid/motion.lua` | the spring motion used by the controls |
| `lib/liquid/svg.lua` | SVG to ASS converter for the icon pipeline |
| `lib/liquid/svg_loader.lua` | loads `assets/icons/*.svg` into the icon registry |
| `lib/liquid/icons.lua` | the icon registry and its inline fallback paths |
| `lib/chapters.lua` | chapter list helpers |
| `elements/SkipPill.lua` | the "skipped segment" pill |
| `assets/icons/*.svg` | the fork's own icon artwork (see below) |
| `assets/frost-noise.png` | a generated noise texture, used by the frosted-glass layer |
| `assets/sounds/README.md` | how to drop in an optional `tick.wav` |
| `bin/ziggy-windows.exe` | the OpenSubtitles helper (see below) |

Because the LGPL requires that recipients can rebuild the modified library, the
complete corresponding source of the fork is this repository. Nothing is
distributed as a compiled library.

- **Bundled helper binary:** `config/scripts/uosc/bin/ziggy-windows.exe` is the
  OpenSubtitles download backend that uosc ships for Windows. It is built from
  the `src/ziggy` Go sources in the upstream repository, is unmodified here,
  and inherits the upstream LGPL-2.1 terms. The corresponding source is
  available at the pinned commit
  (`src/ziggy/` in [tomasklaen/uosc](https://github.com/tomasklaen/uosc) at
  `8214fa9d5379c4c1c86e51a16baade95e10f39a5`). Only the Windows build is
  shipped; the macOS and Linux builds present upstream are omitted because
  they cannot be used by a Windows-only configuration.

- **Icon artwork:** `config/scripts/uosc/assets/icons/` contains 13 SVG files
  authored for this fork. They are covered by the fork's LGPL-2.1 terms. The
  skin also carries an inline fallback path for every icon in
  `lib/liquid/icons.lua`, so the interface still renders correctly if the
  asset folder is missing.

### ModernZ

- **Path:** `config/skins/modernz/` (parked alternative skin; `switch-skin`
  moves it to `config/scripts/modernz/` to activate it)
- **Upstream:** [Samillion/ModernZ](https://github.com/Samillion/ModernZ),
  **v0.3.3** per the file header.
- **Licence:** **LGPL-2.1**. Verified from the header of `main.lua`:

  > This script is a derivative of the original mpv-osc-modern by maoiscat and
  > subsequent forks: cyl0/ModernX, dexeonify/ModernX. It is based on the
  > official osc.lua from mpv, licensed under the GNU Lesser General Public
  > License v2.1 (LGPLv2.1).

  and confirmed by the upstream repository's `LICENSE` file.

- Unmodified upstream copy: `config/skins/modernz/main.lua` is byte-identical
  (SHA-256 `6F622F138931A0B3B019FD17FB7D85FEBF0D0B733948A814AB54EC1C40ED2268`)
  to upstream `modernz.lua` at `main`. `modernz.lua` in the same folder is a
  byte-identical duplicate kept for compatibility with both loading
  conventions. `modernz-icons.ttf` is the icon font that ships with ModernZ.

## Scripts

| Script | Path | Upstream | Licence | Verified from |
|---|---|---|---|---|
| thumbfast | `config/scripts/thumbfast.lua` | [po5/thumbfast](https://github.com/po5/thumbfast) | **MPL-2.0** | the file's own header: "This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0" |
| quality-menu 4.2.1 | `config/scripts/quality-menu.lua` | [christoph-heinrich/mpv-quality-menu](https://github.com/christoph-heinrich/mpv-quality-menu) | **GPL-2.0** | upstream `LICENSE.md` (verbatim GNU General Public License, Version 2) at `master` |
| recentmenu | `config/scripts/recentmenu.lua` | [natural-harmonia-gropius/recent-menu](https://github.com/natural-harmonia-gropius/recent-menu) | **MIT** | upstream `LICENSE` at `master`: "MIT License, Copyright (c) 2023 natural-harmonia-gropius" |
| mpv-webm | `config/scripts/webm.lua` | [ekisu/mpv-webm](https://github.com/ekisu/mpv-webm) | **MIT** | upstream `LICENSE` at `master`: "MIT License, Copyright (c) 2020 ekisu" |
| sponsorblock_minimal | `config/scripts/sponsorblock_minimal.lua` | [jouni/mpv_sponsorblock_minimal](https://codeberg.org/jouni/mpv_sponsorblock_minimal) | **GPL-3.0** | upstream `LICENSE` at `master` (verbatim GNU General Public License, Version 3) |

The first four files carry no licence header of their own, so the upstream
licence file at the pinned branch was read directly for each one.

`sponsorblock_minimal` is a modified copy: the hash check for the SponsorBlock
API, the SHA-256 availability probe and the changed-section skipping were
added for this project. The licence is unchanged.

`sponsorblock_minimal` queries the public SponsorBlock API
(<https://sponsor.ajay.app>). The API and its database are operated by the
SponsorBlock project; the script only consumes the service at runtime and
ships none of its data.

### Scripts written for this project

These are original work, covered by this repository's MIT licence
([`licenses/MIT.txt`](licenses/MIT.txt)):

`config/scripts/nav_shim.lua`, `config/scripts/ytsubs.lua`,
`config/scripts/download.lua`, `config/scripts/pip.lua`,
`config/scripts/autosubs.lua`, `config/scripts/bg.lua`.

`autosubs.lua` calls the `ziggy` binary that ships with uosc for its optional
"single best match" mode. It contains no OpenSubtitles client of its own.

`bg.lua` downloads its idle-screen photos at runtime from loremflickr, picsum
and unsplash. No image is bundled, so no image licence applies to this
repository.

### About the GPL mix

This repository is an aggregate: MIT (original work), LGPL-2.1 (uosc, ModernZ),
GPL-2.0 (quality-menu), GPL-3.0 (sponsorblock_minimal), MPL-2.0 (thumbfast).
The copyleft scripts are separate programs that mpv loads at runtime; they are
not linked into a single work and none of them is relicensed here. If you
redistribute a *modified* copy of one of them, that copy stays under its own
licence.

## Shaders

| File | Licence | Copyright |
|---|---|---|
| `config/shaders/Anime4K_Clamp_Highlights.glsl` | **MIT** | (c) 2019-2021 bloc97 - [bloc97/Anime4K](https://github.com/bloc97/Anime4K) |
| `config/shaders/Anime4K_Restore_CNN_M.glsl` | **MIT** | (c) 2019-2021 bloc97 |
| `config/shaders/Anime4K_Restore_CNN_Soft_M.glsl` | **MIT** | (c) 2019-2021 bloc97 |
| `config/shaders/Anime4K_Upscale_CNN_x2_M.glsl` | **MIT** | (c) 2019-2021 bloc97 |
| `config/shaders/CfL_Prediction.glsl` | **MIT** | (c) 2023 Joao Cristovao - [jgcn/CfL_Prediction](https://github.com/jgcn/CfL_Prediction) |

Each file carries the full MIT permission notice in its header, so the notice
travels with the shader. Full text also at
[`licenses/MIT.txt`](licenses/MIT.txt).

## Fonts

All fonts live in `config/fonts/` and are loaded by mpv from that directory
only - nothing is installed system-wide.

| Font file | Licence | Copyright |
|---|---|---|
| `Geist-Regular.ttf`, `Geist-Medium.ttf`, `Geist-SemiBold.ttf`, `GeistMono-Regular.ttf` | **OFL-1.1** | Copyright 2024 The Geist Project Authors - [vercel/geist-font](https://github.com/vercel/geist-font) |
| `Inter-Medium.ttf`, `Inter-SemiBold.ttf` | **OFL-1.1** | Copyright (c) 2016 The Inter Project Authors - [rsms/inter](https://github.com/rsms/inter) |
| `SourceSans3-Regular.ttf`, `SourceSans3-Medium.ttf`, `SourceSans3-SemiBold.ttf` | **OFL-1.1** | Copyright 2010-2024 Adobe - [adobe-fonts/source-sans](https://github.com/adobe-fonts/source-sans) |
| `MaterialIconsRound-Regular.otf` | **Apache-2.0** | Google LLC - [google/material-design-icons](https://github.com/google/material-design-icons) |
| `modernz-icons.ttf` | **LGPL-2.1** | Bundled with ModernZ (Samillion/ModernZ) as part of that work |

The OFL-1.1 text is in [`licenses/OFL-1.1.txt`](licenses/OFL-1.1.txt) and the
Apache-2.0 text in [`licenses/Apache-2.0.txt`](licenses/Apache-2.0.txt).

Upstream ships an OFL copy as `fonts/LICENSE-Geist.txt`. It is deliberately
**not** included in `config/fonts/`: libass opens every file in that directory
as a font and logs `Error opening memory font 'LICENSE-Geist.txt'` on every
file load. `config/fonts/` therefore contains only font files.

`MaterialIconsRound-Regular.otf` is distributed unmodified, in object form, and
is not embedded into any other product.

## Excluded from this repository

| Item | Reason |
|---|---|
| `Spell of Asia.ttf` | No licence file, no upstream project, and no provenance information was available for the copy on disk. Cannot be redistributed safely. |
| 17 icon SVGs from SVG Repo | The files carried the marker `Uploaded to: SVG Repo, www.svgrepo.com`. The site's licence terms could not be read (the site now answers every request with a bot challenge), and each icon on that site can carry its own separate licence, so no single licence could be established for them. They were removed. The skin renders those icons from the inline fallback paths in `lib/liquid/icons.lua`, so nothing is lost visually. |
| `scripts/uosc/assets/sounds/tick.wav` | Audio asset with no provenance information. The skin is silent without it and the feature is off by default, so nothing breaks. |
| `yt-dlp.exe` | Downloaded by the installer (see above); far too large to commit. |
| `mpv.log`, `recent.json`, `watch_later/`, `screenshots/`, `cache/`, `subtitles/` | Runtime state. `recent.json` in particular contains a personal playback history and local file paths. The installer no longer copies these into the target directory. |
| `INSTALL.txt` | Superseded by this documentation and contained hardcoded personal paths. |

## Licence texts

Full texts of every licence referenced above:

```
licenses/
  Apache-2.0.txt    Material Icons Round
  GPL-2.0.txt       quality-menu
  GPL-3.0.txt       sponsorblock_minimal
  LGPL-2.1.txt      uosc fork, ModernZ, modernz-icons.ttf, ziggy
  MIT.txt           this project's original work, recentmenu, mpv-webm, the shaders
  MPL-2.0.txt       thumbfast
  OFL-1.1.txt       Geist, Inter, Source Sans 3
```

Each text was checked against the canonical wording of the licence it names.
