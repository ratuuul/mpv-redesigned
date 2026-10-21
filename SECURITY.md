# Security policy

## Supported versions

The configuration is versioned together with the repository. The current
release is supported.

| Version | Supported |
|---|---|
| 1.0.x (current) | yes |
| older releases | no - upgrade to the current release |

mpv itself is supported as far as the configuration requires: mpv 0.37 or
newer. Older versions do not know several of the options used here and will log
parse errors.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Use GitHub's private reporting instead:

1. Open the repository on GitHub.
2. Go to **Security** → **Advisories** → **Report a vulnerability**.
3. Describe the problem in as much detail as you can: what the issue is, how to
   reproduce it, and what an attacker gains from it.

If private advisories are not enabled for this repository, contact the
maintainer through their GitHub profile and ask for a private channel.

You can expect an acknowledgement within a few days. Once the report is
confirmed, a fix is prepared, released and published as an advisory, and the
reporter is credited unless they prefer otherwise.

## What is in scope

- A flaw in the installer that writes outside the configuration directory, that
  runs an unverified download, or that destroys a file it should not touch.
- A flaw that lets a remote source (a photograph, a subtitle file, a stream
  manifest) execute code or write outside its cache directory.
- A path traversal in one of the bundled scripts.
- A credential, a token or a private path that is published in the repository.

## What is out of scope

- mpv itself, yt-dlp, uosc, ModernZ and the other upstream projects. Report
  those to their own maintainers.
- Sites that break the configuration in an unusual way. Those are bugs, and
  they belong in the issue tracker.
- The background photograph service being unavailable.
- Missing features and general configuration complaints.

## What this configuration does at runtime

Being explicit about it:

- The **installer** downloads `yt-dlp` from its official release page and
  places it in the configuration directory. The download is not verified with a
  signature; it is fetched over HTTPS from the upstream project.
- The **idle background** (`scripts/bg.lua`) requests a random photograph from a
  public image service and stores it in the configuration cache. Nothing is
  sent except the request itself. It can be switched off completely with
  `enabled=no` in `script-opts/bg.conf`.
- The **subtitle downloader** queries OpenSubtitles through the API key and
  binary that ship with the skin.
- **Nothing else leaves the machine.** There is no telemetry, no analytics, no
  update check and no crash report in this repository.
