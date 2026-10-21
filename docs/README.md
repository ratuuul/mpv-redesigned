# Documentation

The complete documentation for the configuration. Every page is written against
the code in `config/`; if the two disagree, the code is right and the page is a
bug.

| Page | What it covers |
|---|---|
| [INSTALL.md](INSTALL.md) | Installing on Windows and Linux, the flags, the skin switch, verification, rollback and uninstall. |
| [FEATURES.md](FEATURES.md) | Every feature the configuration ships, what it does, how to use it and which file to change. |
| [KEYBINDINGS.md](KEYBINDINGS.md) | The complete key map. Generated from `config/input.conf` and the scripts. |
| [SKINS.md](SKINS.md) | Liquid Glass and ModernZ, how to switch between them, and how to add a third. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the pieces fit: the include graph, the script contract, the skin convention and a typical session. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Symptom, cause and fix for everything that tends to go wrong. |

## Reading order

**New user.** [INSTALL.md](INSTALL.md) → [FEATURES.md](FEATURES.md) →
[KEYBINDINGS.md](KEYBINDINGS.md).

You want the player running first, then a tour of what it can do, then the key
map to print out.

**Power user.** [FEATURES.md](FEATURES.md) → [SKINS.md](SKINS.md) →
[ARCHITECTURE.md](ARCHITECTURE.md).

You already know mpv; you want to know which file to change and why the
configuration is shaped the way it is.

**Contributor.** [CONTRIBUTING.md](../CONTRIBUTING.md) →
[ARCHITECTURE.md](ARCHITECTURE.md) → [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

The validation commands, the repository rules and the failure modes you are
likely to hit.

## Conventions used in these pages

- Paths are relative to the configuration directory. On Windows that is
  `%APPDATA%\mpv`, on Linux and macOS it is `~/.config/mpv`. A path that starts
  with `config/` is relative to the repository.
- **`**Note:**`** marks something that surprises people or breaks in a specific
  situation.
- **Tune:** tells you which file to edit for the option that was just
  described.
- Inline code is an option, a key or a file name. A fenced block is something
  you can paste.
- Options are written in the exact syntax mpv expects, so a block can be
  copied into a config file unchanged.
- Measurements are labelled as such. Where a number was measured on one
  specific machine, the page says so; where a value is a default, the page
  calls it a default.
