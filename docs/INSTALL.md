# Install

Two ways in: the script, or by hand. Both end with the same tree of files in
the mpv configuration directory:

- `~/.config/mpv` on Linux / macOS
- `%APPDATA%\mpv` on Windows

- [Prerequisites](#prerequisites)
- [One-command install](#one-command-install)
- [Manual install](#manual-install)
- [Offline install](#offline-install)
- [What gets installed and where](#what-gets-installed-and-where)
- [Flags](#flags)
- [Skin switching](#skin-switching)
- [yt-dlp setup](#yt-dlp-setup)
- [Fonts](#fonts)
- [Verification](#verification)
- [Uninstall and rollback](#uninstall-and-rollback)
- [Troubleshooting](#troubleshooting)
- [Security and privacy](#security-and-privacy)

## Prerequisites

| | Linux / macOS | Windows |
|---|---|---|
| OS | recent Linux distro or macOS | Windows 10 or 11 |
| Shell | bash (`#!/usr/bin/env bash`) | Windows PowerShell 5.1 or PowerShell 7 |
| Tools | `curl` or `wget`, and `tar` | none (built-in) |
| Disk | ~60 MB free | ~60 MB free |
| Network | for mpv (if missing), yt-dlp and the archive | same |

No administrator rights: everything goes to your user profile, or to a
`--config-dir` / `-InstallDir` you choose.

**mpv** does not have to be installed first: the installer prints a
per-distro hint when `mpv` is missing and continues, because the configuration
can be installed before the player. Install mpv first if you want the
verification step to run.

**Node.js** is not required to install, but full-quality YouTube needs it:
mpv.conf sets `js-runtimes=node` and without Node the format list comes back
empty. The installer prints a hint; it does not install Node for you.

## One-command install

### Linux / macOS — nothing cloned

```bash
curl -fsSL https://github.com/ratuuul/mpv-redesigned/raw/main/install.sh | bash
```

### Linux / macOS — from a clone

```bash
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned
bash install.sh
```

### Windows — nothing cloned

```powershell
irm https://raw.githubusercontent.com/ratuuul/mpv-redesigned/main/install.ps1 | iex
```

### Windows — from a clone

```powershell
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`-ExecutionPolicy Bypass` applies to that one process only; it does not change
the machine-wide policy.

### Piping from the internet (Linux / macOS)

When there is no script file on disk (`curl ... | bash`), the installer
downloads `main.tar.gz` from GitHub into a temp directory, unpacks it there,
and uses the `config/` folder from the extracted archive. Nothing is left
behind in the working directory; the temp directory is removed on exit.

## Manual install

No script needed:

### Linux / macOS

```bash
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned

# Back up whatever is there now (rename, do not merge)
if [[ -d ~/.config/mpv ]]; then
    mv ~/.config/mpv ~/.config/mpv-backup-$(date +%Y%m%d-%H%M%S)
fi

# Deploy
mkdir -p ~/.config/mpv
cp -R config/* ~/.config/mpv/

# yt-dlp, if you want YouTube
curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o ~/.config/mpv/yt-dlp
chmod +x ~/.config/mpv/yt-dlp
```

### Windows

```powershell
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned

# Back up whatever is there now (rename, do not merge)
if (Test-Path "$env:APPDATA\mpv") {
    Rename-Item "$env:APPDATA\mpv" "mpv-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
}

# Deploy
New-Item -ItemType Directory -Force "$env:APPDATA\mpv" | Out-Null
Copy-Item .\config\* "$env:APPDATA\mpv" -Recurse -Force

# yt-dlp, if you want YouTube
Invoke-WebRequest https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe `
    -OutFile "$env:APPDATA\mpv\yt-dlp.exe" -UseBasicParsing
```

Check it:

```bash
mpv --config-dir=~/.config/mpv --no-terminal --list-options > /tmp/mpv-check.log 2>&1
grep -E '\[e\]|Error parsing option|Invalid value|Lua error' /tmp/mpv-check.log
```

No output means the configuration parsed. On Windows:

```powershell
mpv --config-dir="$env:APPDATA\mpv" --no-terminal --list-options > "$env:TEMP\mpv-check.log" 2>&1
Select-String -Path "$env:TEMP\mpv-check.log" -Pattern 'Error parsing option|Invalid value|\[e\]'
```

If you install mpv by hand, unpack a build from
[shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake)
or [mpv.io/installation/](https://mpv.io/installation/) somewhere on `PATH`,
or pass `--config-dir` yourself:

```bash
mpv --config-dir=~/.config/mpv "path/to/video.mkv"
```

```powershell
mpv --config-dir="$env:APPDATA\mpv" "%USERPROFILE%\Videos\something.mkv"
```

## Offline install

The repository contains everything except mpv, yt-dlp and the optional
binaries below, so a clone on a connected machine is a complete offline
payload.

1. On a machine with internet:

   ```bash
   git clone https://github.com/ratuuul/mpv-redesigned.git
   curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
       -o ./mpv-redesigned/yt-dlp
   chmod +x ./mpv-redesigned/yt-dlp
   ```

   ```powershell
   git clone https://github.com/ratuuul/mpv-redesigned.git
   Invoke-WebRequest https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe `
       -OutFile .\mpv-redesigned\yt-dlp.exe -UseBasicParsing
   ```

2. Copy the `mpv-redesigned` folder to the target machine (USB, network share).
3. Install mpv there (package manager, or an unpacked shinchiro build on `PATH`).
4. Deploy without network access:

   ```bash
   bash install.sh --config-dir ~/.config/mpv --force --no-yt-dlp --no-fonts
   ```

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigOnly -Force
   Copy-Item .\yt-dlp.exe "$env:APPDATA\mpv\yt-dlp.exe"
   ```

`--no-yt-dlp` / `-ConfigOnly` never touch the network. YouTube playback
without `yt-dlp` simply fails to resolve URLs; everything local still works.

## What gets installed and where

The `config/` payload is copied into the configuration directory, minus
runtime state (`mpv.log`, `recent.json`, `cache/`, `watch_later/`,
`screenshots/`, `subs/`, `subtitles/`, `temp/`, `state/`), which is never
deployed:

```
~/.config/mpv\                        (Linux / macOS)
%APPDATA%\mpv\                        (Windows)
  mpv.conf              master file, includes conf/*
  input.conf            key bindings
  conf\
    video.conf          renderer, hardware decode, scaling, colour
    audio.conf          output, volume, ReplayGain, track selection
    subtitles.conf      font, colours, borders, margins
    interface.conf      window chrome, OSD, screenshots
    profiles.conf       conditional + on-demand profiles
  scripts\
    uosc\             Liquid Glass OSC (uosc fork) - ACTIVE by default
    modernz\            ModernZ OSC (when it is the active skin)
    nav_shim.lua        skin-aware navigation
    ytsubs.lua          YouTube subtitle picker
    thumbfast.lua       seekbar thumbnail previews
    quality-menu.lua    real YouTube / DASH format picker
    sponsorblock_minimal.lua
    recentmenu.lua      recent-files menu
    webm.lua            clip cutter
    autosubs.lua        automatic OpenSubtitles lookup for local files
    download.lua        download the stream you are watching
    pip.lua             mini always-on-top player
    bg.lua              idle photo background
  script-opts\          per-script options
  skins\
    modernz\            ModernZ (parked - becomes scripts\modernz when active)
    liquid-glass\uosc\  Liquid Glass (parked when ModernZ is active)
  fonts\                Geist, Inter, Source Sans 3, Material Icons, modernz-icons
  shaders\              Anime4K Restore + CfL
  yt-dlp                YouTube / streaming support (yt-dlp.exe on Windows)
  switch-skin.cmd       Windows skin switcher (inside the config dir)
  switch-skin.ps1       Windows skin switcher (inside the config dir)
  cache\                shader cache (created empty)
  state\                mpv state directory (created empty)
  watch_later\          resume points (created empty)
  screenshots\          screenshots (created empty)
  subs\                 downloaded subtitles (created empty)
  subtitles\            subtitle downloader target (created empty)
  temp\                 temporary files (created empty)
```

The `subtitles/` folder is not optional: the uosc skin probes its download
folder by writing a file into it, and if the folder is missing it logs
`open_subtitle_downloader: subtitles_directory not writable` and refuses to
open the subtitle downloader at all.

Nothing in the payload hardcodes a machine path. Every path is relative or
starts with `~~/`, which mpv expands to the configuration directory, so the
whole tree can be moved or copied to another machine unchanged.

Note: `script-opts/download.conf` defaults to `download_dir=~/Videos/mpv-downloads`.
On Windows `~` resolves to `%USERPROFILE%` (the user profile, so downloads land
in `Videos\mpv-downloads` under it); on Linux / macOS it resolves to
`$HOME/Videos/mpv-downloads`. Change it in `script-opts/download.conf` if you
want downloads elsewhere.

## Flags

`install.sh` (Linux / macOS):

| Flag | Effect |
|---|---|
| `--help` | Show usage and exit. |
| `--version` | Print the version and exit. |
| `--uninstall` | Run `uninstall.sh` instead of installing. |
| `--dry-run` | Print every action, change nothing. No files, no directories, no prompts, no verification run. |
| `--force` | Replace an existing configuration without asking. |
| `--config-dir <path>` | Deploy somewhere other than the default (`$MPV_CONFIG_DIR` → `$XDG_CONFIG_HOME/mpv` → `~/.config/mpv`). |
| `--backup-dir <path>` | Put the timestamped backup in this directory (default: next to the configuration directory). |
| `--no-backup` | Do not keep a backup. The existing configuration is removed. Destructive. |
| `--no-history` | Do not carry `watch_later/` and `screenshots/` over from the configuration being replaced. |
| `--no-yt-dlp` | Skip the yt-dlp download. |
| `--no-fonts` | Skip installing the fonts. |
| `--skin <liquidglass\|modernz>` | Activate this skin (default: liquidglass). |

A safe dry run:

```bash
bash install.sh --dry-run --no-yt-dlp --no-fonts
```

A real run into a scratch directory, for testing without touching your own
configuration:

```bash
bash install.sh --config-dir "$HOME/.config/mpv-test" --force --no-yt-dlp --no-fonts
```

The scratch directory is left in place, so you can compare it with your real
configuration or remove it yourself.

`install.ps1` (Windows):

| Flag | Effect |
|---|---|
| `-DryRun` | Print every action, change nothing. |
| `-ConfigOnly` | Skip mpv and yt-dlp. Deploy the configuration only. |
| `-InstallDir <path>` | Deploy somewhere other than `%APPDATA%\mpv` (useful for testing). |
| `-Force` | Do not ask before replacing an existing configuration. |
| `-NoBackup` | Do not back up the existing configuration. Destructive. |
| `-NoHistory` | Do not carry over `watch_later\` and `screenshots\`. |

## Skin switching

Two skins are installed; exactly one is active at a time. The active skin
lives in `scripts/` (mpv only adds a script's own directory to the Lua module
path from there), and the inactive one is parked in `skins/`.

| | Liquid Glass (default) | ModernZ |
|---|---|---|
| Upstream | uosc v5.9.2 fork | Samillion/ModernZ (LGPL-2.1, actively maintained) |
| Look | macOS-style glass, centred overlays, speedometer | glassmorphic blur, hairline accent seekbar, chapter nibbles |
| Menus | uosc menus | full (playlist/subtitles/chapters/audio/devices) |

### Linux / macOS

From a clone, the switcher lives in the repository's `scripts/` directory:

```bash
scripts/switch-skin.sh            # interactive menu
scripts/switch-skin.sh liquidglass
scripts/switch-skin.sh modernz
```

### Windows

The switcher is shipped inside the config directory:

```powershell
.\switch-skin.cmd                 # (inside %APPDATA%\mpv)
.\switch-skin.cmd liquidglass
.\switch-skin.cmd modernz
```

Restart mpv afterwards. `scripts/nav_shim.lua` detects the active skin at
runtime, so the same key bindings work with either skin.

> **Why the switcher moves folders instead of just pointing at another file:**
> mpv only puts a script's own directory on the Lua module path when the
> script lives in `scripts/`. The Liquid Glass skin needs
> `require('lib/std')` and friends, so if it sits anywhere else it **crashes
> on load with "module 'lib/std' not found"** and the player ends up with
> no controls at all. The active skin therefore lives in `scripts/` and the
> inactive one is parked in `skins/`.

## yt-dlp setup

yt-dlp is downloaded from the official release
(https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp) into the
configuration directory as `yt-dlp` (Linux / macOS) or `yt-dlp.exe`
(Windows), with the executable bit set, so mpv's `ytdl_hook` finds it first.
Skipped with `--no-yt-dlp` / `-ConfigOnly`.

The single `yt-dlp` executable runs on x86_64, aarch64 and armv7l; no
architecture-specific build is needed.

Without yt-dlp, YouTube and other network URLs fail to resolve; local files
still play normally.

## Fonts

Fonts are installed into `fonts/` inside the configuration directory and are
loaded by mpv automatically — they are **not** installed system-wide.
Skipped with `--no-fonts`. See config/README.md for the full font list and
licences.

## Verification

When `mpv` is on `PATH`, the installer runs

```bash
mpv --config-dir=<dir> --no-terminal --list-options
```

and checks the output for parse errors (`[e]`, `Error parsing option`,
`Invalid value`, `Lua error`). A clean parse prints `OK Configuration parsed
cleanly`; otherwise the installer prints the log path and exits non-zero.

## Uninstall and rollback

### Linux / macOS

```bash
bash uninstall.sh                    # move the config dir to a timestamped
                                     # backup next to it
bash uninstall.sh --restore <backup> # roll back from a backup
bash uninstall.sh --keep-config      # leave the configuration untouched
bash uninstall.sh --dry-run          # print what would happen
bash uninstall.sh --yes              # skip the confirmation prompt
```

By default the configuration directory is **moved** (not copied) to
`<dir>-backup-YYYYMMDD-HHMMSS` next to it, so nothing is lost. If mpv is
running against the default config dir, the uninstaller refuses until you
close it.

### Windows

```powershell
.\uninstall.ps1      # move %APPDATA%\mpv to a timestamped backup
.\uninstall.ps1 -Purge  # delete it permanently
```

## Troubleshooting

**"mpv is running. Close it and run the installer again."**
Correct behaviour. Close every mpv window, including mini players, and retry.
This check only applies to the default configuration directory.

**"Could not find a suitable mpv release asset."** (Windows)
The release API answered but no plain build was in the latest release.
Install mpv manually and re-run with `-ConfigOnly` / `--no-yt-dlp --no-fonts`.

**"Could not locate the config folder inside the downloaded archive."**
The GitHub archive download was truncated. Retry, or clone instead.

**TLS errors**
Older system TLS stacks sometimes negotiate an outdated version. Download
`https://github.com/ratuuul/mpv-redesigned/archive/refs/heads/main.tar.gz`
in a browser, extract it, and run the installer from the extracted folder.

**"FAIL The configuration produced problems"**
The log path is printed. Open it and look for the first `[e]` line — that is
the real error; the rest are usually consequences. Most parse errors are a
hand-edited `mpv.conf` value or a `ytdl-raw-options` entry without `=value`.
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**mpv missing on PATH**
The installer prints a per-distro hint (e.g. `sudo apt install mpv` on
Debian/Ubuntu, `brew install mpv` on macOS) and continues. Install mpv, then
re-run the installer with `--force` / `-Force` to run the parse check.

**yt-dlp download fails**
Proxy or firewall. Download
https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp
manually and place it (as `yt-dlp`, executable) in the configuration
directory, or re-run with `--no-yt-dlp`.

## Node.js and YouTube quality

Without a JavaScript runtime, modern yt-dlp cannot solve YouTube's signature
and `n` challenges. YouTube then forces SABR streaming and the format list
comes back empty or truncated. The shipped configuration therefore contains
`js-runtimes=node`.

```bash
# Debian/Ubuntu
sudo apt install nodejs
# macOS
brew install node
# then, in a NEW terminal:
node --version
```

Confirm the runtime is visible to yt-dlp:

```bash
yt-dlp -v --simulate "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1 |
    grep -E 'JS runtimes|nsig|SABR'
```

You want a line naming `node`. If Node cannot be installed, comment the
option out — YouTube still plays, just at the lower pre-merged qualities:

```ini
# ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node
```

## Optional: age-restricted videos

Age-gated, members-only and "confirm you're not a bot" videos need cookies from
a browser you are signed into. The shipped configuration deliberately does not
do this, because pointing yt-dlp at a browser profile that does not exist makes
it abort and **all** YouTube playback stops.

If you want it, edit `mpv.conf` and append one entry to the existing
`ytdl-raw-options` line (keep it on one line, no commas inside values):

```ini
ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node,cookies-from-browser=firefox
```

`firefox` is the reliable choice: Chrome, Edge and Chromium keep their cookie
database app-bound encrypted and yt-dlp fails with "Failed to decrypt with
DPAPI". Firefox may stay open while you play.

Verify that the profile exists before you rely on it:

```bash
yt-dlp --cookies-from-browser firefox --simulate "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

If that prints "could not find firefox cookies database", remove the option
again.

## Security and privacy

- The installer downloads code over HTTPS from
  https://github.com/ratuuul/mpv-redesigned only. Inspect `install.sh` /
  `install.ps1` before piping them into `bash` / `iex` if you prefer.
- Nothing is installed system-wide; the scripts never use `sudo`.
- yt-dlp is an unsigned binary from its official upstream; the uosc skin
  bundles `ziggy-windows.exe` (Windows only). See
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for bundled components.
- Runtime state (`mpv.log`, `recent.json`, watch history, screenshots, cache)
  is never deployed, so the installer cannot leak a machine's state or
  overwrite your own history on a re-install.
- Backups are timestamped and never overwrite an existing backup.
