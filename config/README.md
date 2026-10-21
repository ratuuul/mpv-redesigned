# mpv configuration

Tuned for **Windows 10 IoT Enterprise LTSC**, **Intel(R) Graphics (iGPU)**,
panel **1920x1200 @ 60 Hz**, mpv **v0.41.0-dev** / libplacebo **v7.358.0**.

Everything here was verified against the actual build on this machine
(option names checked against `mpv --list-options`, rendering measured with
frame-drop counters and PSNR comparisons).

---

## Layout

```
%APPDATA%\mpv\
  mpv.conf              master file, includes everything below
  input.conf            key bindings
  conf\
    video.conf          renderer, hardware decode, scaling, colour
    audio.conf          WASAPI output, volume, ReplayGain, track selection
    subtitles.conf      font, colours, borders, margins
    interface.conf      window chrome, OSD, screenshots
    profiles.conf       conditional + on-demand profiles
  scripts\
    uosc\             Liquid Glass OSC (uosc fork) - ACTIVE
    nav_shim.lua      skin-aware navigation (seek / volume / speed / scroll)
    ytsubs.lua        YouTube subtitle picker
    thumbfast.lua     seekbar thumbnail previews
    quality-menu.lua  real YouTube/DASH format picker
    sponsorblock_minimal.lua
    recentmenu.lua    recent-files menu
    webm.lua          clip cutter
  script-opts\        per-script options
  skins\
    modernz\          ModernZ OSC (parked - becomes scripts\modernz when active)
  fonts\                Geist, Inter, Source Sans 3, Noto/ModernZ icons
  shaders\              Anime4K Restore + CfL
  yt-dlp.exe            YouTube / streaming support
  switch-skin.cmd       swap between the two skins
  mpv.log               last run log
```

Nothing in this directory hardcodes a machine path. Every path is either
relative or starts with `~~/`, which mpv expands to this config directory, so
the whole tree can be moved or copied to another machine unchanged.

---

## Skin

Two skins are installed. Exactly one is active at a time.

| | Liquid Glass (default) | ModernZ |
|---|---|---|
| Upstream | uosc v5.9.2 fork | Samillion/ModernZ (LGPL-2.1, actively maintained) |
| Look | macOS-style glass, centred overlays, speedometer | glassmorphic blur, hairline accent seekbar, chapter nibbles |
| Menus | uosc menus | full (playlist/subtitles/chapters/audio/devices) |

Switch with:

```
switch-skin.cmd            # interactive
switch-skin.cmd liquidglass
switch-skin.cmd modernz
```

> **Why the switcher moves folders instead of just pointing at another file:**
> mpv only puts a script's own directory on the Lua module path when the
> script lives in `scripts/`. The Liquid Glass skin needs
> `require('lib/std')` and friends, so if it sits anywhere else it **crashes
> on load with "module 'lib/std' not found"** and the player ends up with
> no controls at all. The active skin therefore lives in `scripts/` and the
> inactive one is parked in `skins/`.

Restart mpv afterwards. `scripts/nav_shim.lua` detects the active skin at
runtime, so the **same key bindings work with either** - with Liquid Glass
you get its centred macOS-style seek/volume overlays, with ModernZ you get
its own feedback.

### Controls are always visible

uosc normally hides the control bar and the progress bar until the mouse
comes near them. `script-opts/uosc.conf` turns that off:

```ini
controls_persistency=video
timeline_persistency=video
```

Remove those lines to go back to show-on-hover. The top bar, volume and
speed indicators stay hover-only.

### Liquid Glass fixes applied

- window minimum lowered from 1240x420 to 760x320 (the old floor made
  side-by-side work impossible)
- the speedometer tick no longer spawns a PowerShell subprocess on every
  scroll event (re-enable with `liquid_glass_tick_sound=yes`)
- idle screen font changed from the handwriting face to Geist Medium
- it now announces itself so the nav shim can talk to it
- a "YouTube subtitles" entry was added to its main menu, shown only while a
  YouTube video is loaded

