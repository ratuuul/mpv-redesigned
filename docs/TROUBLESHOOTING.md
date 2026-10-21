# Troubleshooting

Every entry here is a bug that was actually hit while building this config, not
a hypothetical. Start at the top; the first three account for most breakage.

---

## YouTube videos never load (the player sits there, or exits)

Almost always a malformed `ytdl-raw-options` line in `mpv.conf`.

mpv parses that option as a **comma-separated list of `key=value` pairs**:

```ini
ytdl-raw-options=no-playlist=,write-sub=,sub-langs=(en|ja).*
```

Three rules, all of them easy to break:

1. **Every entry needs `=value`.** A bare key swallows the next entry, which
   silently corrupts the whole yt-dlp command line. The video then never
   resolves and mpv looks frozen.
2. **A value must not contain a comma.** Use `|` and let yt-dlp split the list.
3. **`#` starts a comment** in mpv config files. Quote any value containing it.

Check what mpv actually built:

```
mpv --log-file=%TEMP%\mpv.log --msg-level=all=debug,ytdl_hook=debug "URL"
```

Look for the `ytdl_hook` line that prints the argument list. If an option is
missing or two options are merged, that is your bug.

---

## No controls at all — no buttons, no progress bar

The skin is crashing on load. Check the log:

```
mpv --log-file=%TEMP%\mpv.log --msg-level=all=warn
```

If you see:

```
Lua error: .../uosc.lua:20: module 'lib/std' not found
```

then the Liquid Glass skin is **not** in `scripts\uosc\`.

mpv only puts a script's own directory on the Lua module path when the script
lives inside `scripts/`. uosc calls `require('lib/std')`, `require('elements/Controls')`
and so on, so it **must** live at `%APPDATA%\mpv\scripts\uosc\main.lua`.

Loading it from anywhere else via `script=~~/skins/.../uosc.lua` fails. That is
why `switch-skin.ps1` physically moves folders instead of pointing at a file.

---

## Options that look correct are ignored, or colours are wrong

**In mpv config files, `#` begins a comment.**

```ini
sub-color=#F5F2EF          # WRONG - everything after # is discarded
sub-color="#F5F2EF"        # correct
```

This affects every hex colour and every value containing `#`.

---

## `script-binding foo/bar` does not exist

mpv normalises dashes to underscores in script names:

| File | Script name |
|---|---|
| `nav-shim.lua` | `nav_shim` |
| `quality-menu.lua` | `quality_menu` |
| `ytsubs.lua` | `ytsubs` |

So the binding is `script-binding quality_menu/video_formats_toggle`, not
`quality-menu/...`.

Also note that **shifted letters collapse**: `Ctrl+Shift+K` is delivered as
`Ctrl+k`. If you bind `Ctrl+Shift+S` you are really binding `Ctrl+S`.

---

## Startup aborts with "Command sub-add: required argument url not set"

```
[   0.000][e][input] Command sub-add: required argument url not set.
[   0.000][e][input] Command was defined at ...\mpv\input.conf:79.
```

A bare `sub-add` binding in `input.conf` is invalid: mpv validates the argument
count when it parses `input.conf` and gives up on the rest of the file. The
shipped binding is therefore:

```ini
Ctrl+v  script-binding uosc/load-subtitles
```

which opens a file browser and calls `sub-add` with a real path. If you see
this error, your `input.conf` predates that fix, or you added the binding back
yourself.

More generally: any `input.conf` line whose command is malformed kills the
**whole file**, so every later binding silently stops working. When a key that
should exist does nothing, check the log for `[e][input]` first.

---

## The subtitle downloader never opens

```
[e][uosc] open_subtitle_downloader: subtitles_directory not writable: C:\...\mpv\subtitles
```

