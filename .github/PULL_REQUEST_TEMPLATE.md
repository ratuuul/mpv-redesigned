# Pull request

## What this changes

<!-- One or two sentences. The diff shows the how; this says the why. -->

## Why

<!-- The problem this solves. Link the issue it closes, if there is one: -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New option or script
- [ ] Change to an existing option
- [ ] Documentation
- [ ] Installer or tooling
- [ ] Skin or interface

## Checklist

- [ ] `luac5.1 -p` passes for every Lua file I touched
- [ ] Every PowerShell file I touched parses
- [ ] `pwsh -NoProfile -File tools/gen-keybindings.ps1 -Check` passes
      (or I regenerated `docs/KEYBINDINGS.md` because I changed `config/input.conf`)
- [ ] mpv starts against `config/` with no error and no warning
- [ ] The privacy scan is clean: no absolute path, no token, no e-mail address,
      no runtime state, no binary in the diff
- [ ] The documentation that describes this change was updated
- [ ] The commit message explains the reason, not only the diff

## Notes for the reviewer

<!-- Anything that needs a decision, a second opinion, or a machine-specific
     test that the reviewer has to repeat. -->