---

## YouTube

`yt-dlp.exe` lives in the config directory, so mpv's `ytdl_hook` finds it
first. Streaming, format switching and downloads all work out of the box.

### Subtitles

Two independent mechanisms:

**1. Automatic - creator-uploaded subtitles.**
`ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*`
asks yt-dlp for the subtitles the uploader provided. mpv's `ytdl_hook` turns
each one into a normal subtitle track immediately, so they are already in
the track list when the video starts. Cycle them with `v`, or pick from the
skin's **Subtitles** menu.

> Watch out when editing this option: mpv parses `ytdl-raw-options` as a
> key/value list and **every entry needs a `=value`**. A bare key swallows
> the next entry and breaks the yt-dlp command line completely (the video
> then never loads). Keep it to a single entry, and never use a comma
> inside the value - use `|` for alternation.

**2. On demand - the full picker.**
`Alt+s` opens a menu with **every** subtitle YouTube offers for the video:
the creator-uploaded ones plus the auto-generated captions, in all
languages. `Alt+Shift+s` loads the pick as the *secondary* subtitle (shown
at the top of the screen) instead of the main one.

`scripts/ytsubs.lua` builds the list from the yt-dlp metadata, downloads
the chosen track into `cache\ytsubs\` and hands it to mpv with `sub-add`, so
it appears in the track list and in every subtitle menu. Files are cached,
so re-picking is instant.

> **Known limitation:** YouTube rate-limits the timedtext endpoint hard
> (HTTP 429) for *auto-translated* captions. The creator-uploaded subtitles
> and the original-language captions work reliably; a machine-translated one
> may be refused, in which case the script retries twice and then says so.
> The menu marks those entries as "translated".

| Key | Action |
|---|---|
| `Alt+s` | YouTube subtitle menu |
| `Alt+Shift+s` | same, but as the secondary (top) subtitle |
| `F` / `Alt+f` | video / audio format menu (real formats, not presets) |
| `b` | toggle SponsorBlock skipping |
| `W` | cut a clip to WebM |

---

## Key bindings

Navigation goes through `nav_shim` so it works with both skins.

| Key | Action |
|---|---|
| `Left` / `Right` | seek -5 / +5 s |
| `Shift+Left/Right` | seek -1 / +1 s (frame exact) |
| `Ctrl+Left/Right` | seek -10 / +10 s |
| `Up` / `Down` | volume +/- 5 |
| `Wheel` | seek (timeline), not volume |
| `0`-`9`, `KP0`-`KP9` | jump to 0%, 10% ... 90% |
| `{` / `}` / `Backspace` | speed up / down / reset |
| `Space`, `MBTN_RIGHT` | pause |
| `s` / `S` / `Ctrl+s` | screenshot (with / without subtitles) |
| `a` / `Alt+a` | cycle audio track |
| `v` / `Shift+v` / `Alt+v` | cycle subtitles / down / toggle visibility |
| `z` / `Z` / `Ctrl+z` | subtitle delay |
| `F` / `Alt+f` | YouTube video / audio format menu |
| `Alt+s` | YouTube subtitle menu (every language) |
| `Alt+Shift+s` | load a YouTube subtitle as the secondary (top) one |
| `b` | toggle SponsorBlock (claimed by the script) |
| `W` | cut a clip to WebM (claimed by the script) |
| `Ctrl+Shift+R` | recent files menu |
| `Shift+MBTN_RIGHT` | native mpv context menu |
| `g-h` `g-w` `g-b` `g-m` | mpv's built-in history / watch-later / bindings / main menu |
| `Alt+1` ... `Alt+0` | profiles (see below) |

---

## Profiles

Apply with `Alt+<n>` or `apply-profile <name>`.

| Key | Profile | What it does |
|---|---|---|
| `Alt+1` | `fast` | bilinear, no interpolation, no debanding |
| `Alt+2` | `max-quality` | ewa_lanczos4sharpest, 4 deband iterations |
| `Alt+3` | `cine` | spline36, no interpolation, light deband |
| `Alt+4` | `shaders-anime` | Anime4K Restore (M) + chroma-from-luma |
| `Alt+5` | `shaders-off` | remove all user shaders |
| `Alt+6` | `subs-panel` | Netflix-style translucent subtitle panel |
| `Alt+7` | `subs-cinema` | shadow-only subtitles, lower on screen |
| `Alt+8` | `loudnorm` | EBU R128 normalisation |
| `Alt+9` | `dynaudnorm` | gentler dynamic normalisation |
| `Alt+0` | `gpu-vulkan` | switch the renderer to Vulkan (A/B) |

Conditional profiles apply automatically:

- `anime-restore` - any file whose path contains "anime" gets Anime4K
  line-art restoration + chroma-from-luma
- `anime-restore-soft` - same, softer variant for <=720p sources

---

## What was measured on this machine

Everything below was benchmarked here, not assumed:

- **d3d11va vs Vulkan decoding** - both decode 1080p and 4K with 0 dropped
  frames, and the rendered output is pixel-identical (PSNR 66.5 dB). d3d11
  was chosen because it is Intel's best-supported Windows path and it is the
  only one where `d3d11va-zero-copy` applies. `gpu-vulkan` is one keypress
  away if you want to compare.
- **Scalers** - spline36, ewa_lanczossharp and ewa_lanczos4sharpest all run
  with 0 dropped frames at 1920x1200, even combined with interpolation and
  debanding. The iGPU has enough headroom for the full-quality stack.
- **Interpolation** - `video-sync=display-resample` + `interpolation=yes`
  removes the 24p->60 Hz judder, which is very visible on this panel.
- **Colour** - `target-colorspace-hint=auto` was verified to be a no-op
  here (output identical to the default); `icc-profile-auto` is off because
  Windows only exposes WCS profiles here, which mpv cannot read.

---

## Notes and caveats

- **Windows 10 has no real rounded window corners.** The DWM corner API is
  Windows 11 only, and Win10's blur-behind blurs the desktop, not the
  video, so "real glass" is not achievable in mpv on this OS. The skins
  simulate it with translucency and noise, which is why the accent colour
  and typography do the heavy lifting.
- **PGS / VobSub subtitles cannot be restyled** - they are pre-rendered
  images. `sub-gauss` and `sub-gray` only soften them. Text subs get the
  full treatment.
- **`sub-*` options do not affect ASS/SSA files**, which carry their own
  styling. `sub-ass-style-overrides` gently restyles the `Default` style of
  fansub ASS so it matches the plain-text subtitles.
- **Deleting a file via the skin's menu is permanent on Windows** - the
  recycle-bin path (`use_trash`) is Linux/macOS only.
- `mpv --register` was run, so Windows shows a proper mpv entry in the media
  flyout and protocol handlers work. Undo with `mpv --unregister`.

---

## Fonts

All fonts live in `fonts\` and are loaded by mpv automatically - they are
**not** installed system-wide.

| Font | Licence | Use |
|---|---|---|
| Geist Medium / SemiBold / Mono | OFL-1.1 | subtitles, OSD, ModernZ text |
| Inter Medium / SemiBold | OFL-1.1 | alternative |
| Source Sans 3 | OFL-1.1 | alternative |
| Material Icons Round | Apache-2.0 | Liquid Glass icons |
| modernz-icons | LGPL-2.1 (bundled with ModernZ) | ModernZ icons |

The full OFL-1.1 text is in the repository's `licenses/` directory. It is not
kept in `fonts\` because libass tries to load every file there as a font.

---

## Scripts and licences

| Script | Licence |
|---|---|
| ModernZ | LGPL-2.1 |
| uosc (Liquid Glass fork) | LGPL-2.1 |
| thumbfast | MPL-2.0 |
| quality-menu | GPL-2.0 |
| sponsorblock_minimal | GPL-3.0 |
| recentmenu | MIT |
| mpv-webm | MIT |
| Anime4K shaders | MIT |
| CfL_Prediction | MIT |
