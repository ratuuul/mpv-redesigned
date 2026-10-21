# Install

Two ways in: the script, or by hand. Both end with the same tree of files in
`%APPDATA%\mpv`.

- [The script](#the-script)
- [What the script does, step by step](#what-the-script-does-step-by-step)
- [Manual install](#manual-install)
- [Offline install](#offline-install)
- [Optional: age-restricted videos](#optional-age-restricted-videos)
- [When the installer fails](#when-the-installer-fails)

## The script

### From the internet, nothing cloned

```powershell
irm https://raw.githubusercontent.com/ratuuul/mpv-redesigned/main/install.ps1 | iex
```

### From a clone

```powershell
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`-ExecutionPolicy Bypass` applies to that one process only; it does not change
the machine-wide policy.

### Flags

| Flag | Effect |
|---|---|
| `-DryRun` | Print every action, change nothing. No files, no directories, no prompts, no verification run. |
| `-ConfigOnly` | Skip mpv and yt-dlp. Deploy the configuration only. |
| `-InstallDir <path>` | Deploy somewhere other than `%APPDATA%\mpv` (useful for testing). |
| `-Force` | Do not ask before replacing an existing configuration. |
| `-NoBackup` | Do not back up the existing configuration. Destructive. |
| `-NoHistory` | Do not carry over `watch_later\` and `screenshots\`. |

A dry run that is safe to paste anywhere:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun -ConfigOnly
```

A real run into a scratch directory, for testing without touching your own
configuration:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigOnly -Force -NoBackup `
    -InstallDir "$env:TEMP\mpv-install-test"
```

### Prerequisites

| | |
|---|---|
| Windows 10 or 11, x86-64 | The PowerShell script itself refuses to run elsewhere. |
| Windows PowerShell 5.1 | Present on every Windows 10/11. PowerShell 7 also works. |
| ~60 MB free | About 10 MB of configuration, the rest for the shader cache built on first play and for the backup. |
| Internet, unless offline | For mpv (if missing), yt-dlp and, in the `irm` mode, the archive itself. |

**Node.js** is not required to install, but it is required for full-quality
YouTube. The installer prints a hint when `node` is not on `PATH`; it will not
install Node for you. See [Node.js](#nodejs-and-youtube-quality) below.

No administrator rights: everything goes to your user profile.

## What the script does, step by step

1. **Locate the payload.**
   If the script sits next to a `config\` folder (a clone), that is used.
   Otherwise — the `irm | iex` case, where there is no script file on disk — it
   downloads `main.zip` from GitHub into `%TEMP%\mpv-redesigned-<random>` and
   unpacks it there. Nothing is left behind in the working directory.

2. **Find mpv.**
   Looks for `mpv.com` / `mpv` on `PATH`, then `%LOCALAPPDATA%\mpv\mpv.com`.

3. **Install mpv, if missing.**
   - `scoop` present → `scoop install mpv` (keeps mpv updatable via scoop).
   - otherwise → the latest **plain x86_64** release from
     [shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake),
     unpacked to `%LOCALAPPDATA%\mpv`, then that directory is appended to the
     **user** `PATH`.
   - The `-v3` (AVX2) builds are deliberately skipped: they crash on older CPUs.
   - `winget` is deliberately not used: the package id is unstable.

4. **Check for Node.js.**
   Prints a hint if `node` is not on `PATH`; does not install anything. Full
   YouTube quality needs it — see [Node.js and YouTube quality](#nodejs-and-youtube-quality).

5. **Back up an existing configuration.**
   `%APPDATA%\mpv` is *moved* (not copied) to
   `%APPDATA%\mpv-backup-YYYYMMDD-HHMMSS`. If mpv is running, the script stops
   first — moving a locked directory is how you lose state. The check applies to
   the directory being replaced: a `-InstallDir` scratch run is allowed while
   another player is open.

6. **Deploy.**
   Copies `config\*` into the install directory, creates `cache\` and
   `screenshots\`, then copies `watch_later\` and `screenshots\` out of the
   backup so resume points and past screenshots survive.

   Runtime state is never deployed. `mpv.log` holds the authoring machine's
   own paths and `recent.json` holds a playback history with local file
   names, so neither is copied; copying them would also overwrite the
   user's own history on a re-install. The same goes for `cache\`,
   `watch_later\`, `screenshots\`, `subs\`, `subtitles\` and `temp\`.

7. **yt-dlp.**
   Downloads `yt-dlp.exe` from the official release into the config directory,
   where mpv's `ytdl_hook` looks first. Skipped with `-ConfigOnly`.

8. **Verify.**
   Starts mpv once with `--config-dir=<install dir> --idle=yes --vo=null
   --ao=null --msg-level=all=warn --log-file=<temp>`, waits four seconds, then
   reads the log. `--script-opts=bg-enabled=no` is added for that run only, so
   the idle photo downloader does not hit the network during a verification.
   The check fails on `Error parsing option`, `Invalid value`, `Lua error` or any
   message logged at error level; a clean parse prints
   `OK Configuration parsed cleanly`. If it fails, the installer prints the log
   path and exits non-zero.

## Manual install

No script, no PowerShell execution policy:

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

```powershell
mpv --idle=yes --vo=null --ao=null --msg-level=all=warn --log-file="$env:TEMP\mpv-check.log"
Select-String -Path "$env:TEMP\mpv-check.log" -Pattern 'Error parsing option|Invalid value|\[e\]'
```

No output from `Select-String` means the configuration parsed.

If you install mpv by hand, unzip a build from
[shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake)
or [mpv-player/mpv builds](https://mpv.io/installation/) somewhere on `PATH`,
or pass `--config-dir` yourself:

```powershell
mpv --config-dir="$env:APPDATA\mpv" "%USERPROFILE%\Videos\something.mkv"
```

## Offline install

The repository contains everything except mpv, yt-dlp and the two optional
binaries below, so a clone on a connected machine is a complete offline
payload.

1. On a machine with internet:
   ```powershell
   git clone https://github.com/ratuuul/mpv-redesigned.git
   Invoke-WebRequest https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe `
       -OutFile .\mpv-redesigned\yt-dlp.exe -UseBasicParsing
   ```
2. Copy the `mpv-redesigned` folder to the target machine (USB, network share).
3. Install mpv there (scoop, or an unpacked shinchiro build on `PATH`).
4. Deploy without network access:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigOnly -Force
   Copy-Item .\yt-dlp.exe "$env:APPDATA\mpv\yt-dlp.exe"
   ```

`-ConfigOnly` never touches the network. YouTube playback without `yt-dlp.exe`
simply fails to resolve URLs; everything local still works.

### Mirrored clones

`install.ps1` in `irm` mode always downloads from
`github.com/ratuuul/mpv-redesigned`. If you fork the project, edit that URL in
`Get-RepoRoot` (one line, near the top of the "Locate the payload" section).

## Optional: age-restricted videos

Age-gated, members-only and "confirm you're not a bot" videos need cookies from
a browser you are signed into. The shipped configuration deliberately does not
do this, because pointing yt-dlp at a browser profile that does not exist makes
it abort and **all** YouTube playback stops.

If you want it, edit `%APPDATA%\mpv\mpv.conf` and append one entry to the
existing `ytdl-raw-options` line (keep it on one line, no commas inside values):

```ini
ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node,cookies-from-browser=firefox
```

`firefox` is the reliable choice: Chrome, Edge and Chromium keep their cookie
database app-bound encrypted and yt-dlp fails with "Failed to decrypt with
DPAPI". Firefox may stay open while you play.

Verify that the profile exists before you rely on it:

```powershell
yt-dlp --cookies-from-browser firefox --simulate "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

If that prints "could not find firefox cookies database", remove the option
again.

## Node.js and YouTube quality

Without a JavaScript runtime, modern yt-dlp cannot solve YouTube's signature
and `n` challenges. YouTube then forces SABR streaming and the format list comes
back empty or truncated; playback may stall or fall back to 360p. The shipped
configuration therefore contains `js-runtimes=node`.

```powershell
winget install OpenJS.NodeJS.LTS
# or: scoop install nodejs-lts
# then, in a NEW terminal:
node --version
```

Restart mpv after installing Node. Confirm the runtime is actually visible to
yt-dlp:

```powershell
yt-dlp -v --simulate "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1 |
    Select-String 'JS runtimes|nsig|SABR'
```

You want a line naming `node`. If Node cannot be installed, comment the option
out — YouTube still plays, just at the lower pre-merged qualities:

```ini
# ytdl-raw-options=sub-langs=(en|ja|de|es|fr|it|ru|pt|pl|nl|sv|tr|ko|zh).*,js-runtimes=node
```

## When the installer fails

**"mpv is running. Close it and run the installer again."**
Correct behaviour. Close every mpv window, including mini players, and retry.

**"Could not find a suitable mpv release asset."**
GitHub's release API answered but no plain `mpv-x86_64-*.7z` was in the latest
release. Install mpv manually (above) and re-run with `-ConfigOnly`.

**"Could not locate the config folder inside the downloaded archive."**
The GitHub zip download was truncated, or the branch was renamed. Retry, or
clone instead.

**`Invoke-WebRequest` fails with a TLS error**
Windows PowerShell 5.1 sometimes negotiates TLS 1.0. The script forces TLS 1.2;
if a proxy or antivirus still blocks it, download
`https://github.com/ratuuul/mpv-redesigned/archive/refs/heads/main.zip` in a
browser, extract it, and run `install.ps1` from the extracted folder.

**The archive will not extract and `tar` is missing**
Install 7-Zip, or extract the `.7z` by hand and put `mpv.exe`, `mpv.com` and the
DLLs in `%LOCALAPPDATA%\mpv`.

**"FAIL The configuration produced problems"**
The log path is printed. Open it and look for the first `[e]` line — that is
the real error; the rest are usually consequences. Most parse errors are a
value containing `#` without quotes, or a `ytdl-raw-options` entry without
`=value`. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**PowerShell refuses to run the script**
Either use `powershell -ExecutionPolicy Bypass -File .\install.ps1` (per-process,
no policy change), or unblock the file after downloading it from a browser:

```powershell
Unblock-File .\install.ps1
```

**Antivirus flags the download**
`ziggy-windows.exe` inside the uosc skin and `yt-dlp.exe` are unsigned
executables. Both are vendored/downloaded from their official upstreams; see
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
