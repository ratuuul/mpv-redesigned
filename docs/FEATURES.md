# Features

Every feature in the shipped configuration, what it actually does, and the exact
place to change it. Paths are relative to `%APPDATA%\mpv` unless they start with
`config/` (then they are relative to the repository).

Options are grouped the way the config is: `conf/video.conf`,
`conf/audio.conf`, `conf/subtitles.conf`, `conf/interface.conf`,
`conf/profiles.conf`. Everything is included from `mpv.conf`.

---

## Video

### Renderer: gpu-next on d3d11

`vo=gpu-next` with `gpu-api=d3d11` and `gpu-context=d3d11`.

**Why d3d11 and not Vulkan:** both were measured on the reference machine and
produced pixel-identical output (PSNR 66.5 dB on a 1080p reference), but d3d11
is Intel's best-supported Windows path and the only one where
`d3d11va-zero-copy` applies. Vulkan is one keypress away (`Alt+0`) if you want
to compare on your hardware.

**Tune:** `conf/video.conf`, lines under `---- renderer ----`. To make Vulkan
permanent, either press `Alt+0` per session or delete the `gpu-api` /
`gpu-context` / `hwdec` lines and let the `gpu-vulkan` profile's values become
the defaults.

### Zero-copy hardware decoding

```ini
hwdec=d3d11va
d3d11va-zero-copy=yes
```

Frames stay in GPU memory; on shared-memory Intel graphics skipping the extra
GPU→GPU copy is the single biggest win.

**If you see green or corrupt edges,** delete `d3d11va-zero-copy=yes` and
retest. Some older Intel drivers mishandle it.

**Tune:** `conf/video.conf`, `---- decoding ----`.

### Scaling

| Option | Value | Why |
|---|---|---|
| `scale` | `ewa_lanczossharp` | sharpest good-looking luma upscaler |
| `cscale` | `spline36` | chroma is low-frequency; EWA there is wasted work |
| `dscale` | `mitchell` | soft downscale without ringing (4K → 1080p) |
| `scale-antiring` | `0.6` | suppresses EWA ringing |
| `scaler-resizes-only` | `yes` | do not rescale when the window matches the video |
| `correct-downscaling`, `linear-downscaling`, `sigmoid-upscaling` | `yes` | gpu-next defaults, stated explicitly |

All of these were measured at 1920×1200 with zero dropped frames on the iGPU.

**Tune:** `conf/video.conf`, `---- scaling ----`. The `max-quality` profile
(`Alt+2`) raises the luma scaler to `ewa_lanczos4sharpest` and doubles the
deband iterations; `fast` (`Alt+1`) drops everything to bilinear.

### Debanding

```ini
deband=yes
deband-iterations=2
deband-threshold=48
deband-range=16
deband-grain=24
```

Removes the 8-bit banding that compressed and streamed video shows in skies and
gradients. Costs under a millisecond here.

**Tune:** `conf/video.conf`, `---- banding ----`. Lower `deband-threshold` if
debanging smears fine film grain you want to keep.

### Judder removal

```ini
video-sync=display-resample
interpolation=yes
tscale=oversample
```

The panel is 60 Hz and most content is 23.976 or 24 fps. `display-resample`
retimes playback to the display and interpolation blends the in-between frames.
This is the most visible single improvement on a 60 Hz panel.

**Tune:** `conf/video.conf`, `---- motion / sync ----`. For a battery-powered
laptop, `Alt+1` (`fast`) turns both off.

### Colour

```ini
dither=fruit            # blue noise, no visible pattern
dither-depth=8
temporal-dither=no      # avoids LCD flicker
tone-mapping=spline     # HDR -> SDR
hdr-compute-peak=no
libplacebo-opts=peak_detect=no
icc-profile-auto=no
```

`peak_detect` is documented as prohibitively slow on weaker integrated GPUs, so
it is off. `icc-profile-auto` is off because Windows only exposes WCS profiles,
which mpv cannot read, and auto-detection produced both over- and
under-saturation here.

**Tune:** `conf/video.conf`, `---- colour ----`. If you have a wide-gamut
monitor and a real ICC profile, install it as the display profile and set
`icc-profile-auto=yes`.

### Graphite shader cache

`gpu-shader-cache-dir=~~/cache/gpu-shaders` — libplacebo compiles user shaders
once and reuses them, so the first play of a file does not stutter while the
driver builds the pipeline. Delete `%APPDATA%\mpv\cache\gpu-shaders` to force a
rebuild.

