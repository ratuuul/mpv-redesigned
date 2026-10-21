# Contributing to mpv-redesigned

Thank you for taking the time. This document explains how the repository is
laid out, what a change has to pass before it can be merged, and the rules that
keep the published tree free of anything that belongs to one machine.

## The shape of the repository

```
mpv-redesigned/
  config/            the mpv configuration - this is the product
    mpv.conf         master file, includes everything below
    input.conf       key bindings
    conf/            video, audio, subtitles, interface, profiles
    scripts/         the Lua scripts and the active skin
    script-opts/     one options file per script
    skins/           the parked skins
    shaders/         Anime4K and CfL GLSL
    fonts/           Geist, Inter, Source Sans 3, icon fonts
  docs/              the documentation set
  site/              the GitHub Pages site (static, no build step)
  tools/             repository tooling
  licenses/          the licence texts of every bundled component
  install.ps1        the Windows installer
  install.sh         the Linux and macOS installer
  uninstall.ps1      the Windows uninstaller
  uninstall.sh       the Linux and macOS uninstaller
```

`config/` is a copy of a live mpv configuration. Everything else is written
for the repository itself.

## Setting up

```powershell
git clone https://github.com/ratuuul/mpv-redesigned.git
cd mpv-redesigned
```

You need:

| Tool | Version | Why |
|---|---|---|
| mpv | 0.37 or newer | the player itself |
| LuaJIT / `luac5.1` | 5.1 | mpv embeds LuaJIT 2.1, which is Lua 5.1 |
| PowerShell | 7 or newer | the installer and the tooling |
| yt-dlp | recent | streaming support |
| Node.js | 18 or newer | `js-runtimes=node` for full YouTube quality |

A plain `mpv` and `luac5.1` are enough to run the validation suite. The
installers are optional for development: point mpv at the payload directly.

```powershell
mpv --config-dir="$PWD\config" --idle=yes --vo=null --ao=null
```

## Making a change to the configuration

1. Change it in the live configuration first, or in `config/` directly - both
   work. `tools/sync-config.ps1` merges the live tree back into the repository
   and refuses to commit a configuration that produces an error or a warning.
2. Keep the comments. Every option in `config/` explains why it has the value
   it has; a value without a reason is a value someone will "fix" later.
3. Keep the portable paths. Use mpv's `~~/` for anything inside the
   configuration directory, `%APPDATA%\mpv` or `~/.config/mpv` for the
   configuration directory itself, and never a path that belongs to one
   machine.

## Validation

Run all of these before you open a pull request. The CI runs the same checks.

```powershell
# 1. Every Lua file must parse with Lua 5.1 (the dialect mpv speaks).
luac5.1 -p config/scripts/*.lua
Get-ChildItem -Recurse -Filter *.lua | ForEach-Object { luac5.1 -p $_.FullName }

# 2. Every PowerShell file must parse.
Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
    $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null
    if ($e.Count) { $_.FullName; $e }
}

# 3. The key binding reference must match config/input.conf.
pwsh -NoProfile -File tools/gen-keybindings.ps1 -Check

# 4. mpv must start against the configuration without an error or a warning.
$log = "$env:TEMP\mpv-check.log"
mpv --config-dir="$PWD\config" --idle=yes --vo=null --ao=null "--log-file=$log" --msg-level=all=warn --script-opts=bg-enabled=no
Select-String -Path $log -Pattern '\[e\]|\[f\]|\[w\]|Lua error|Error parsing option'
```

Step 4 must print nothing. A single `unknown key '...', ignoring` line means an
option was renamed in a `script-opts` file without the script being updated.

The same run happens inside `tools/sync-config.ps1`, which also merges the live
tree into `config/`:

```powershell
pwsh -NoProfile -File tools/sync-config.ps1 -Apply -Commit
```

## The privacy rules

The configuration is copied off a real machine, so it is very easy to publish
something that belongs to one person. The CI scans every tracked file and
fails the build on any of these:

- an absolute path into a home directory (a drive letter followed by `Users`,
  or a POSIX `/home/<name>/` style path)
- a token, an API key or a private key
- an e-mail address
- runtime state: `mpv.log`, `recent.json`, `cache/`, `watch_later/`,
  `screenshots/`, `subtitles/`

If a vendored upstream file legitimately contains a path-shaped string, add it
to `.github/privacy-allowlist.txt` **with a reason**. The list is meant to stay
short.

Runtime state never belongs in the repository. Neither do binaries: `yt-dlp` and
the player's own binaries are downloaded by the installer at install time.

## Commit and pull request conventions

- One logical change per commit. A commit that fixes a typo and renames a
  profile cannot be reviewed.
- Write the subject line as an imperative sentence: "Hide the top bar while a
  video plays" rather than "top bar fix".
- Describe *why* in the body. The diff already says what changed.
- Reference the issue the change fixes, if there is one.
- If the change touches `config/input.conf`, regenerate
  `docs/KEYBINDINGS.md` with `tools/gen-keybindings.ps1`. The CI compares the
  two and fails on drift.
- If the change touches the configuration, re-run the four validation steps
  above.

## Pull request checklist

- [ ] `luac5.1 -p` passes for every Lua file
- [ ] every PowerShell file parses
- [ ] `tools/gen-keybindings.ps1 -Check` passes
- [ ] mpv starts against `config/` with no error and no warning
- [ ] the privacy scan is clean
- [ ] the documentation that describes the change was updated
- [ ] no runtime state, no binary and no absolute path in the diff

## Reporting a bug

Open an issue and include:

- the mpv version (`mpv --version`) and the operating system
- the output of `mpv --list-options` for the options involved
- the relevant part of the log: `mpv --log-file=mpv.log --msg-level=all=debug`
- what you expected and what happened instead

Never attach a log that still contains personal paths. Run it through a search
first.

## Code of conduct

Participation in this project is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Licence

The configuration in `config/` is published under the MIT licence. Vendored
components keep their own licence; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
and the `licenses/` folder.
