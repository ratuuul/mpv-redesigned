/* ==========================================================================
   mpv-redesigned - site data
   --------------------------------------------------------------------------
   Single source of truth for everything the page shows about the project:
   the feature grid, the key bindings, the config tree, the installer flags
   and the FAQ all read from this object, so the prose and the interactive
   table can never drift apart.

   No build step, no framework: the file exposes window.MPVR.
   ========================================================================== */
(function (global) {
  'use strict';

  function icon(body) {
    return (
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" ' +
      'aria-hidden="true" focusable="false">' + body + '</svg>'
    );
  }

  var ICONS = {
    glass: icon(
      '<rect x="2.5" y="4" width="19" height="16" rx="3.2"/><path d="M2.5 8.6h19"/><path d="M6.5 12.6h5.5"/><path d="M15 12.6h2.5"/><circle cx="6.5" cy="6.3" r="0.9" fill="currentColor" stroke="none"/>'
    ),
    chip: icon(
      '<rect x="6.5" y="6.5" width="11" height="11" rx="2"/><path d="M10 3.2v3.3M14 3.2v3.3M10 17.5v3.3M14 17.5v3.3M3.2 10h3.3M3.2 14h3.3M17.5 10h3.3M17.5 14h3.3"/>'
    ),
    aperture: icon(
      '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5v8.5l7.4 4.3M12 12 4.6 16.3M12 12l7.4-4.3"/>'
    ),
    sparkle: icon(
      '<path d="M12 3.2 13.9 9l5.8 1.9-5.8 1.9L12 18.6l-1.9-5.8L4.3 10.9 10.1 9 12 3.2Z"/><path d="M18.6 15.4l.8 2.3 2.3.8-2.3.8-.8 2.3-.8-2.3-2.3-.8 2.3-.8.8-2.3Z"/>'
    ),
    frame: icon(
      '<rect x="2.6" y="5" width="18.8" height="14" rx="2.4"/><path d="M7.6 9.6v4.8l4.4-2.4-4.4-2.4Z"/><path d="M14.5 9.8h4M14.5 13h4"/>'
    ),
    wave: icon(
      '<path d="M3 12h1.6M7 7.4v9.2M10.6 4.6v14.8M14.2 8.6v6.8M17.8 6.2v11.6M21 10.4v3.2"/>'
    ),
    captions: icon(
      '<rect x="2.6" y="5.4" width="18.8" height="13.2" rx="2.4"/><path d="M10 10.2a2.2 2.2 0 1 0 0 3.6M17.4 10.2a2.2 2.2 0 1 0 0 3.6"/>'
    ),
    list: icon(
      '<path d="M8.4 6.4h12M8.4 12h12M8.4 17.6h12"/><path d="M3.8 6.4h.1M3.8 12h.1M3.8 17.6h.1"/>'
    ),
    globe: icon(
      '<circle cx="12" cy="12" r="8.6"/><path d="M3.6 12h16.8"/><path d="M12 3.4c2.3 2.4 3.5 5.4 3.5 8.6S14.3 18.2 12 20.6c-2.3-2.4-3.5-5.4-3.5-8.6S9.7 5.8 12 3.4Z"/>'
    ),
    skip: icon(
      '<path d="M4 6.4 13 12l-9 5.6V6.4Z"/><path d="M20 5.4v13.2"/>'
    ),
    scissors: icon(
      '<circle cx="6.4" cy="6.4" r="2.6"/><circle cx="6.4" cy="17.6" r="2.6"/><path d="M8.6 8.2 20 17M20 7 8.6 15.8"/>'
    ),
    photo: icon(
      '<rect x="2.6" y="4.8" width="18.8" height="14.4" rx="2.4"/><circle cx="8.4" cy="9.8" r="1.6"/><path d="M3.4 16.6 8.8 12l4.2 3.6 3-2.4 4.6 3.6"/>'
    ),
    power: icon(
      '<path d="M12 3.4v8.2"/><path d="M7.4 6.6a7.4 7.4 0 1 0 9.2 0"/>'
    ),
    keyboard: icon(
      '<rect x="2.4" y="6" width="19.2" height="12" rx="2.2"/><path d="M6 9.6h.1M9.4 9.6h.1M12.8 9.6h.1M16.2 9.6h.1M6 13h.1M9.4 13h.1M12.8 13h.1M16.2 13h.1M8 16h8"/>'
    ),
    layers: icon(
      '<path d="M12 3.4 21 8l-9 4.6L3 8l9-4.6Z"/><path d="m3 12.4 9 4.6 9-4.6"/><path d="m3 16.6 9 4.6 9-4.6"/>'
    ),
    shield: icon(
      '<path d="M12 3.2 5 5.8v5.4c0 4.2 2.9 7.6 7 9.6 4.1-2 7-5.4 7-9.6V5.8L12 3.2Z"/><path d="m9.2 11.8 2 2 3.6-3.8"/>'
    )
  };

  var DATA = {
    repo: 'https://github.com/ratuuul/mpv-redesigned',
    pages: 'https://ratuuul.github.io/mpv-redesigned/',

    /* ---------------------------------------------------------- numbers -- */
    stats: [
      {
        value: 12,
        title: 'Lua scripts',
        detail: 'Every key binding on the page is one of them'
      },
      {
        value: 10,
        title: 'Runtime profiles',
        detail: 'Alt+1 through Alt+0, applied on the fly'
      },
      {
        value: 5,
        title: 'Config files',
        detail: 'One per domain, included from a master file'
      },
      {
        value: 0,
        title: 'Dropped frames',
        detail: 'Measured at 1920x1200 on the reference machine'
      }
    ],

    /* --------------------------------------------------------- features -- */
    features: [
      {
        icon: ICONS.glass,
        title: 'Liquid Glass skin',
        tag: 'Interface',
        body:
          'A uosc fork that keeps a translucent control bar and timeline on screen while the picture plays, with macOS-style centred seek, volume and speed overlays.'
      },
      {
        icon: ICONS.chip,
        title: 'Zero-copy decode',
        tag: 'Video',
        body:
          'd3d11 output with d3d11va hardware decoding. On an Intel iGPU with shared memory this is the single biggest win available.'
      },
      {
        icon: ICONS.aperture,
        title: 'libplacebo pipeline',
        tag: 'Video',
        body:
          'vo=gpu-next with spline HDR to SDR tone mapping, fruit dither, grain-assisted debanding and correct downscaling.'
      },
      {
        icon: ICONS.sparkle,
        title: 'Anime4K on autopilot',
        tag: 'Video',
        body:
          'Line-art restoration and chroma-from-luma are applied automatically to files whose path contains "anime", with a softer variant below 720p.'
      },
      {
        icon: ICONS.frame,
        title: 'Judderless playback',
        tag: 'Video',
        body:
          'video-sync=display-resample plus interpolation removes 24p to 60 Hz judder, and EWA Lanczos keeps the luma sharp while it does.'
      },
      {
        icon: ICONS.wave,
        title: 'WASAPI audio chain',
        tag: 'Audio',
        body:
          'Shared-mode output named "mpv" in the Windows mixer, ReplayGain on top of the volume curve, scaletempo2 pitch correction and gapless playback.'
      },
      {
        icon: ICONS.captions,
        title: 'Designed subtitles',
        tag: 'Text',
        body:
          'Geist Medium at 40, warm off-white, hairline outline and a soft shadow, with margins that keep captions inside the letterbox of a 2.35:1 film.'
      },
      {
        icon: ICONS.list,
        title: 'Real format picker',
        tag: 'Streaming',
        body:
          'The YouTube menu lists the formats the server actually offers and switches between them without reloading, instead of guessing from a 360p and 720p preset list.'
      },
      {
        icon: ICONS.globe,
        title: 'Every subtitle track',
        tag: 'Streaming',
        body:
          'Creator-uploaded and auto-generated captions in every language the video carries, cached after the first fetch, with a separate secondary track.'
      },
      {
        icon: ICONS.skip,
        title: 'SponsorBlock skipping',
        tag: 'Streaming',
        body:
          'Toggle segment skipping on the fly with a configurable category list, so the sponsor read never interrupts the film.'
      },
      {
        icon: ICONS.scissors,
        title: 'Frame-accurate clip cutter',
        tag: 'Tools',
        body:
          'Cut the current range to H.264 and AAC with a range picker that lands on the frame you picked, not the nearest keyframe.'
      },
      {
        icon: ICONS.photo,
        title: 'Idle photo background',
        tag: 'Interface',
        body:
          'A fetched photograph and a quiet prompt sit behind the window when there is nothing to play, cached locally, and one key moves to the next photo.'
      }
    ],

    /* ------------------------------------------------------ key bindings -- */
    /* Every row below is a real binding: either a line in config/input.conf,
       a binding registered by one of the shipped scripts, or an mpv default
       that the configuration deliberately leaves in place.                  */
    keybindings: [
      { id: 'nav-left', keys: 'Left', action: 'Seek 5 seconds back', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-right', keys: 'Right', action: 'Seek 5 seconds forward', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-shift-left', keys: 'Shift+Left', action: 'Seek 1 second back, frame exact', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-shift-right', keys: 'Shift+Right', action: 'Seek 1 second forward, frame exact', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-ctrl-left', keys: 'Ctrl+Left', action: 'Seek 10 seconds back, frame exact', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-ctrl-right', keys: 'Ctrl+Right', action: 'Seek 10 seconds forward, frame exact', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-wheel', keys: 'Wheel Up / Wheel Down', action: 'Scrub the timeline through the skin', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-comma', keys: ',', action: 'Step one frame back', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-dot', keys: '.', action: 'Step one frame forward', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-pgup', keys: 'PgUp / PgDn', action: 'Seek 60 seconds forward or back', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-percent', keys: '0 - 9', action: 'Jump to 0 %, 10 % ... 90 % of the file (numpad too)', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-volume', keys: 'Up / Down', action: 'Volume up or down by 5', group: 'Navigation', source: 'input.conf' },
      { id: 'nav-reopen', keys: 'MBTN_LEFT_DBL', action: 'Reopen the last played media and resume it at the exact position', group: 'Navigation', source: 'lasthit.lua' },

      { id: 'play-space', keys: 'Space', action: 'Pause and resume', group: 'Playback', source: 'mpv default' },
      { id: 'play-right', keys: 'MBTN_RIGHT', action: 'Pause and resume with the right mouse button', group: 'Playback', source: 'input.conf' },
      { id: 'play-slower', keys: '{', action: 'Step the playback speed down', group: 'Playback', source: 'input.conf' },
      { id: 'play-faster', keys: '}', action: 'Step the playback speed up', group: 'Playback', source: 'input.conf' },
      { id: 'play-reset', keys: 'Backspace', action: 'Reset the playback speed to 1.0x', group: 'Playback', source: 'input.conf' },
      { id: 'play-fullscreen', keys: 'f', action: 'Fullscreen', group: 'Playback', source: 'mpv default' },
      { id: 'play-quit', keys: 'q', action: 'Quit mpv', group: 'Playback', source: 'mpv default' },
      { id: 'play-pip', keys: 'Alt+p', action: 'Mini always-on-top picture-in-picture player that restores the previous window state', group: 'Playback', source: 'pip.lua' },

      { id: 'audio-cycle', keys: 'a', action: 'Cycle the audio track forward', group: 'Audio', source: 'input.conf' },
      { id: 'audio-cycle-back', keys: 'Alt+a', action: 'Cycle the audio track backward', group: 'Audio', source: 'input.conf' },
      { id: 'audio-menu', keys: 'A', action: 'Open the skin audio menu', group: 'Audio', source: 'input.conf' },
      { id: 'audio-delay', keys: '[ / ]', action: 'Shift the audio by 0.1 seconds in either direction', group: 'Audio', source: 'input.conf' },
      { id: 'audio-delay-reset', keys: '\\', action: 'Reset the audio delay', group: 'Audio', source: 'input.conf' },

      { id: 'sub-cycle', keys: 'v', action: 'Cycle the subtitle track', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-menu', keys: 'V', action: 'Open the subtitle menu', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-visibility', keys: 'Alt+v', action: 'Show or hide the subtitle track', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-cycle-back', keys: 'Alt+Shift+v', action: 'Cycle the subtitle track backward', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-delay', keys: 'z / Z', action: 'Shift the subtitles by 0.1 seconds earlier or later', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-delay-reset', keys: 'Ctrl+z', action: 'Reset the subtitle delay', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-position', keys: 'x / X', action: 'Move the subtitles 1 pixel up or down', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-scale', keys: 'r / R', action: 'Scale the subtitles up or down by 0.1', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-size', keys: 'Ctrl+j / Ctrl+J', action: 'Change the subtitle font size by 2', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-add', keys: 'Ctrl+v', action: 'Add a subtitle file from disk', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-add-menu', keys: 'Alt+d', action: 'Open the subtitle file browser', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-download', keys: 'D', action: 'Download subtitles from the online providers', group: 'Subtitles', source: 'input.conf' },
      { id: 'sub-autosubs', keys: 'Alt+o', action: 'Look the title up on OpenSubtitles again', group: 'Subtitles', source: 'autosubs.lua' },

      { id: 'shot-sub', keys: 's', action: 'Screenshot including the subtitles', group: 'Screenshots', source: 'input.conf' },
      { id: 'shot-video', keys: 'S', action: 'Screenshot of the video only', group: 'Screenshots', source: 'input.conf' },
      { id: 'shot-video-ctrl', keys: 'Ctrl+s', action: 'Screenshot of the video only', group: 'Screenshots', source: 'input.conf' },

      { id: 'yt-video-formats', keys: 'F', action: 'YouTube video format picker with the real server format list', group: 'YouTube', source: 'input.conf' },
      { id: 'yt-audio-formats', keys: 'Alt+f', action: 'YouTube audio format picker', group: 'YouTube', source: 'input.conf' },
      { id: 'yt-reload', keys: 'Ctrl+r', action: 'Reload the stream and resume where it was', group: 'YouTube', source: 'input.conf' },
      { id: 'yt-subs', keys: 'Alt+s', action: 'YouTube subtitle picker with every offered language', group: 'YouTube', source: 'input.conf' },
      { id: 'yt-subs-secondary', keys: 'Alt+Shift+s', action: 'YouTube subtitle picker for the secondary track', group: 'YouTube', source: 'input.conf' },
      { id: 'yt-sponsorblock', keys: 'b', action: 'Toggle SponsorBlock segment skipping', group: 'YouTube', source: 'sponsorblock_minimal.lua' },
      { id: 'yt-clip', keys: 'W', action: 'Cut a clip with a frame-accurate range picker', group: 'YouTube', source: 'webm.lua' },
      { id: 'yt-download', keys: 'Ctrl+d', action: 'Download the stream you are watching at the negotiated quality', group: 'YouTube', source: 'download.lua' },
      { id: 'yt-download-cancel', keys: 'Ctrl+Shift+d', action: 'Cancel a running download', group: 'YouTube', source: 'download.lua' },

      { id: 'prof-fast', keys: 'Alt+1', action: 'Profile: fast', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-max', keys: 'Alt+2', action: 'Profile: max-quality', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-cine', keys: 'Alt+3', action: 'Profile: cine', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-shaders', keys: 'Alt+4', action: 'Profile: shaders-anime', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-shaders-off', keys: 'Alt+5', action: 'Profile: shaders-off', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-subs-panel', keys: 'Alt+6', action: 'Profile: subs-panel (translucent Netflix style panel)', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-subs-cinema', keys: 'Alt+7', action: 'Profile: subs-cinema (shadow only cinema subtitles)', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-loudnorm', keys: 'Alt+8', action: 'Profile: loudnorm (EBU R128 normalisation)', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-dynaudnorm', keys: 'Alt+9', action: 'Profile: dynaudnorm (dynamic normalisation)', group: 'Profiles', source: 'input.conf' },
      { id: 'prof-vulkan', keys: 'Alt+0', action: 'Profile: gpu-vulkan, to A/B the Vulkan output', group: 'Profiles', source: 'input.conf' },

      { id: 'menu-context', keys: 'Shift+MBTN_RIGHT', action: 'Open the mpv context menu', group: 'Menus', source: 'input.conf' },
      { id: 'menu-history', keys: 'g-h', action: 'mpv menu: playback history', group: 'Menus', source: 'mpv default' },
      { id: 'menu-watch-later', keys: 'g-w', action: 'mpv menu: watch later', group: 'Menus', source: 'mpv default' },
      { id: 'menu-bindings', keys: 'g-b', action: 'mpv menu: key bindings', group: 'Menus', source: 'mpv default' },
      { id: 'menu-main', keys: 'g-m', action: 'mpv menu: main menu', group: 'Menus', source: 'mpv default' },
      { id: 'menu-recent', keys: 'Ctrl+Shift+r', action: 'Open the recent files menu', group: 'Menus', source: 'input.conf' },
      { id: 'menu-theme', keys: 'Ctrl+t', action: 'Toggle the Liquid Glass theme', group: 'Menus', source: 'uosc fork' },
      { id: 'menu-photo', keys: 'Ctrl+Shift+K', action: 'Fetch the next idle background photo', group: 'Menus', source: 'input.conf' }
    ],

    /* ------------------------------------------------------ config tree -- */
    configTree: [
      { tree: 'config/', note: 'Everything below this folder is deployed to the mpv config directory.' },
      { tree: '  mpv.conf', note: 'Master file. Includes the five conf files and owns the yt-dlp options.' },
      { tree: '  input.conf', note: 'Every key binding, in one keymap that works with both skins.' },
      { tree: '  conf/', note: 'One file per domain, so a setting has exactly one home.' },
      { tree: '    video.conf', note: 'Renderer, hardware decode, scaling, tone mapping, colour.' },
      { tree: '    audio.conf', note: 'WASAPI output, volume curve, ReplayGain, track selection.' },
      { tree: '    subtitles.conf', note: 'Font, colours, borders, margins, ASS overrides.' },
      { tree: '    interface.conf', note: 'Window chrome, OSD, screenshots, input defaults.' },
      { tree: '    profiles.conf', note: 'Conditional profiles plus the ten on-demand ones.' },
      { tree: '  scripts/', note: 'The active skin and the twelve Lua scripts that extend the player.' },
      { tree: '    uosc/', note: 'Liquid Glass, a uosc fork. The active skin.' },
      { tree: '    nav_shim.lua', note: 'One keymap, both skins: it detects which skin is running.' },
      { tree: '    quality-menu.lua', note: 'The real format picker, driven by the F and Alt+f keys.' },
      { tree: '    ytsubs.lua', note: 'Subtitle picker for every language a video carries.' },
      { tree: '    bg.lua', note: 'Idle photo background, cached locally.' },
      { tree: '    webm.lua', note: 'Clip cutter for the W key.' },
      { tree: '  script-opts/', note: 'Per-script options, one file per script.' },
      { tree: '  shaders/', note: 'Anime4K and the chroma-from-luma companion.' },
      { tree: '  fonts/', note: 'Geist, Inter, Source Sans 3 and Material Icons.' },
      { tree: '  skins/modernz/', note: 'The parked alternative skin. switch-skin.cmd moves it in.' }
    ],

    /* ----------------------------------------------------- install flags -- */
    installFlags: [
      {
        flag: '--help',
        switch: 'Get-Help .\\install.ps1',
        body: 'Comment-based help for every switch, the default install directory and two worked examples.'
      },
      {
        flag: '--version',
        switch: '—',
        body: 'Print the version and exit.'
      },
      {
        flag: '--dry-run',
        switch: '-DryRun',
        body: 'Prints every planned download, backup and copy, then writes nothing at all.'
      },
      {
        flag: '--force',
        switch: '-Force',
        body: 'Deploy over an existing configuration without stopping to ask.'
      },
      {
        flag: '--config-dir <path>',
        switch: '-InstallDir <path>',
        body: 'Target directory. The configuration home on Linux, the roaming application data on Windows.'
      },
      {
        flag: '--backup-dir <path>',
        switch: '—',
        body: 'Where the timestamped backup goes. Windows always keeps it next to the install directory.'
      },
      {
        flag: '--no-backup',
        switch: '-NoBackup',
        body: 'Remove the existing configuration instead of moving it aside. Destructive.'
      },
      {
        flag: '--no-history',
        switch: '-NoHistory',
        body: 'Do not carry watch_later and screenshots over from the configuration being replaced.'
      },
      {
        flag: '--no-yt-dlp',
        switch: '-ConfigOnly',
        body: 'Skip the yt-dlp download. On Windows -ConfigOnly also skips the mpv download.'
      },
      {
        flag: '--no-fonts',
        switch: '—',
        body: 'Skip installing the fonts. On Windows they ship inside the configuration tree and follow the copy.'
      },
      {
        flag: '--skin <name>',
        switch: 'switch-skin.ps1 -Skin <name>',
        body: 'Swap the active skin between Liquid Glass and ModernZ without touching the rest of the configuration.'
      },
      {
        flag: '--uninstall',
        switch: 'uninstall.ps1',
        body: 'Run the uninstaller instead of the installer. The configuration is moved aside, never deleted.'
      }
    ],

    /* -------------------------------------------------------------- faq -- */
    faq: [
      {
        q: 'Where does the configuration live?',
        a: 'On Windows it is deployed to the mpv folder inside the roaming application data, so the path reads as %APPDATA%\\mpv. On Linux and macOS the same tree belongs in ~/.config/mpv, and mpv picks it up with no further ceremony.'
      },
      {
        q: 'Which skin is active?',
        a: 'Liquid Glass, a fork of uosc, and it lives in scripts/uosc inside the configuration. ModernZ is shipped as a parked alternative in skins/modernz. Exactly one skin is loaded at a time; the configuration never loads both.'
      },
      {
        q: 'How do I switch skins?',
        a: 'Run switch-skin.cmd from the configuration directory, or switch-skin.ps1 -Skin modernz from a shell. The script moves the two skin folders and rewrites the pointer, and nav_shim.lua notices which skin is running so your key bindings behave identically either way.'
      },
      {
        q: 'Does it work on Linux?',
        a: 'The configuration itself is platform neutral: the video, audio, subtitle and profile files are plain mpv options, and the scripts are plain Lua. Copy the config folder to ~/.config/mpv and you are done. There is a bash installer next to the PowerShell one: it deploys the configuration, downloads yt-dlp, installs the fonts and checks that the configuration parses. It does not install mpv itself, because on Linux the package manager is the right place for that.'
      },
      {
        q: 'What does it download at runtime?',
        a: 'The installer fetches mpv when it is missing, plus yt-dlp from its official release page. While playing, the idle screen fetches one background photograph and caches it locally, OpenSubtitles is queried when a local file has no subtitle track, and YouTube is asked for the format and subtitle list of the video you opened.'
      },
      {
        q: 'Is anything sent to a server?',
        a: 'No telemetry and no analytics. The only network traffic is what the media itself requires: the YouTube or streaming host, OpenSubtitles, and the source of the idle photograph. The optional cookie option reads a local Firefox profile on your own machine and sends nothing extra.'
      },
      {
        q: 'How do I update?',
        a: 'Run the installer again. It backs up your current configuration to a timestamped folder first, so an update never destroys a setting you changed by hand. From a clone, pull the changes and copy the config folder over the installed one.'
      },
      {
        q: 'How do I uninstall?',
        a: 'Run uninstall.ps1. It moves the installed configuration into a timestamped backup folder, so the rollback path stays open. Add -Purge to delete it instead, after a confirmation. mpv itself is left installed; remove that with your package manager.'
      }
    ]
  };

  global.MPVR = DATA;
})(window);
