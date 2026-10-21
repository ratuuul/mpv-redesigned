# Third-party notices

This repository redistributes a configuration for [mpv](https://mpv.io), which
means it also redistributes the skins, scripts, shaders and fonts that the
configuration loads. Those components are **not** covered by this project's MIT
licence. Each keeps its own.

Everything below was verified against the files actually shipped in `config/`,
not taken from memory. Where a licence could not be established from the
upstream project, the component was **left out** of the repository — those are
listed at the end.

## Not redistributed

| Component | Why |
|---|---|
| **mpv** | Not bundled. `install.ps1` installs it from scoop or the official [shinchiro Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake). mpv is GPL-2.0-or-later (LGPL-2.1-or-later for some builds); see <https://mpv.io>. |
| **yt-dlp** | Not bundled. `install.ps1` downloads `yt-dlp.exe` from the official [yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases). yt-dlp is Unlicense (public domain). |
| **ffmpeg** | Not bundled. Ships with mpv on Windows. |

## Skins

### uosc — Liquid Glass fork

- **Path:** `config/scripts/uosc/`
- **Upstream:** [tomasklaen/uosc](https://github.com/tomasklaen/uosc), pinned to
  **v5.9.2** (commit `8214fa9d5379c4c1c86e51a16baade95e10f39a5`). The pin is also
  recorded in `config/scripts/uosc/UPSTREAM.md`.
- **Licence:** **LGPL-2.1** — full text at
  `config/scripts/uosc/LICENSE.LGPL`, copy in [`licenses/LGPL-2.1.txt`](licenses/LGPL-2.1.txt).
- **Modifications made in this fork** (this is a modified version, not upstream):
  - new visual layer: `lib/liquid/` (`glass.lua`, `theme.lua`, `motion.lua`,
    `layout.lua`, `svg.lua`, `svg_loader.lua`, `icons.lua`) implements the
    six-layer glass primitive, the SVG icon pipeline and the spring motion.
  - new elements: `elements/Curtain.lua`, `elements/WindowBorder.lua`,
    `elements/BufferingIndicator.lua`, `elements/SkipPill.lua`,
    `elements/ManagedButton.lua`.
  - the control bar, timeline, volume, speed, top bar and pause indicator were
    reworked for the glass theme and the centred overlays.
  - minimum window size lowered to 760x320 (landscape) / 360x360 (portrait);
    the values are runtime options, see `script-opts/liquid-glass.conf`.
  - the speedometer tick sound is throttled and disabled by default
    (`liquid_glass_tick_sound=no`); it no longer spawns a PowerShell process per
    scroll event.
  - the skin announces itself via `user-data/skin/liquidglass` so that
    `nav_shim.lua` can detect which skin is active.
  - a "YouTube subtitles" entry was added to the main menu, shown only while a
    YouTube video is loaded.
  - the idle screen uses Geist Medium instead of a handwriting face.

  Because the LGPL requires that recipients can rebuild the modified library,
  the complete corresponding source of the fork is this repository. Nothing is
  distributed as a compiled library.

- **Bundled helper binary:** `config/scripts/uosc/bin/ziggy-windows.exe` — the
  OpenSubtitles download backend that uosc ships for Windows. It is part of the
  uosc distribution and is covered by the same LGPL-2.1 terms. Only the Windows
  build is shipped; the macOS and Linux builds present upstream are omitted
  because they cannot be used by a Windows-only configuration.

### ModernZ

- **Path:** `config/skins/modernz/` (parked alternative skin; `switch-skin`
  moves it to `config/scripts/modernz/` to activate it)
- **Upstream:** [Samillion/ModernZ](https://github.com/Samillion/ModernZ),
  **v0.3.3** per the file header.
- **Licence:** **LGPL-2.1**. The header of `main.lua` states:

  > This script is a derivative of the original mpv-osc-modern by maoiscat and
  > subsequent forks: cyl0/ModernX, dexeonify/ModernX. It is based on the
  > official osc.lua from mpv, licensed under the GNU Lesser General Public
  > License v2.1 (LGPLv2.1).

- Unmodified upstream copy; `modernz.lua` and `main.lua` are byte-identical
  duplicates kept for compatibility with both loading conventions.

## Scripts

| Script | Path | Upstream | Licence | Verified from |
|---|---|---|---|---|
| thumbfast | `config/scripts/thumbfast.lua` | [po5/thumbfast](https://github.com/po5/thumbfast) | **MPL-2.0** | header: "This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0" |
| quality-menu 4.2.1 | `config/scripts/quality-menu.lua` | [christoph-heinrich/mpv-quality-menu](https://github.com/christoph-heinrich/mpv-quality-menu) | **GPL-2.0** | upstream repository licence (the file header names the project but carries no licence block) |
| recentmenu | `config/scripts/recentmenu.lua` | [natural-harmonia-gropius/recent-menu](https://github.com/natural-harmonia-gropius/recent-menu) | **MIT** | upstream `LICENSE`, "Copyright (c) 2023 natural-harmonia-gropius" |
| mpv-webm | `config/scripts/webm.lua` | [ekisu/mpv-webm](https://github.com/ekisu/mpv-webm) | **MIT** | upstream repository licence |
| sponsorblock_minimal | `config/scripts/sponsorblock_minimal.lua` | [jouni/mpv_sponsorblock_minimal](https://codeberg.org/jouni/mpv_sponsorblock_minimal) | **GPL-3.0** | upstream `LICENSE` |

`sponsorblock_minimal` queries the public SponsorBlock API
(<https://sponsor.ajay.app>). The API and its database are operated by the
SponsorBlock project; the script only consumes the service at runtime and
ships none of its data.

### Scripts written for this project

These are original work and covered by this repository's MIT licence:

`config/scripts/nav_shim.lua`, `config/scripts/ytsubs.lua`,
`config/scripts/download.lua`, `config/scripts/pip.lua`,
`config/scripts/autosubs.lua`, `config/scripts/bg.lua`.

`autosubs.lua` calls the `ziggy` binary that ships with uosc for its optional
"single best match" mode. It contains no OpenSubtitles client of its own.

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
| `config/shaders/Anime4K_Clamp_Highlights.glsl` | **MIT** | (c) 2019-2021 bloc97 — [bloc97/Anime4K](https://github.com/bloc97/Anime4K) |
| `config/shaders/Anime4K_Restore_CNN_M.glsl` | **MIT** | (c) 2019-2021 bloc97 |
| `config/shaders/Anime4K_Restore_CNN_Soft_M.glsl` | **MIT** | (c) 2019-2021 bloc97 |
| `config/shaders/Anime4K_Upscale_CNN_x2_M.glsl` | **MIT** | (c) 2019-2021 bloc97 |
| `config/shaders/CfL_Prediction.glsl` | **MIT** | (c) 2023 João Cristóvão — [jgcn/CfL_Prediction](https://github.com/jgcn/CfL_Prediction) |

Each file carries the full MIT permission notice in its header, so the notice
travels with the shader.

## Fonts

All fonts live in `config/fonts/` and are loaded by mpv from that directory
only — nothing is installed system-wide.

| Font file | Licence | Copyright |
|---|---|---|
| `Geist-Regular.ttf`, `Geist-Medium.ttf`, `Geist-SemiBold.ttf`, `GeistMono-Regular.ttf` | **OFL-1.1** | Copyright 2024 The Geist Project Authors — [vercel/geist-font](https://github.com/vercel/geist-font) |
| `Inter-Medium.ttf`, `Inter-SemiBold.ttf` | **OFL-1.1** | Copyright (c) 2016 The Inter Project Authors — [rsms/inter](https://github.com/rsms/inter) |
| `SourceSans3-Regular.ttf`, `SourceSans3-Medium.ttf`, `SourceSans3-SemiBold.ttf` | **OFL-1.1** | Copyright 2010-2024 Adobe — [adobe-fonts/source-sans](https://github.com/adobe-fonts/source-sans) |
| `MaterialIconsRound-Regular.otf` | **Apache-2.0** | Google LLC — [google/material-design-icons](https://github.com/google/material-design-icons) |
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
| `scripts/uosc/assets/sounds/tick.wav` | Audio asset with no provenance information. The skin is silent without it and the feature is off by default, so nothing breaks. |
| `yt-dlp.exe` | Downloaded by the installer (see above); far too large to commit. |
| `mpv.log`, `recent.json`, `watch_later/`, `screenshots/`, `cache/`, `subtitles/` | Runtime state. `recent.json` in particular contains a personal playback history and local file paths. |
| `INSTALL.txt` | Superseded by this documentation and contained hardcoded personal paths. |

## Licence texts

Full texts of every licence referenced above:

```
licenses/
  Apache-2.0.txt    Material Icons Round
  GPL-2.0.txt       quality-menu
  GPL-3.0.txt       sponsorblock_minimal
  LGPL-2.1.txt      uosc fork, ModernZ, modernz-icons.ttf, ziggy
  MPL-2.0.txt       thumbfast
  OFL-1.1.txt       Geist, Inter, Source Sans 3
```

The MIT text that covers the shaders is reproduced in each shader file.
