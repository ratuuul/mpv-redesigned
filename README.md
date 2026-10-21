# mpv-redesigned

A tuned [mpv](https://mpv.io) for Windows, packaged as one config directory you
can install with a single command. It pairs a glass control bar (a fork of
[uosc](https://github.com/tomasklaen/uosc) called Liquid Glass) with a
full-quality video pipeline, a WASAPI audio chain, designed subtitle typography,
and the tooling that makes mpv usable as a YouTube client: a real format picker,
a subtitle picker that sees every language YouTube offers, SponsorBlock skipping,
clip cutting, downloads and picture-in-picture. Every option was checked against
the build that runs it and measured on the machine described under
[Tested on](#tested-on); the reasoning is written down next to each setting in
the config files.

> **Screenshot:** not included yet. The skin is best seen moving — a short
> screen capture of the control bar, the format picker and the idle screen will
> be added here. No placeholder image is faked in the meantime.

## Features

### Video

- `vo=gpu-next` with libplacebo — HDR→SDR tone mapping (`spline`), fruit dither,
  debanding with grain, correct downscaling.
- **d3d11 output + `d3d11va` zero-copy decode.** The single biggest win on an
  Intel iGPU with shared memory. `Alt+0` switches to Vulkan for A/B.
- EWA Lanczos sharp luma scaling, spline36 chroma, mitchell downscaling,
  anti-ringing at 0.6 — the full-quality stack still drops zero frames on the
  reference machine at 1920x1200.
- `video-sync=display-resample` + interpolation, which removes 24p→60 Hz judder.
- Anime4K line-art restoration applied **automatically** to files whose path
  contains `anime` (+ chroma-from-luma), with a softer variant for ≤720p.
- Build-time shader cache so the first play of a file does not stutter.
- Profiles for `fast`, `max-quality`, `cine` and Vulkan (`Alt+1`…`Alt+3`,
  `Alt+0`).

### Audio

- WASAPI shared-mode output, named `mpv` in the Windows volume mixer.
- ReplayGain track mode applied on top of the volume curve, with `volume-max=130`
  for quiet material. Clipping protection is off by default (`replaygain-clip`),
  which is fine at a 0 dB preamp; turn it on if loud masters distort.
- Gapless audio, pitch correction via `scaletempo2` (works without
  librubberband), `auto-safe` channel layout with clipping-safe downmix.
- Optional EBU R128 / dynamic normalisation profiles (`Alt+8`, `Alt+9`),
  deliberately off by default.

### Subtitles

- Geist Medium at 40, warm off-white, hairline outline plus soft shadow, slight
  blur — and a gentle restyle of the `Default` style of fansub ASS files so they
  match plain-text subtitles.
- `sub-ass-force-margins` so subtitles sit inside the letterbox bars of 2.35:1
  films instead of floating over them.
- Two opt-in looks: a Netflix-style translucent panel (`Alt+6`) and shadow-only
  cinema subtitles (`Alt+7`).
- Automatic OpenSubtitles lookup for local files when no subtitle track exists
  (`Alt+o` to re-run); PGS/VobSub bitmap subs are softened, not restyled.

### YouTube and streaming

- Format picker that lists the **real** formats the server offers and switches
  without reloading (`F` video, `Alt+f` audio) — not a 360p/720p/1080p preset
  list.
- Subtitle picker with every creator-uploaded and auto-generated track in every
  language, cached after the first fetch (`Alt+s`, `Alt+Shift+s` for the
  secondary track).
- Creator-uploaded subtitles pre-loaded into the normal track list via
  `ytdl-raw-options`, so `v` and the skin's Subtitles menu just work.
- SponsorBlock segment skipping (`b`), with a configurable category list.
- Download the stream you are already watching, at the quality mpv negotiated
  (`Ctrl+d`), with live progress and no overwrites.
- Cut a clip to H.264/AAC (`W`) with a frame-accurate range picker.

### UI and skin

- Liquid Glass: translucent control bar and timeline that stay visible while a
  video plays, macOS-style centred seek/volume/speed overlays, a speedometer with
  a spring needle, a floating "Next:" pill at the end of an episode, a buffering
  indicator and a custom window border.
- An info button in the control bar that opens mpv's own stats overlay — codec,
  fps, bitrate and dropped frames at a glance. The format picker is one key away
  (`F`).
- Seekbar thumbnail previews (thumbfast).
- Recent files menu (`Ctrl+Shift+r`).
- ModernZ is shipped as a parked alternative; `switch-skin.cmd` swaps them.
- Windows integration: media keys, SMTC flyout, Aero-Snap preserved.
- Idle screen: a fetched photograph with the cat and prompt on top
  (`Ctrl+Shift+K` for the next one), cached locally, off with one option.

### Automation

- `nav_shim.lua` maps one keymap onto both skins, so switching skins does not
  change how you drive the player.
- Resume where you left off, with a deliberately narrow `watch-later-options`
  list so stray volume/mute changes are not restored.
- Folder playback: `autocreate-playlist=same`, recursive directory mode.
- Sidecar audio/subtitle discovery (`fuzzy`), with extra lookup paths.
- Picture-in-picture / always-on-top mini player (`Alt+p`) that restores the
  exact previous window state, taskbar-aware on Windows.

## Install

### One-liner

Open **PowerShell** (not cmd) and run:

```powershell
irm https://raw.githubusercontent.com/ratuuul/mpv-redesigned/main/install.ps1 | iex
```

This downloads the repository archive, installs mpv if it is missing, fetches
`yt-dlp.exe`, backs up any existing mpv configuration, deploys this one, and
starts mpv once to confirm the config parses.

### From a clone

```powershell
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Preview without changing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

Config only (skip mpv and yt-dlp — you already have both):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigOnly
```

### Requirements

| | |
|---|---|
| OS | Windows 10 or 11, x86-64 |
| Shell | Windows PowerShell 5.1 (built in) or PowerShell 7 |
| Disk | ~60 MB for the configuration and its shader cache; ~150 MB more if mpv has to be installed |
| Optional | [Node.js](https://nodejs.org) on `PATH` — required for full-quality YouTube (see below) |
| Optional | A browser you are happy to point yt-dlp at, for age-restricted videos |

The installer does **not** need administrator rights.

### What it changes on disk

| Path | What happens |
|---|---|
| `%APPDATA%\mpv\` | The configuration is deployed here. An existing directory is first **moved** to `%APPDATA%\mpv-backup-<timestamp>\`, then `watch_later\` and `screenshots\` are copied into the new one. |
| `%LOCALAPPDATA%\mpv\` | mpv is unpacked here if it is not already on `PATH` and scoop is not installed. |
| User `PATH` | Only if the installer had to unpack mpv itself: `%LOCALAPPDATA%\mpv` is appended to the **user** `PATH` (no admin needed). |
| `%APPDATA%\mpv\yt-dlp.exe` | Downloaded from the official yt-dlp release page. |

Nothing is written to `Program Files`, the registry (beyond what mpv does when
you run `mpv --register` yourself), or any other user's profile.

Full details, including a manual install and an offline install, are in
[docs/INSTALL.md](docs/INSTALL.md).

## Quick start

```powershell
mpv "%USERPROFILE%\Videos\something.mkv"
mpv "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
mpv .                      # play everything in the current folder
```

| Key | Action |
|---|---|
| `Left` / `Right` | seek −5 s / +5 s (wheel scrubs too) |
| `Shift+Left` / `Right` | seek ∓1 s, frame exact |
| `Up` / `Down` | volume ±5 |
| `0`–`9` | jump to 0 %, 10 % … 90 % |
| `{` / `}` / `Backspace` | slower / faster / normal speed |
| `Space` or right-click | pause |
| `F` / `Alt+f` | YouTube video / audio format picker |
| `Alt+s` | YouTube subtitle picker (every language) |
| `Ctrl+d` | download the video you are watching |
| `Alt+p` | mini always-on-top player |
| `W` | cut a clip |
| `b` | toggle SponsorBlock skipping |
| `s` / `S` | screenshot with / without subtitles |
| `v` / `V` | cycle subtitle tracks / open the subtitle menu |
| `Alt+1`…`Alt+0` | performance and quality profiles |
| `Ctrl+Shift+K` | next idle background photo |
| `Ctrl+Shift+r` | recent files |

The complete list, generated from `input.conf`, is in
[docs/KEYBINDINGS.md](docs/KEYBINDINGS.md).

## Node.js and YouTube quality

Modern yt-dlp only enables its `deno` JavaScript runtime by default. If no JS
runtime is available, YouTube's signature and `n` challenges fail, YouTube
forces SABR streaming, and the format list comes back empty — the usual symptom
is "only images are available" or playback that silently drops to 360p.

The shipped `mpv.conf` therefore contains:

```ini
ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node
```

Install Node.js and make sure `node` is on `PATH`, then restart mpv:

```powershell
node --version
```

If you cannot install Node, comment that option out; YouTube will still play,
but only the lower, pre-merged formats will be offered.

**Age-restricted videos** ("Sign in to confirm your age") additionally need
cookies. Add `cookies-from-browser=firefox` to the same line — the browser
profile must exist, or yt-dlp aborts and *all* YouTube playback fails for that
profile. See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Moves `%APPDATA%\mpv` to a timestamped backup folder. `-Purge` deletes it
instead (and asks first). mpv itself is left installed — remove it with
`scoop uninstall mpv` or by deleting `%LOCALAPPDATA%\mpv`.

## Project layout

```
mpv-redesigned/
├─ install.ps1                 one-click installer (also runs from irm | iex)
├─ uninstall.ps1               backup-or-delete the installed config
├─ config/                     exactly what lands in %APPDATA%\mpv
│  ├─ mpv.conf                 master file; includes conf/*.conf
│  ├─ input.conf               key bindings (one keymap, both skins)
│  ├─ conf/
│  │  ├─ video.conf            renderer, decode, scaling, colour
│  │  ├─ audio.conf            WASAPI, volume, ReplayGain, tracks
│  │  ├─ subtitles.conf        typography, colour, ASS overrides
│  │  ├─ interface.conf        window chrome, OSD, screenshots
│  │  └─ profiles.conf         conditional + on-demand profiles
│  ├─ scripts/
│  │  ├─ uosc/                 Liquid Glass skin (uosc fork, LGPL-2.1)
│  │  ├─ nav_shim.lua          skin-aware navigation
│  │  ├─ ytsubs.lua            YouTube subtitle picker
│  │  ├─ download.lua          download the current stream
│  │  ├─ pip.lua               mini player
│  │  ├─ autosubs.lua          automatic OpenSubtitles lookup
│  │  ├─ bg.lua                idle photo background
│  │  ├─ quality-menu.lua      real format picker
│  │  ├─ thumbfast.lua         seekbar thumbnails
│  │  ├─ sponsorblock_minimal.lua
│  │  ├─ recentmenu.lua
│  │  └─ webm.lua              clip cutter
│  ├─ script-opts/             per-script options
│  ├─ shaders/                 Anime4K + chroma-from-luma
│  ├─ fonts/                   Geist, Inter, Source Sans 3, Material Icons
│  ├─ skins/modernz/           parked alternative skin
│  ├─ switch-skin.ps1/.cmd     swap the active skin
│  └─ README.md                the config's own reference notes
├─ docs/
│  ├─ INSTALL.md               manual install, offline install, installer FAQ
│  ├─ KEYBINDINGS.md           generated from input.conf
│  ├─ FEATURES.md              every feature, and how to tune it
│  ├─ ARCHITECTURE.md          why the config is shaped this way
│  ├─ SKINS.md                 Liquid Glass vs ModernZ
│  └─ TROUBLESHOOTING.md       real failures, with fixes
├─ tools/gen-keybindings.ps1   regenerates docs/KEYBINDINGS.md
├─ licenses/                   full licence texts
└─ .github/workflows/          CI: PowerShell + Lua syntax, no binaries
```

## Tested on

Windows 10 (IoT Enterprise LTSC 19044), 1920×1200 @ 60 Hz panel, Intel
integrated graphics, **mpv 0.41-dev** with libplacebo 7.358.0. Frame drops,
scaler cost and renderer equality were measured on this hardware; the numbers
are quoted in `conf/video.conf` and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Licence

The original work here — configuration, PowerShell installers, documentation and
the scripts written for this project — is **MIT**. See [LICENSE](LICENSE).

The repository also redistributes third-party skins, scripts, shaders and fonts,
each under its own licence: LGPL-2.1 (uosc fork, ModernZ), GPL-2.0
(quality-menu), GPL-3.0 (sponsorblock_minimal), MPL-2.0 (thumbfast), MIT
(Anime4K, CfL, recentmenu, mpv-webm), OFL-1.1 (Geist, Inter, Source Sans 3) and
Apache-2.0 (Material Icons Round).

Read [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for per-component
attribution and [`licenses/`](licenses/) for the full licence texts.

mpv and yt-dlp are **not** redistributed here; the installer downloads them.
