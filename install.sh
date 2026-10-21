#!/usr/bin/env bash
#
# install.sh - Linux/macOS installer for mpv-redesigned.
#
# Mirrors install.ps1: deploys the config/ payload to the mpv configuration
# directory, backs up an existing install, downloads yt-dlp, installs fonts,
# activates a skin and sanity-checks the configuration with mpv.
#
#   From a clone:        bash install.sh
#   From the internet:   curl -fsSL https://github.com/ratuuul/mpv-redesigned/raw/main/install.sh | bash
#
set -euo pipefail
IFS=$'\n\t'

readonly PROGRAM_NAME='install.sh'
readonly PROGRAM_VERSION='1.0.0'
readonly REPO_URL='https://github.com/ratuuul/mpv-redesigned'
readonly ARCHIVE_URL="${REPO_URL}/archive/refs/heads/main.tar.gz"
readonly YTDLP_URL='https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp'

readonly SKIN_DEFAULT='liquidglass'

# skin name -> "live folder under scripts/ | parked folder under skins/"
skin_live()   { case "$1" in liquidglass) echo 'uosc';; modernz) echo 'modernz';; esac; }
skin_parked() { case "$1" in liquidglass) echo 'liquid-glass/uosc';; modernz) echo 'modernz';; esac; }

# Directories the player and the skins expect to exist.
readonly RUNTIME_DIRS=(cache state watch_later screenshots subs subtitles temp)
# Runtime state is never deployed: mpv.log and recent.json are personal to the
# authoring machine, and watch_later/screenshots/subs/subtitles/temp/state are
# user state that must survive a re-install.
readonly SKIP_NAMES=(cache mpv.log recent.json watch_later screenshots subs subtitles temp state)

# -----------------------------------------------------------------------------
#  Output (colourised when connected to a terminal)
# -----------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  c_reset='\033[0m'; c_step='\033[36m'; c_ok='\033[32m'
  c_info='\033[90m'; c_warn='\033[33m'; c_err='\033[31m'
else
  c_reset=''; c_step=''; c_ok=''; c_info=''; c_warn=''; c_err=''
fi

STEP_NO=0
DRY_RUN=0
FORCE=0
NO_YTDLP=0
NO_FONTS=0
CONFIG_DIR_OVERRIDE=''
BACKUP_DIR_OVERRIDE=''
SKIN=''
DO_UNINSTALL=0
TEMP_DIR=''

step()  { STEP_NO=$((STEP_NO + 1)); printf '\n  %s[%d]%s %s\n' "$c_step" "$STEP_NO" "$c_reset" "$1"; }
ok()    { printf '      %sOK%s    %s\n' "$c_ok" "$c_reset" "$1"; }
info()  { printf '            %s\n' "$1"; }
warn()  { printf '      %sWARN%s  %s\n' "$c_warn" "$c_reset" "$1"; }
err()   { printf '      %sFAIL%s  %s\n' "$c_err" "$c_reset" "$1"; }

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

# Run $2.. as an action, or just log what would happen in dry-run mode.
action() {
  local desc="$1"; shift
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "would: $desc"
    return 0
  fi
  "$@"
}

usage() {
  cat <<EOF
Usage: ${PROGRAM_NAME} [options]

  From a clone:        bash ${PROGRAM_NAME}
  From the internet:   curl -fsSL ${REPO_URL}/raw/main/${PROGRAM_NAME} | bash

Options:
  --help               Show this help and exit.
  --version            Print the version and exit.
  --uninstall          Run uninstall.sh instead of installing.
  --dry-run            Print every action, change nothing.
  --force              Replace an existing configuration without asking.
  --config-dir <path>  Configuration directory (default: \$MPV_CONFIG_DIR,
                       then \$XDG_CONFIG_HOME/mpv, then ~/.config/mpv).
  --backup-dir <path>  Directory for the timestamped backup (default: next
                       to the configuration directory).
  --no-yt-dlp          Skip the yt-dlp download.
  --no-fonts           Skip installing the fonts.
  --skin <skin>        Activate liquidglass or modernz (default: liquidglass).

Exit codes: 0 = ok, 1 = failure.
EOF
}