The uosc skin probes its download folder by writing a file into it. If
`subtitles\` does not exist under the config directory, the probe fails and the
downloader refuses to open - and so does the automatic OpenSubtitles lookup
(`Alt+o`), which uses the same code path.

The current build creates the folder itself, so this should not happen. If it
does, the path is genuinely unwritable - a read-only install, or a config
directory on a drive the user cannot write to. Check the path in the message
and create the folder by hand:

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\mpv\subtitles"
```

The installer creates it too, so a directory deployed by `install.ps1` always
has it. A config directory that was assembled by hand, or one deployed with an
older installer, may not.

---

## A Lua command does nothing

mpv's command API takes the command and its arguments as **separate** parameters:

```lua
mp.commandv('add volume', '10')    -- WRONG, silently does nothing
mp.commandv('add', 'volume', '10') -- correct
mp.commandv('multiply', 'speed', '1.1')  -- correct
```

---

## The window is smaller than the screen

Windows display scaling. At 125% on a 1920x1200 panel the usable logical
resolution is 1536x960, so `geometry=1920x1200` does not do what you expect.

Check the real numbers:

```lua
mp.get_property_native('osd-dimensions')
mp.get_property('display-hidpi-scale')
```

---

## The control bar floats above the bottom of the screen in fullscreen

This is letterboxing, not a bug in the skin. mpv reports the **video** rectangle
(aspect-corrected), not the window, so a 16:9 video on a 16:10 panel has black
bars top and bottom and the bar anchors to the bottom of the *video*.

The Liquid Glass layout anchors to `display.height + osd-dimensions.mb` so it
sits on the window edge instead. If you fork the skin and the bar drifts up in
fullscreen, that is the number to fix.

---

## Auto-generated YouTube captions fail with HTTP 429

Creator-uploaded subtitle tracks work. Auto-generated and auto-translated
(`tlang=`) tracks are rate-limited hard by YouTube's `timedtext` endpoint; every
player client (`web`, `mweb`, `tv`, `ios`, `android_vr`, `web_safari`,
`tv_simply`) returns 429.

This is server-side. `ytsubs.lua` retries twice, then shows a clear message
rather than loading the HTML error page (which mpv would otherwise try to parse
as a subtitle file).

---

## YouTube offers no formats above 360p / "only images are available"

Symptom: the video plays, or stalls, but `F` lists nothing useful, and the log
shows yt-dlp reporting no video formats, or mpv picking a tiny pre-merged
format.

Cause: modern yt-dlp has to solve YouTube's signature and `n` challenges in
JavaScript. It only enables the `deno` runtime by default. If that — and any
runtime named in `ytdl-raw-options` — is missing, yt-dlp warns that "some
formats may be missing" and YouTube may push the player onto SABR streaming.

What it looks like with no runtime available (measured on yt-dlp 2026.08.19):

```
[debug] JS runtimes: none
WARNING: [youtube] No supported JavaScript runtime could be found. Only deno is
enabled by default; to use another runtime add --js-runtimes RUNTIME[:PATH] ...
```

Playback is **not** aborted — the process still exits 0 and, on this yt-dlp
version, the `visionos` impersonation client still returned 2160p. That path is
not guaranteed, which is why the runtime is configured rather than assumed. The
hard failure it prevents is the one where every format comes back without a URL
and mpv reports only images, or falls back to a 360p pre-merged stream.

Check what yt-dlp actually has:

```powershell
yt-dlp -v --simulate "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1 |
    Select-String 'JS runtimes|nsig|SABR|WARNING'
```

With Node present the line reads `JS runtimes: node-24.19.0` (any version). If it
says `JS runtimes: none`, install Node.js and make sure a **new** terminal can
see it:

```powershell
winget install OpenJS.NodeJS.LTS
# or: scoop install nodejs-lts
node --version
```

The shipped `mpv.conf` already pins the runtime:

```ini
ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node
```

Leave it enabled even if you do not have Node: the option degrades to a warning,
it does not fail the download. If you would rather silence the warning, put a
`#` at the start of that line.

Confirm from inside mpv:

