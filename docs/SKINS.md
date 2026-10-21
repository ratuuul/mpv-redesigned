# Skins

Two skins are installed. Exactly one is active at a time.

| | Liquid Glass | ModernZ |
|---|---|---|
| Default | **yes** | no, parked |
| Location when active | `scripts\uosc\` | `scripts\modernz\` |
| Location when parked | `skins\liquid-glass\uosc\` | `skins\modernz\` |
| Upstream | [tomasklaen/uosc](https://github.com/tomasklaen/uosc) v5.9.2, forked | [Samillion/ModernZ](https://github.com/Samillion/ModernZ) v0.3.3 |
| Licence | LGPL-2.1 | LGPL-2.1 |
| Look | translucent glass, centred macOS-style overlays, spring speedometer | glassmorphic blur, hairline accent seekbar, chapter nibbles |
| Menus | uosc menus | full menus: playlist, subtitles, chapters, audio, devices |
| Options | `script-opts/liquid-glass.conf` + `script-opts/uosc.conf` | `script-opts/modernz.conf` |

Neither is modified beyond the Liquid Glass fork changes listed in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Switching

```powershell
cd $env:APPDATA\mpv
.\switch-skin.cmd                    # interactive menu
.\switch-skin.cmd liquidglass
.\switch-skin.cmd modernz
```

Then **restart mpv**. A skin is Lua code loaded once at startup; the switcher
cannot swap it out from under a running player.

Under the hood `switch-skin.cmd` just calls `switch-skin.ps1` with
`-ExecutionPolicy Bypass` for that one process:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\switch-skin.ps1 modernz
```

The `pause` at the end of the `.cmd` keeps the window open so you can read the
output when you double-click it.

## Why it moves folders instead of pointing at a file

mpv adds **a script's own directory** to the Lua module search path, and only
for scripts inside `scripts\`. Liquid Glass is built from modules:

```lua
require('lib/std')
require('lib/utils')
require('elements/Controls')
```

Loading it from `skins\liquid-glass\uosc\main.lua` via `script=...` gives:

```
Lua error: ...: module 'lib/std' not found
```

and mpv shows a video with **no controls at all** — no bar, no progress, no
menus. The player looks broken rather than misconfigured, which is why the
switcher takes the blunt approach: the active skin is the one under `scripts\`,
always.

ModernZ is a single 195 KB script and does not strictly need this, but moving
both the same way keeps one rule instead of two.

## What the switcher actually does

`switch-skin.ps1` holds a map of *live* and *parked* directory names:

```powershell
$map = @{
    "liquidglass" = @{ live = "uosc";          parked = "liquid-glass\uosc" }
    "modernz"     = @{ live = "modernz";       parked = "modernz" }
}
```

Then, in order:

1. For **every** skin in the map: if its live directory exists under
   `scripts\`, move it to its parked location under `skins\`. This parks
   whatever is currently active, whatever it is.
2. Move the requested skin from `skins\` into `scripts\`.
3. Print what became active and remind you to restart mpv.

Anything that cannot be moved — a file locked by a running mpv, a missing
`skins\` directory — stops the script with a readable error rather than leaving
a half-swapped state.

The script defaults to `%APPDATA%\mpv`. If you installed the configuration
somewhere else with `install.ps1 -InstallDir`, point it at that directory:

```powershell
.\switch-skin.ps1 modernz -ConfigDir "D:\mpv-config"
```

The same directory is used for `scripts\` and `skins\`, so the two folders must
live side by side as they do in a normal install.

## When the switcher appears to do nothing

- **mpv was open.** Restart it.
- **The bar disappeared entirely.** The skin crashed on load. Run
  `mpv --msg-level=all=warn --log-file=%TEMP%\mpv.log` and look for the first
  `Lua error`. A parked-but-not-restored `uosc` folder, or a `lib\` directory
  that did not come along, produces exactly this.
- **Both bars drawn on top of each other.** Two skins are live at once, which
  means a merge-style install or a failed move. Check:

  ```powershell
  Get-ChildItem "$env:APPDATA\mpv\scripts" -Directory
  ```

  Exactly one of `uosc` / `modernz` should be there, plus no stray `lib`,
  `elements`, `intl` folders at the top level of `scripts\`.

## Adding a third skin

1. Park it under `skins\<name>\`.
2. Add one entry to `$map` in `switch-skin.ps1`:
   `"myskin" = @{ live = "myskin"; parked = "myskin" }`.
3. If the skin registers its own key bindings that clash with the keymap,
   handle the dispatch in `scripts/nav_shim.lua` rather than forking
   `input.conf`. See [ARCHITECTURE.md](ARCHITECTURE.md#why-nav_shim-exists).

If the skin is a tree of Lua modules, it **must** be loaded from `scripts\` —
that is the whole reason for the move.