# -----------------------------------------------------------------------------
#  Config directory resolution
# -----------------------------------------------------------------------------
resolve_config_dir() {
  if [[ -n "${CONFIG_DIR_OVERRIDE:-}" ]]; then
    printf '%s' "${CONFIG_DIR_OVERRIDE}"
  elif [[ -n "${MPV_CONFIG_DIR:-}" ]]; then
    printf '%s' "${MPV_CONFIG_DIR}"
  elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s/mpv' "${XDG_CONFIG_HOME}"
  else
    printf '%s/.config/mpv' "${HOME}"
  fi
}

default_config_dir() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then printf '%s/mpv' "${XDG_CONFIG_HOME}";
  else printf '%s/.config/mpv' "${HOME}"; fi
}

# -----------------------------------------------------------------------------
#  1. Locate the configuration payload
# -----------------------------------------------------------------------------
locate_payload() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0}}")" 2>/dev/null && pwd || true)"
  if [[ -n "$script_dir" && -d "$script_dir/config" ]]; then
    printf '%s' "$script_dir"
    return 0
  fi
  return 1
}

download_payload() {
  local target="$1" archive
  archive="${target}/src.tar.gz"
  info 'Downloading repository archive...'
  if command -v curl >/dev/null 2>&1; then
    action "download ${ARCHIVE_URL}" sh -c 'curl -fsSL --retry 3 --connect-timeout 20 "$1" -o "$2"' _ "$ARCHIVE_URL" "$archive"
  elif command -v wget >/dev/null 2>&1; then
    action "download ${ARCHIVE_URL}" sh -c 'wget -q --timeout=20 -t 3 -O "$2" "$1"' _ "$ARCHIVE_URL" "$archive"
  else
    err 'Neither curl nor wget is available; cannot fetch the repository archive.'
    return 1
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then return 0; fi
  tar -xzf "$archive" -C "$target"
  local entry null_was=0
  shopt -q nullglob || { null_was=1; shopt -s nullglob; }
  for entry in "$target"/*/; do
    if [[ -d "$entry/config" ]]; then
      printf '%s' "$entry"
      if [[ "$null_was" -eq 1 ]]; then shopt -u nullglob; fi
      return 0
    fi
  done
  if [[ "$null_was" -eq 1 ]]; then shopt -u nullglob; fi
  err 'Could not locate the config folder inside the downloaded archive.'
  return 1
}

# -----------------------------------------------------------------------------
#  2. mpv
# -----------------------------------------------------------------------------
MPV_BIN=''

find_mpv() {
  if command -v mpv >/dev/null 2>&1; then
    MPV_BIN="$(command -v mpv)"
    ok "Found ${MPV_BIN}"
  else
    MPV_BIN=''
    warn 'mpv not found on PATH'
    hint_mpv_install
  fi
}

hint_mpv_install() {
  case "$(uname -s)" in
    Darwin)
      info 'macOS:    brew install mpv'
      ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}" in
          ubuntu|debian) info 'Debian/Ubuntu:  sudo apt install mpv' ;;
          arch)          info 'Arch Linux:     sudo pacman -S mpv' ;;
          fedora)        info 'Fedora:         sudo dnf install mpv' ;;
          *)             info 'Install mpv with your distribution package manager.' ;;
        esac
      fi
      ;;
    *)
      info 'Install mpv from https://mpv.io/installation/'
      ;;
  esac
  info 'The configuration is still installed; mpv is only needed to play.'
}

# -----------------------------------------------------------------------------
#  3. yt-dlp
# -----------------------------------------------------------------------------
install_yt_dlp() {
  # `local dest="$1" exe="${dest}/yt-dlp"` expands ${dest} before the local
  # assignment has happened, which `set -u` rejects. Split it.
  local dest="$1"
  local exe="${dest}/yt-dlp"
  local arch
  if [[ -f "$exe" ]]; then
    ok 'yt-dlp already present'
    return 0
  fi
  arch="$(uname -m)"
  info "Downloading yt-dlp for ${arch}..."
  action "download yt-dlp -> ${exe}" sh -c 'curl -fsSL --retry 3 --connect-timeout 20 "$1" -o "$2"' _ "$YTDLP_URL" "$exe"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    chmod +x -- "$exe"
    ok "yt-dlp installed (${arch})"
  fi
}

# -----------------------------------------------------------------------------
#  4. Deploy the configuration
# -----------------------------------------------------------------------------
deploy_config() {
  local source="$1" dest="$2" name bname s skip null_was=0
  shopt -q nullglob || { null_was=1; shopt -s nullglob; }
  action "create ${dest}" mkdir -p -- "$dest"
  for name in "$source"/*; do
    bname="$(basename -- "$name")"
    skip=0
    for s in "${SKIP_NAMES[@]}"; do
      if [[ "$bname" == "$s" ]]; then skip=1; break; fi
    done
    if [[ "$skip" -eq 1 ]]; then
      info "skip ${bname} (runtime state, never deployed)"
      continue
    fi
    action "copy ${bname}" cp -R -- "$name" "$dest/"
  done
  if [[ "$null_was" -eq 1 ]]; then shopt -u nullglob; fi
}

backup_config() {
  local path="$1" stamp parent base backup n
  stamp="$(date +%Y%m%d-%H%M%S)"
  parent="$(dirname -- "$path")"
  base="$(basename -- "$path")"
  if [[ -n "${BACKUP_DIR_OVERRIDE:-}" ]]; then
    parent="${BACKUP_DIR_OVERRIDE}"
    action "create backup dir" mkdir -p -- "$parent"
  fi
  backup="${parent}/${base}-backup-${stamp}"
  n=1
  while [[ -e "$backup" ]]; do
    backup="${parent}/${base}-backup-${stamp}-${n}"
    n=$((n + 1))
  done
  action "backup existing configuration -> ${backup}" mv -- "$path" "$backup"
  printf '%s' "$backup"
}

install_fonts() {
  local source="$1" dest="$2" f
  if [[ ! -d "${source}/fonts" ]]; then
    info 'No fonts/ in the payload; skipping.'
    return 0
  fi
  action "create fonts/" mkdir -p -- "${dest}/fonts"
  local f null_was=0
  shopt -q nullglob || { null_was=1; shopt -s nullglob; }
  for f in "${source}"/fonts/*; do
    case "$f" in
      *.ttf|*.otf|*.TTF|*.OTF) ;;
      *) info "skip $(basename -- "$f") (not a font file)"; continue ;;
    esac
    action "install font $(basename -- "$f")" cp -- "$f" "${dest}/fonts/"
  done
  if [[ "$null_was" -eq 1 ]]; then shopt -u nullglob; fi
}

activate_skin() {
  local dest="$1" skin="$2"
  local scripts="${dest}/scripts" skins="${dest}/skins"
  local name live parked from to
  # Park every skin that is currently live, then bring the wanted one out.
  for name in liquidglass modernz; do
    live="$(skin_live "$name")"
    parked="$(skin_parked "$name")"
    if [[ -d "${scripts}/${live}" ]]; then
      mkdir -p -- "$(dirname -- "${skins}/${parked}")"
      if [[ -e "${skins}/${parked}" ]]; then rm -rf -- "${skins}/${parked}"; fi
      action "park ${live}" mv -- "${scripts}/${live}" "${skins}/${parked}"
      info "parked ${live}"
    fi
  done
  live="$(skin_live "$skin")"
  parked="$(skin_parked "$skin")"
  from="${skins}/${parked}"
  to="${scripts}/${live}"
  if [[ ! -e "$from" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      # In a dry run the park step above was only printed, so ${from} was never
      # moved into place. Report the plan instead of failing on a missing path.
      action "activate ${skin} (${live})" true
      info "would activate ${live} (${skin})"
      return 0
    fi
    err "Could not find ${from}"
    return 1
  fi
  action "activate ${skin} (${live})" mv -- "$from" "$to"
  ok "active ${live} (${skin})"
}

# -----------------------------------------------------------------------------
#  5. Node.js hint (mirrors install.ps1 Test-NodeRuntime)
# -----------------------------------------------------------------------------
hint_node() {
  if command -v node >/dev/null 2>&1; then
    ok "Found $(command -v node)"
    return 0
  fi
  warn 'node not found on PATH'
  info 'YouTube still plays, but the higher-quality formats need a JS runtime.'
  info "mpv.conf sets js-runtimes=node; without Node, yt-dlp cannot solve"
  info "YouTube's signature challenge, so the format list comes back empty."
  case "$(uname -s)" in
    Darwin) info 'macOS:    brew install node' ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}" in
          ubuntu|debian) info 'Debian/Ubuntu:  sudo apt install nodejs' ;;
          arch)          info 'Arch Linux:     sudo pacman -S nodejs npm' ;;
          fedora)        info 'Fedora:         sudo dnf install nodejs' ;;
          *)             info 'Install Node.js with your distribution package manager.' ;;
        esac
      fi
      ;;
    *) info 'Install Node.js from https://nodejs.org/' ;;
  esac
  info 'Then open a NEW terminal and start mpv again.'
}

# -----------------------------------------------------------------------------
#  6. Verify
# -----------------------------------------------------------------------------
verify_config() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "would: ${MPV_BIN:-mpv} --config-dir='${CONFIG_DIR}' --no-terminal --list-options (parse check)"
    return 0
  fi
  if [[ -z "${MPV_BIN:-}" ]]; then
    warn 'mpv not found on PATH - skipping the parse check.'
    return 0
  fi
  step 'Verifying the configuration'
  info "Running ${MPV_BIN} --config-dir='${CONFIG_DIR}' --no-terminal --list-options ..."
  local check_log rc=0 problems
  check_log="$(mktemp "${TMPDIR:-/tmp}/mpv-redesigned-check-XXXXXX.log")"
  "$MPV_BIN" --config-dir="$CONFIG_DIR" --no-terminal --list-options >"$check_log" 2>&1 || rc=$?
  problems="$(grep -E '\[e\]|Error parsing option|Invalid value|Lua error|unknown option|failed to|No such' "$check_log" || true)"
  if [[ -n "$problems" || "$rc" -ne 0 ]]; then
    err 'The configuration produced problems:'
    local n=0 line
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf '            %s\n' "$line"
      n=$((n + 1))
      [[ "$n" -ge 10 ]] && break
    done <<< "$problems"
    info "Full log: ${check_log}"
    return 1
  fi
  ok 'Configuration parsed cleanly'
  rm -f -- "$check_log"
  return 0
}

# -----------------------------------------------------------------------------
#  Main
# -----------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --version) printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"; exit 0 ;;
      --uninstall) DO_UNINSTALL=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --force) FORCE=1 ;;
      --no-yt-dlp) NO_YTDLP=1 ;;
      --no-fonts) NO_FONTS=1 ;;
      --config-dir)
        shift
        if [[ $# -eq 0 ]]; then err 'option --config-dir requires a value'; exit 1; fi
        CONFIG_DIR_OVERRIDE="$1"
        ;;
      --backup-dir)
        shift
        if [[ $# -eq 0 ]]; then err 'option --backup-dir requires a value'; exit 1; fi
        BACKUP_DIR_OVERRIDE="$1"
        ;;
      --skin)
        shift
        if [[ $# -eq 0 ]]; then err 'option --skin requires a value'; exit 1; fi
        SKIN="$1"
        case "$SKIN" in
          liquidglass|modernz) ;;
          *) err "unknown skin: ${SKIN} (try: liquidglass|modernz)"; exit 1 ;;
        esac
        ;;
      --) shift; break ;;
      *) err "unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

main() {
  printf '\n  %bmpv-redesigned%b\n' "$c_step" "$c_reset"
  printf '  ------------------------------------------------\n'
  printf '  A tuned mpv: Liquid Glass skin, full-quality video stack,\n'
  printf '  YouTube quality picker, subtitles, downloads and more.\n'
  printf '\n'

  parse_args "$@"

  if [[ "$DO_UNINSTALL" -eq 1 ]]; then
    local uninstaller
    uninstaller="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0}}")" 2>/dev/null && pwd || true)/uninstall.sh"
    if [[ -f "$uninstaller" ]]; then
      exec bash -- "$uninstaller"
    fi
    cat <<EOF

  Run the uninstaller instead:

    curl -fsSL ${REPO_URL}/raw/main/uninstall.sh | bash

  or, from a clone:

    bash ./uninstall.sh
EOF
    exit 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then warn 'DRY RUN - nothing will be changed.'; fi

  CONFIG_DIR="$(resolve_config_dir)"
  local default_dir; default_dir="$(default_config_dir)"

  # Refuse to stomp a running player: file locks and lost state. Only the
  # default config dir is protected, so a --config-dir scratch run is allowed
  # while another player is open.
  if command -v pgrep >/dev/null 2>&1 && pgrep -x mpv >/dev/null 2>&1; then
    if [[ "$CONFIG_DIR" == "$default_dir" ]]; then
      err 'mpv is running. Close it and run the installer again.'
      info 'Its configuration files are in use; replacing them now would lose resume state.'
      exit 1
    fi
    warn "mpv is running, but the target is a custom --config-dir."
    info "If that player was started with --config-dir=\"${CONFIG_DIR}\", close it first."
  fi

  step 'Locating the configuration payload'
  local repo_dir='' src=''
  if repo_dir="$(locate_payload 2>/dev/null)"; then
    src="${repo_dir}/config"
    ok "Using ${src}"
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "would: download ${ARCHIVE_URL} to a temp dir and extract config/"
    else
      if [[ "$DRY_RUN" -eq 1 ]]; then
        info "would: download ${ARCHIVE_URL} to a temp dir and extract config/"
        src='<temp extraction>/config'
      else
        TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mpv-redesigned-XXXXXX")"
        repo_dir="$(download_payload "$TEMP_DIR")" || exit 1
        src="${repo_dir}/config"
        ok "Using ${src}"
      fi
    fi
  fi
  if [[ "$DRY_RUN" -eq 0 && (! -d "$src") ]]; then
    err "Configuration payload missing at ${src}"
    exit 1
  fi

  step 'mpv'
  find_mpv

  step 'Node.js (YouTube format support)'
  hint_node

  if [[ -d "$CONFIG_DIR" && "$FORCE" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    printf '\n  A configuration already exists at:\n    %s\n' "$CONFIG_DIR"
    local answer=''
    read -r -p '  Back it up and replace it? [y/N] ' answer || true
    case "$answer" in
      y|yes|Y|Yes) ;;
      *) printf '  Cancelled. Nothing was changed.\n'; exit 0 ;;
    esac
  fi

  local backup=''
  if [[ -e "$CONFIG_DIR" ]]; then
    step 'Backing up the existing configuration'
    backup="$(backup_config "$CONFIG_DIR")"
    ok "Backup: ${backup}"
  fi

  step 'Deploying the configuration'
  deploy_config "$src" "$CONFIG_DIR"
  ok "Deployed to ${CONFIG_DIR}"

  local d
  for d in "${RUNTIME_DIRS[@]}"; do
    action "create ${d}" mkdir -p -- "${CONFIG_DIR}/${d}"
  done

  if [[ -n "$backup" && -d "$backup" ]]; then
    local keep
    for keep in watch_later screenshots; do
      if [[ -d "${backup}/${keep}" ]]; then
        info "Carrying over ${keep}"
        action "restore ${keep}" cp -R -- "${backup}/${keep}" "${CONFIG_DIR}/${keep}"
      fi
    done
  fi

  if [[ "$NO_YTDLP" -eq 0 ]]; then
    step 'yt-dlp'
    install_yt_dlp "$CONFIG_DIR"
  else
    step 'yt-dlp (skipped: --no-yt-dlp)'
  fi

  if [[ "$NO_FONTS" -eq 0 ]]; then
    step 'Fonts'
    install_fonts "$src" "$CONFIG_DIR"
  else
    step 'Fonts (skipped: --no-fonts)'
  fi

  step "Activate skin: ${SKIN:-$SKIN_DEFAULT}"
  activate_skin "$CONFIG_DIR" "${SKIN:-$SKIN_DEFAULT}"

  verify_config

  printf '\n  ------------------------------------------------\n'
  printf '  Done.\n\n'
  printf '  Open a video:\n'
  printf '    mpv "path/to/video.mkv"\n'
  printf '    mpv "https://www.youtube.com/watch?v=..."\n\n'
  printf '  Handy keys:\n'
  printf '    Ctrl+d          download the video you are watching\n'
  printf '    Alt+p           mini always-on-top player\n'
  printf '    F               YouTube quality / format picker\n'
  printf '    Alt+s           YouTube subtitle picker\n'
  printf '    Alt+o           search OpenSubtitles for this file\n'
  printf '    V / D           subtitle menu / download subtitles\n'
  printf '    Ctrl+Shift+K    next idle background photo\n'
  printf '    Ctrl+Shift+r    recent files\n'
  printf '    {  }  BS        slower / faster / normal speed\n\n'
  printf '  Full list: docs/KEYBINDINGS.md\n'
  if [[ -n "$backup" && "$DRY_RUN" -eq 0 ]]; then
    printf '  Your previous configuration is safe at:\n'
    printf '    %s\n' "$backup"
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn 'Dry run: nothing was changed.'
  fi
  printf '\n'
}

main "$@"