### Anime4K, automatic

Two conditional profiles in `conf/profiles.conf`:

```ini
[anime-restore]
profile-cond=path and path:lower():find("anime") ~= nil
glsl-shaders=~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/CfL_Prediction.glsl
```

Any file whose path contains `anime` gets line-art restoration at source
resolution plus chroma-from-luma, because libplacebo has no equivalent of a CNN
restore pass. `anime-restore-soft` does the same with the softer network for
sources at 720p or below.

**Tune:** rename the folder, or change the `find("anime")` string. Force it on
for one session with `Alt+4` (`shaders-anime`), off with `Alt+5`.

`shaders-anime-full` (not bound to a key) adds the x2 CNN upscale as well; it is
noticeably heavier and only worth it for SD anime.

### Clip cutting

`W` opens mpv-webm's range picker: mark in, mark out, encode. Configured in
`script-opts/webm.conf` to write **H.264/AAC at CRF 18** instead of the script's
VP8 default, which is CPU-only and slow. `target_filesize=5000` kB, source
resolution, output next to the source file.

**Tune:** `script-opts/webm.conf`. `W` itself is the `keybind` option in the
same file.

---

## Audio

### Output

```ini
ao=wasapi
audio-exclusive=no
audio-client-name=mpv
```

WASAPI shared mode, so system sounds keep working while mpv plays, and the
player shows up as `mpv` in the Windows volume mixer.

**Tune:** `conf/audio.conf`, `---- output ----`. `audio-exclusive=yes` gives
bit-perfect output but silences everything else.

### Level matching

```ini
replaygain=track
replaygain-preamp=0
replaygain-clip=no
volume=100
volume-max=130
```

ReplayGain is applied on top of the cubic volume curve, so the volume limit does
not eat the gain. `replaygain-clip=no` leaves mpv's clipping protection **off**:
loud masters are allowed to clip rather than being quietly turned down. Set
`replaygain-clip=yes` if that distortion bothers you.

**Tune:** `conf/audio.conf`, `---- volume ----` and `---- replaygain ----`.
`replaygain=album` keeps an album at a constant level relative to itself.

### Optional loudness normalisation

Two profiles, deliberately **not** on by default because single-pass loudnorm
pumps and costs CPU:

- `Alt+8` → `loudnorm` → `af=lavfi=[loudnorm=I=-16:TP=-1.5:LRA=11]`
- `Alt+9` → `dynaudnorm` → `af=lavfi=[dynaudnorm=f=250:g=5:p=0.9:r=0.9]`

**Tune:** `conf/profiles.conf`, `---- audio ----`. Reset with
`mpv --no-config` or by restarting; there is no "off" profile, so add one:

```ini
[audio-default]
profile-desc=Raw audio
af=
```

### Gapless, pitch, channels

```ini
gapless-audio=weak
audio-pitch-correction=yes     # scaletempo2, works without librubberband
audio-channels=auto-safe       # the system's own speaker layout
audio-normalize-downmix=yes    # no clipping when downmixing surround
audio-resample-filter-size=32  # cleaner when a resample does happen
```

**Tune:** `conf/audio.conf`. `audio-samplerate=48000` is present but commented
out: leaving the device at its native rate avoids resampling entirely.

### Track selection

```ini
aid=auto
sid=auto
slang=eng,en,jpn
audio-file-auto=fuzzy
sub-auto=fuzzy
```

`fuzzy` finds sidecar files whose names only partly match. Extra lookup
directories, relative to the config dir:

```ini
audio-file-paths=~~/audio
sub-file-paths=sub;subs;subtitles;~~/subtitles
```

