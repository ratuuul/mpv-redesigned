# Architecture

Why the configuration is shaped the way it is. This is the "why", not the
"what" — every option itself is explained next to the line that sets it.

- [How mpv loads this configuration](#how-mpv-loads-this-configuration)
- [Why the config is split into conf/*.conf](#why-the-config-is-split-into-confconf)
- [Why the active skin lives in scripts/](#why-the-active-skin-lives-in-scripts)
- [Why nav_shim exists](#why-nav_shim-exists)
- [Why d3d11 and not Vulkan](#why-d3d11-and-not-vulkan)
- [Why the installer moves instead of merging](#why-the-installer-moves-instead-of-merging)
- [Why the generated key binding docs](#why-the-generated-key-binding-docs)

## How mpv loads this configuration

mpv resolves, in order, and stops at the first directory that exists:

1. `--config-dir=...`
2. `%APPDATA%\mpv` (the per-user config on Windows)
3. the directory containing `mpv.exe`

Inside that directory it reads `mpv.conf`, then `input.conf`, then loads every
`*.lua` in `scripts\` and every subdirectory of `scripts\` that contains a
`main.lua`. Options in `script-opts\<script>.conf` are read by the scripts
themselves.

`~~/` in any path expands to the config directory. That is the only reason this
repository can ship a working config without knowing where it will be installed:

```ini
include=~~/conf/video.conf
glsl-shaders=~~/shaders/Anime4K_Restore_CNN_M.glsl
screenshot-template=~~/screenshots/%F-%p%n
gpu-shader-cache-dir=~~/cache/gpu-shaders
```

A hardcoded absolute path into somebody's home directory in a shipped file
would make the repository unusable for anyone else. Nothing under `config/`
contains one: every path is either relative to mpv's `~~/` (the config
directory) or built from the environment.

### Option precedence

Later wins. The practical order is:

```
command line  >  --profile=  >  mpv.conf  >  include= (in include order)  >  mpv defaults
```

`conf/video.conf` is included first, `conf/profiles.conf` last, so a profile can
override anything above it. `apply-profile` at runtime applies on top of
everything.

`--config-dir` relocates `~~/`, which is what makes the installer's verification
run and the scratch-directory test possible without touching a real
installation. It does **not** relocate the runtime state: since mpv 0.37 that
lives in its own state directory (`%LOCALAPPDATA%\mpv` on Windows,
`~/.local/state/mpv` on Linux), so `cache/`, `watch_later/` and
`watch_history.jsonl` stay where they are no matter where the configuration is
installed.

## Why the config is split into conf/*.conf

`mpv.conf` is a bit over a hundred lines of comments-plus-settings; a single
file covering video, audio, subtitles, the interface and profiles would be
roughly 600 lines with five unrelated `# ====` banners in it. Splitting it:

- **gives each concern one obvious file to edit.** "Subtitles are too big" →
  `conf/subtitles.conf`. No scrolling through renderer options to find
  `sub-font-size`.
- **keeps the includes ordered and explicit.** `mpv.conf` is a table of
  contents; you can see the whole load order in seven lines.
- **keeps `mpv.conf` readable as the place for things that do not fit a
  category** — YouTube options, resume behaviour, logging, playlist handling.
- **makes profiles a separate concept** rather than a section at the bottom.
  `conf/profiles.conf` holds two kinds of thing: `profile-cond` profiles that
  mpv evaluates automatically, and manual profiles applied with
  `apply-profile`.

What it deliberately does **not** do is spread a single feature across files.
Every `ytdl-*` option is in `mpv.conf`; every `sub-*` option is in
`conf/subtitles.conf`; every `deband-*` option is in `conf/video.conf`.

`include=` is not conditional. Every included file must exist — a missing
include is a startup error, which is why the repository ships all five.

## Why the active skin lives in scripts/

mpv adds a script's **own directory** to the Lua module search path, and only
when the script is inside `scripts\`. Liquid Glass is a uosc fork, and uosc is
built out of modules:

```lua
local std = require('lib/std')
local Controls = require('elements/Controls')
```

If the fork is loaded from anywhere else — `script=~~/skins/liquid-glass/uosc.lua`,
a `--script=` flag pointing outside the config, anything — those `require`
calls fail with:

```
Lua error: .../uosc.lua:20: module 'lib/std' not found
```

and mpv ends up with **no controls at all**: no bar, no progress, no menus, just
a video. That failure mode is confusing enough that it has its own entry in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

So there is exactly one rule: **the skin that is active is the one in
`scripts\`**, and the other one is parked in `skins\`. `switch-skin.ps1` moves
directories rather than rewriting a path, because a path cannot make mpv put the
skin on the module path. More in [SKINS.md](SKINS.md).

The same mechanism is why every other script in `scripts\` is a **single file**:
none of them needs modules, so none of them needs a directory. Only `uosc` is a
tree.

## Why nav_shim exists

Two skins, one keymap. The obvious approach — bind keys to uosc commands and
ignore ModernZ — breaks the moment you switch skins: uosc's
`script-binding uosc/...` targets do not exist under ModernZ, and mpv prints an
error for every keypress.

The other obvious approach — bind keys to native mpv commands — works
everywhere but throws away Liquid Glass's centred overlays, which are the point
of the skin.

`scripts/nav_shim.lua` takes the third option: **detect, then dispatch.**

Detection is explicit, not guessed. The Liquid Glass skin sets a user property
when it loads:

```lua
mp.set_property_native('user-data/skin/liquidglass', true)
```

`nav_shim` reads that property (and probes once at startup, in case the shim
loaded first). If it is true, the message is forwarded to the skin:

```
script-message-to nav_shim nav-seek 5
  → Liquid Glass:  script-message lg-seek 5      (centred overlay + spring)
  → otherwise:     seek 5                        (ModernZ draws its own OSD)
```

The result is that `input.conf` contains no skin-specific bindings for
navigation at all. It only ever says:

```ini
LEFT   repeatable script-message-to nav_shim nav-seek -5
UP     repeatable script-message-to nav_shim nav-volume 5
{      script-message-to nav_shim nav-speed 1
```

Adding a third skin means adding one branch in one file, not rewriting the
keymap.

The shim is also where per-action policy lives: how much a wheel notch seeks,
whether the speed change is clamped, whether the OSD is suppressed because the
skin is already drawing feedback. That policy has to live in one place or the
two skins drift apart.

## Why the idle background and the double-click are separate scripts

`bg.lua` and `lasthit.lua` both look at "what was played last", and they still
belong in two files.

`bg.lua` **writes** the history: every photograph it fetches is loaded through
`loadfile`, so it ends up in mpv's watch history and in `recent.json` like any
other file. `lasthit.lua` **reads** the history to find the last real media.
If they shared a file, the reader would have to know about the writer's own
entries, and the "is this a background photograph?" rule would live in the same
place as the resume logic.

Split, the rule is one predicate in one place:

```lua
local function is_background(path, title)
    local p = path:gsub('\\', '/'):lower()
    if p:find('/cache/bg/', 1, true) then return true end
    if title and tostring(title):lower() == 'background' then return true end
    return false
end
```

The same split keeps the failure modes apart. `bg.lua` needs the network and
can fail without breaking anything; `lasthit.lua` needs the state directory and
must never prevent mpv from starting. Two scripts, two failure domains.

## Why the state directory is not the config directory

mpv splits the configuration from the state:

| | Windows | Linux |
|---|---|---|
| configuration | `%APPDATA%\mpv` | `~/.config/mpv` |
| state | `%LOCALAPPDATA%\mpv` | `~/.local/state/mpv` |

The state directory holds `cache/`, `watch_later/` and `watch_history.jsonl` -
everything that changes on every run. Keeping it out of the configuration
directory means the configuration can be copied, versioned, reinstalled or
deleted without touching the resume points or the photo cache.

Two consequences the configuration depends on:

- `lasthit.lua` reads the watch-later store from the **state** directory, not
  from the configuration directory.
- `resume-playback-check-mtime=no` is set, because a remote file has no
  modification time and the check would silently discard the saved position
  for every HTTP stream.

The installer still carries an old `watch_later/` across from a backup, for
configurations that were created before mpv made this split.

## Why d3d11 and not Vulkan

Both were benchmarked on the reference machine (Windows 10, Intel iGPU, 1920×1200):

| | d3d11 | Vulkan |
|---|---|---|
| 1080p decode | 0 dropped frames | 0 dropped frames |
| 4K decode | 0 dropped frames | 0 dropped frames |
| Rendered output | **pixel-identical** to Vulkan (PSNR 66.5 dB) | identical |
| `d3d11va-zero-copy` | yes | n/a |
| Driver maturity on Intel | best-supported Windows path | works, less exercised |

Picture quality is not the deciding factor — the output is the same. The
decision is:

1. **Zero-copy decode only exists on the d3d11 path.** On shared-memory Intel
   graphics, skipping the extra GPU→GPU copy is the single biggest performance
   win available, and it is free.
2. **Driver maturity.** Intel's D3D11 driver is the path Windows itself uses for
   video; the Vulkan driver is less exercised and has historically had
   presentation quirks.
3. **Reversibility.** Vulkan is one keypress (`Alt+0`, the `gpu-vulkan`
   profile) or one command line flag (`--profile=gpu-vulkan`) away, so choosing
   d3d11 as the default costs nothing.

The `max-quality`, `cine` and `fast` profiles exist for the same reason: the
full stack was measured to fit on this iGPU, but the escape hatch should be one
keypress, not an edit.

## Why the installer moves instead of merging

`install.ps1` renames an existing `%APPDATA%\mpv` to
`%APPDATA%\mpv-backup-<timestamp>` instead of copying over it.

A merge leaves files behind that this configuration does not use — an old
`scripts\modernz\` next to a new `scripts\uosc\`, a stale `script-opts` entry
referring to a script that no longer exists, a `fonts\` directory full of
whatever was installed before. Skins are directories, so a merge produces two
active skins and two control bars. The failure is silent and looks like a skin
bug.

Moving is atomic, reversible, and makes the deployed tree exactly the tree in
`config/` — which is what the scratch-directory test in the release process
verifies.

Two things are then copied **out of** the backup on purpose:

- `watch_later\` — resume points. Losing them on upgrade is the fastest way to
  make an installer feel hostile.
- `screenshots\` — user content, not configuration.

Everything else stays in the backup until you delete it.

mpv writes `watch_later\`, `cache\` and `watch_history.jsonl` under
`%LOCALAPPDATA%\mpv` rather than `%APPDATA%\mpv` on Windows (mpv's "state"
directory), so moving the config directory does not actually lose resume
positions — the carry-over is belt and braces for configurations that were set
up before that split, and for anyone who moved the state directory.

## Why the generated key binding docs

`docs/KEYBINDINGS.md` is generated by `tools/gen-keybindings.ps1` from
`config/input.conf`, and CI fails if the committed file differs from what the
generator produces.

Hand-written key tables drift within a week: someone rebinds `W`, the table
still says `W`, and the documentation is now actively misleading. Generating it
means the table is either correct or CI is red.

The generator also scans `config/scripts/*.lua` for literal
`mp.add_key_binding('key', 'name', ...)` calls, so keys that a script claims for
itself (`b`, `W`, `Ctrl+d`, `Alt+p`, `Alt+o`) appear in the reference even though
they are not in `input.conf`. A three-entry static table covers the one script
that binds a key through an option default.

Descriptions come from the comment line directly above each binding in
`input.conf`, which means the docs improve whenever the config comments do.