```powershell
mpv --msg-level=all=info,ytdl_hook=debug --log-file="$env:TEMP\mpv.log" `
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
Select-String -Path "$env:TEMP\mpv.log" -Pattern 'VO: \[|Video: ' | Select-Object -First 3
```

`VO: [gpu-next] 3840x2160` means the 4K stream was negotiated. `1280x720` means
it was not.

---

## yt-dlp says "Sign in to confirm you're not a bot" / video is age-restricted

Two different problems that look alike.

**1. No cookies at all.** Age gates, members-only videos and bot checks need a
signed-in session. Append a cookie source to the `ytdl-raw-options` line in
`%APPDATA%\mpv\mpv.conf` — same line, no commas inside the value:

```ini
ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node,cookies-from-browser=firefox
```

Test it before relying on it:

```powershell
yt-dlp --cookies-from-browser firefox --simulate "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

**Use Firefox.** Chrome, Edge and Chromium keep their cookie database encrypted
with a key bound to the application (DPAPI / app-bound encryption), and yt-dlp
aborts with `Failed to decrypt with DPAPI`. Firefox may stay open while you
play; yt-dlp copies the database instead of locking it.

**2. The cookie source does not exist.** This is the dangerous one:

```
ERROR: could not find firefox cookies database in "..."
```

yt-dlp exits, `ytdl_hook` fails, and **every** YouTube URL stops loading — not
just age-gated ones. If that happens, remove `cookies-from-browser=...` from
`mpv.conf` first and confirm normal playback returns, then fix the profile path.
That is why the shipped default does not include it: most people do not have a
Firefox profile, and shipping it would break YouTube out of the box.

`cookies-from-browser=firefox:<profile-directory-name>` points at a specific
profile when several exist.

---

## Log says `Error opening memory font 'LICENSE-Geist.txt'`

mpv hands **every** file in `fonts\` to libass, which tries to open each one as
a font. A licence text or a readme in that directory produces an info-level error
on every file load. The shipped tree contains only `.ttf`/`.otf` files there; the
OFL text lives in the repository's `licenses/` directory.

Find anything that is not a font:

```powershell
Get-ChildItem "$env:APPDATA\mpv\fonts" -File |
    Where-Object { $_.Extension -notin '.ttf', '.otf', '.ttc' }
```

Delete or move whatever it prints.

---

## Playback stutters or the fan spins up

The full-quality stack (`ewa_lanczossharp`, `interpolation=yes`,
`video-sync=display-resample`) is tuned for a desktop-class GPU. On battery or
on an older iGPU, switch to the cheap profile:

| Key | Profile | Effect |
|---|---|---|
| `Alt+1` | `fast` | no interpolation, cheap scalers, `--hwdec` only |
| `Alt+2` | `max-quality` | the full stack |
| `Alt+0` | `gpu-vulkan` | Vulkan instead of d3d11 |

Check what is actually dropping frames:

```
mpv --msg-level=all=info --log-file=%TEMP%\mpv.log
```

and grep for `frame-drop-count`.

---

## Vulkan vs d3d11

Both were benchmarked on this hardware and produced **pixel-identical** output
(PSNR ≈ 66.5 dB on a 1080p reference); d3d11 won on driver maturity and gives
`d3d11va` zero-copy decode. `Alt+0` switches to Vulkan if you want to compare
on your own machine.

---

## The skin switcher did nothing

`switch-skin.ps1` moves `scripts\uosc` to `skins\liquid-glass\uosc` (or
`scripts\modernz` to `skins\modernz`). It cannot swap a skin that mpv has
already loaded — **restart mpv** afterwards.

If the folder is stuck because a file is locked, close mpv first.

---

## Resetting to a clean state

```powershell
# back up and start over
.\uninstall.ps1
.\install.ps1
```

`install.ps1` also carries over any `watch_later` and `screenshots` folders it
finds in the backup. On Windows mpv keeps resume data in `%LOCALAPPDATA%\mpv`,
so that state survives the reinstall either way; the carry-over is for trees
created before that split.