**Tune:** `conf/audio.conf`, `---- track selection ----`. Drop
`%APPDATA%\mpv\subtitles\` in there and any `*.srt` is picked up automatically.

---

## Subtitles

### Typography and colour

```ini
sub-font='Geist Medium'
sub-font-size=40
sub-color="#F5F2EF"
sub-outline-size=1.15
sub-shadow-offset=1.1
sub-blur=0.3
sub-border-style=outline-and-shadow
sub-margin-y=42
sub-margin-x=120
```

Geist Medium has a tall x-height, open counters and unambiguous `I`/`l`/`1`.
Warm off-white instead of pure white; the hairline outline plus soft shadow is
what stops subtitles looking like a Crunchyroll slab.

Sizes are scaled from a 720p reference: `sub-font-size=40` is roughly 60 px at
1080p.

**Tune:** `conf/subtitles.conf`. Every line has a comment. Live adjustments:
`z`/`Z` (delay), `x`/`X` (position), `r`/`R` (scale), `Ctrl+j`/`Ctrl+J` (font
size).

### ASS/SSA handling

```ini
sub-ass-override=scale
sub-ass-style-overrides=Default.OutlineColour=&HA0000000,Default.Outline=1.15,Default.Shadow=1.1,Default.PrimaryColour=&H00F5F2EF
sub-ass-force-margins=yes
sub-scale-signs=no
```

Only the `Default` style is touched, so fansub signs and italics keep their
identity. `sub-ass-force-margins` keeps the caption a fixed distance from the
bottom edge of the window, so it lands in the lower letterbox band of a
2.35:1 film instead of floating over the picture.

**Tune:** `conf/subtitles.conf`, `---- gentle restyle of ASS subs ----`. Format
is `[Style.]Field=Value`; ASS colours are `&HAABBGGRR`. Set
`sub-ass-override=no` to let ASS files style themselves completely.

### Bitmap subtitles

`sub-gauss=0.6` and `sub-gray` soften PGS/VobSub subtitles. They are
pre-rendered images, so they cannot be restyled — only blurred or desaturated.

### Subtitle menus and downloading

| Key | Action |
|---|---|
| `V` | track menu, including an OpenSubtitles search |
| `D` | download subtitles from the online providers |
| `Ctrl+v` / `Alt+d` | load a subtitle file from disk |
| `Alt+s` / `Alt+Shift+s` | YouTube subtitle picker (see below) |
| `Alt+o` | re-run the automatic OpenSubtitles lookup |

### Automatic subtitle lookup for local files

`scripts/autosubs.lua`, configured by `script-opts/autosubs.conf`:

```ini
auto_load=prompt     # prompt | single | off
delay=2.5
extensions=mkv;mp4;avi;mov;m4v;webm;ts
```

When a local file starts with no subtitle track, it either opens uosc's subtitle
picker pre-filled with a cleaned-up title (`prompt`, the default) or downloads
silently only when there is exactly one strong match (`single`). It never
blocks playback.

It uses uosc's own `ziggy` binary and API key as the backend — there is no
second OpenSubtitles client in this repository.

**Tune:** `script-opts/autosubs.conf`. `auto_load=off` disables it entirely;
`Alt+o` still works as a manual trigger.

### Subtitle looks as profiles

- `Alt+6` → `subs-panel` — Netflix-style translucent box
  (`sub-border-style=background-box`).
- `Alt+7` → `subs-cinema` — shadow only, no outline, 64 px from the bottom.

**Tune:** `conf/profiles.conf`, `---- subtitles ----`.

---

## YouTube and streaming

### The yt-dlp options line

```ini
ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node
```

Three things matter and they are all documented in `mpv.conf` next to the line:

1. **Every entry needs `=value`.** A bare key swallows the next entry and
   corrupts the whole yt-dlp command line; the video then never loads.
2. **A value must not contain a comma.** Use `|`, which yt-dlp treats as list
   alternation.
3. **`#` starts a comment**, even mid-line, so quote any value containing one.

`js-runtimes=node` is required for full quality: without a JS runtime, yt-dlp
cannot solve YouTube's signature and `n` challenges, YouTube forces SABR
streaming and the format list comes back empty. Needs Node.js on `PATH`.

`cookies-from-browser=firefox` is **not** shipped because it hard-fails when
that profile does not exist. Add it only if you want age-gated videos — see
[INSTALL.md](INSTALL.md#optional-age-restricted-videos).

### Format picker

`F` opens `scripts/quality-menu.lua`, which lists the formats the server
actually offers (codec, resolution, bitrate, fps) and switches between them
without reloading the file. `Alt+f` does the same for audio tracks; `Ctrl+r`
reloads the stream at the current position.

**Tune:** `script-opts/quality-menu.conf`. Useful options:

```ini
show_unavailable_formats=no   # hide formats yt-dlp reports as unavailable
gray_unavailable_formats=no
key_up_binding / key_down_binding / key_select_binding
```

### YouTube subtitle picker

`Alt+s` lists **every** subtitle YouTube offers for the video: creator-uploaded
tracks plus auto-generated captions, in every language. `Alt+Shift+s` loads the
pick as the secondary (top-of-screen) track.

`scripts/ytsubs.lua` builds the list from the info dict that mpv's `ytdl_hook`
already cached, so opening the menu costs no network traffic. The chosen track
is downloaded once to `cache\ytsubs\` and added with `sub-add`, which means it
also appears in `v` and in the skin's subtitle menu.

**Tune:** `script-opts/ytsubs.conf`.

```ini
cache_dir=~~/cache/ytsubs
sub_format=srt           # srt | vtt
offer_manual=yes
offer_auto=yes
max_auto=60
auto_select=no
auto_langs=en,ja
timeout=20
```

**Known limitation:** YouTube rate-limits the `timedtext` endpoint
(HTTP 429) for machine-translated captions. Creator-uploaded and
original-language captions work; a translated one may be refused after two
retries. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### SponsorBlock

`b` toggles skipping. Segments are fetched per video and skipped by seeking.

```ini
categories=sponsor;intro;outro;selfpromo;interaction;preview;music_offtopic
```

**Tune:** `script-opts/sponsorblock_minimal.conf`. It explains each category and
warns that `preview` can clip legitimate story content in episodic videos.
`hash=true` switches to hashed video IDs but needs `sha256sum`, which is not on
a stock Windows `PATH`.

### Downloading the current stream

`Ctrl+d` saves what you are watching with yt-dlp, at the quality mpv already
negotiated. It runs asynchronously (playback never stalls), shows live progress,
never overwrites (an existing file becomes `... [2].mp4`), and ignores local
files.

**Tune:** `script-opts/download.conf`.

```ini
download_dir=~/Videos/mpv-downloads
extra_args=
```

`~/` expands to your user profile. `extra_args` is passed straight to yt-dlp,
space separated.

### Thumbnail previews on the seekbar

`scripts/thumbfast.lua` spawns a second headless mpv that decodes thumbnails
into a pipe; the skin only renders them. Configured in
`script-opts/thumbfast.conf`:

```ini
hwdec=no     # a second d3d11va decoder can deadlock with the main one
network=no   # never fetch a thumbnail over the network
direct_io=no # required for the Windows pipe path
scale_factor=1.0
```

**Tune:** those four values. `network=yes` makes YouTube previews work but
doubles bandwidth and often stalls.

---

## UI and skin

### Liquid Glass

The active skin is `scripts/uosc/` — a fork of uosc v5.9.2 with a glass visual
layer. Details and the modification list are in
[SKINS.md](SKINS.md) and [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Runtime options, `script-opts/liquid-glass.conf`:

```ini
liquid_glass_theme=dark          # dark | light
liquid_glass_intensity=1.0       # glass layer strength, clamped 0.5-1.5
liquid_glass_accent=E8553A
liquid_glass_show_frost_noise=yes
reduced_motion=no
liquid_glass_tick_sound=no       # was spawning a process per scroll event
liquid_glass_next_video_threshold=120
liquid_glass_min_width_landscape=760
liquid_glass_min_height_landscape=320
liquid_glass_min_width_portrait=360
liquid_glass_min_height_portrait=360
```

All of these live in one file and are read by one option table, so mpv never
logs an "unknown key" warning for them.

### Controls appear on hover

uosc hides the control bar and the progress bar until the mouse approaches them.
`script-opts/uosc.conf` leaves both at their default, hover-only behaviour:

```ini
controls_persistency=
timeline_persistency=
```

Valid values are `video`, `paused`, `windowed`, `fullscreen`, `idle`, combined
with spaces. Set one to make that element permanent while it applies. The top
bar, volume and speed indicators stay hover-only, and the top bar is switched
off entirely:

```ini
top_bar=no
top_bar_controls=no
top_bar_title=no
```

The window title, the close button and the maximise button therefore never
appear; `f` toggles fullscreen and the title bar of the operating system stays
hidden as well.

### Control bar extras

The bar carries, from left to right: play/pause, previous/next, seek jump,
time, the timeline, time remaining, volume, speed, the subtitle and audio menus,
an info button, the playlist, settings and fullscreen.

The info button runs `script-binding stats/display-stats-toggle`, mpv's own stats
overlay — the fastest way to see codec, fps, bitrate and dropped frames. There is
no separate quality button: `F` opens the format picker, which lists every format
with its resolution and bitrate.

### Window chrome

```ini
border=yes
title-bar=no
window-dragging=yes
autofit-larger=1920x1200
snap-window=yes
```

`border=yes` with `title-bar=no` is the sweet spot on Windows 10: the caption is
hidden but `WS_CAPTION` remains, so Aero-Snap, Alt-Tab, the taskbar and the
maximise button all keep working.

**Do not add a bare `autofit=100%`** — mpv parses it as `100%x0`, which forces
the window to the full screen width and pushes it off the right edge of a 16:10
panel, taking the control bar with it.

**Tune:** `conf/interface.conf`, `---- window chrome ----`.

### OSD

Geist Medium at 32, centred near the top (`osd-align-y=top`,
`osd-margin-y=56`) so messages do not collide with the skin's top bar, 1.6 s
duration.

**Tune:** `conf/interface.conf`, `---- OSD ----`. `osd-level=1` is required —
mpv only prints to the OSD at level 1 and above.

### Screenshots

```ini
screenshot-format=png
screenshot-high-bit-depth=yes
screenshot-png-compression=3
screenshot-template=~~/screenshots/%F-%p%n
```

`s` saves with subtitles, `S` / `Ctrl+s` saves the video only at original
resolution. Files land in `%APPDATA%\mpv\screenshots\`.

**Tune:** `conf/interface.conf`, `---- screenshots ----`. Change
`screenshot-directory` to write elsewhere; `%F` is the filename, `%p` the
playback position, `%n` a counter.

### Windows integration

```ini
media-controls=yes
input-media-keys=yes
```

Gives you working media keys and a proper entry in the Windows media flyout. To
register the app name and icon once:

```powershell
mpv --register      # undo with: mpv --unregister
```

### Mini player (picture-in-picture)

`Alt+p` shrinks the window to 480×270, removes the border, pins it above other
windows and anchors it to the bottom-right of the monitor's work area (above the
taskbar). Portrait videos get a portrait window. Toggling again restores the
previous ontop/border/geometry/size/fullscreen state exactly.

**Tune:** `script-opts/pip.conf`.

```ini
pip_width=480
pip_height=270
pip_margin=24
```

### Idle screen: photo background

`scripts/bg.lua` fetches a photograph and shows it whenever mpv has nothing to
play, with a welcome overlay drawn on top. `Ctrl+Shift+K` fetches another one.

```ini
enabled=yes
keywords=nature,landscape,minimal,city,night
sources=picsum
width=1920
height=1200
cache_size=20
initial_delay=0.2
show_prompt=yes
prompt=Drop a file or link to play
font=Geist SemiBold
font_size=80
font_sub=Inter Medium
font_size_sub=32
```

The photo is scaled to fill the window (`panscan=1.0`), so there are no black
bars on the sides. The overlay is typeset in Geist SemiBold and Inter Medium —
both ship in `fonts/` and are loaded by mpv from there, not installed system
wide — with a hairline outline and a soft drop shadow so it stays readable over
a bright photograph.

Photos are cached in `cache\bg\`, bounded by `cache_size` (oldest deleted first),
so going back to the idle screen does not always need the network.
`initial_delay` exists so that `mpv something.mkv` shows the video rather than a
photo at startup.

`width`/`height` are the requested photo size; the values shipped match the
panel this was tuned on. Ask for something near your own screen resolution or
the photo will be upscaled.

Only `picsum` is enabled. The script still understands `loremflickr` and
`unsplash`, but both were dead ends when they were checked: loremflickr answers
HTTP 500 on every request and the random endpoint of unsplash was retired
(HTTP 503). Leaving them in the list only cost about 1.3 s per photo, because
every request had to fail first. Set `enabled=no` if you are offline, would
rather not make those requests, or want the skin's own idle background back.

**Tune:** `script-opts/bg.conf`.

### Reopen the last media with a double-click

`scripts/lasthit.lua` binds `MBTN_LEFT_DBL`. Double-clicking the window opens
the last real media that was played and resumes it at the exact position it was
left at.

The background photograph is not a candidate — the script skips everything that
lives in `cache/bg/` — so the last video wins over the last photo.

The position comes from mpv's own watch-later store. Two options make that
reliable:

```ini
resume-playback=yes
resume-playback-check-mtime=no
write-filename-in-watch-later-config=yes
```

`resume-playback-check-mtime` is off because a remote file has no modification
time, and the check silently drops the saved position for every HTTP stream.
`write-filename-in-watch-later-config` records the source path inside the
watch-later entry, which is what lets the script map a watch-later file back to
the media it belongs to.

**Tune:** `scripts/lasthit.lua` and `mpv.conf`. The binding is in
`input.conf`; the skin used to swallow every double click, so the force binding
that did that was removed from `scripts/uosc/lib/cursor.lua`.

### Recent files

`Ctrl+Shift+r` opens a menu of what you played, with series and episode
awareness. Backed by `%APPDATA%\mpv\recent.json`, which is created at runtime
and is not part of this repository.

**Tune:** the options are at the top of `scripts/recentmenu.lua`
(`length`, `ignore_same_series`, `reduce_io`). For a config-file override,
create `script-opts/recentmenu.conf` with those same keys.

### The parked second skin

ModernZ ships in `skins\modernz`. `switch-skin.cmd modernz` swaps it in. See
[SKINS.md](SKINS.md).

---

## Automation and housekeeping

### One keymap for both skins

`input.conf` never talks to a skin directly for navigation. It sends a message
to `scripts/nav_shim.lua`, which asks who is loaded:

- **Liquid Glass** answers on `user-data/skin/liquidglass`. The shim forwards
  to the skin's centring overlays (`lg-seek`, `lg-volume`, …).
- **Anything else** (ModernZ): the shim performs the command natively and
  ModernZ draws its own feedback.

So `Left`, `Right`, `Up`, `Down`, `{`, `}`, wheel and the number keys behave
identically in both skins. See [ARCHITECTURE.md](ARCHITECTURE.md).

### Resume and watch history

```ini
save-position-on-quit=yes
resume-playback=yes
resume-playback-check-mtime=no
write-filename-in-watch-later-config=yes
watch-later-options=start,speed,pitch,aid,sid,sub-delay,sub-scale
save-watch-history=yes
```

Only the listed properties are restored. That is deliberate: restoring volume
and mute state makes a player feel broken when you switch outputs.

`resume-playback-check-mtime=no` is required for remote media: a HTTP stream has
no modification time, and with the check enabled mpv quietly discards the saved
position for every one of them. `write-filename-in-watch-later-config=yes`
writes the source path into the watch-later entry, which is what allows the
double-click action to find the position again.

`save-watch-history=yes` is not an mpv default; `recentmenu.lua` and
`select.lua` both use it.

On Windows mpv keeps state — `watch_later\`, `cache\` and
`watch_history.jsonl` — under `%LOCALAPPDATA%\mpv`, not in the config directory.
Moving the config therefore does not lose resume points. The installer still
carries an old `watch_later\` across if one exists in the backup, for
configurations created before mpv made that split.

### Folder playback

```ini
autocreate-playlist=same
directory-mode=recursive
```

`mpv .` plays the whole current folder and its subfolders in order.

**Tune:** `mpv.conf`. `autocreate-playlist=fuzzy` also picks up similarly named
files next to the one you opened.

### Profiles on demand

`conf/profiles.conf` defines `fast`, `max-quality`, `cine`, `shaders-anime`,
`shaders-anime-full`, `shaders-off`, `subs-panel`, `subs-cinema`, `loudnorm`,
`dynaudnorm`, `gpu-vulkan`, `gpu-d3d11` and `windowed-full`. `Alt+1`…`Alt+0`
apply the first ten; the others are reachable with
`apply-profile <name>` from the console (`` ` ``) or a temporary `--profile=`.

`profile-restore=copy` on the automatic profiles means the values they change
are restored when the next file loads, so an anime file does not leave Anime4K
shaders on for a live-action file.

**Tune:** `conf/profiles.conf`. Any profile can also be applied from the command
line without editing anything:

```powershell
mpv --profile=fast "%USERPROFILE%\Videos\something.mkv"
```

### Verification

The installer starts mpv once with `--vo=null --ao=null` and fails loudly if the
configuration produces parse errors. For a manual check:

```powershell
mpv --idle=yes --vo=null --ao=null --msg-level=all=warn --log-file="$env:TEMP\mpv.log"
Select-String -Path "$env:TEMP\mpv.log" -Pattern 'Error parsing option|Invalid value|Lua error|\[e\]'
```

Warnings are worth reading too. `mpv --msg-level=all=warn` logs an
`unknown key '...', ignoring` line for every option in a `script-opts` file
that the script does not know, which is how a renamed option or a stale
options file shows up.

To check the configuration without touching a real installation, install it
into a scratch directory and point mpv at it:

```powershell
.\install.ps1 -ConfigOnly -Force -NoBackup -InstallDir "$env:TEMP\mpv-scratch"
mpv --config-dir="$env:TEMP\mpv-scratch" --idle=yes --vo=null --ao=null --msg-level=all=warn
```

`tools/sync-config.ps1` does the same check after every merge, and refuses to
commit a configuration that produces an error or a warning.
