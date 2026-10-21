#!/usr/bin/env bash
#
# uninstall.sh - Remove (or restore) the mpv-redesigned configuration.
#
#   bash uninstall.sh                    # move the config dir to a timestamped
#                                        # backup next to it
#   bash uninstall.sh --restore <dir>    # roll back from a backup
#   bash uninstall.sh --keep-config      # leave the configuration untouched
#
# mpv itself is left in place: it is usually installed through a package
# manager. yt-dlp lives inside the config folder so it goes with it.
#
set -euo pipefail
IFS=$'\n\t'

readonly PROGRAM_NAME='uninstall.sh'
readonly PROGRAM_VERSION='1.0.0'
readonly REPO_URL='https://github.com/ratuuul/mpv-redesigned'

restore_backup=''
KEEP_CONFIG=0
DRY_RUN=0
YES=0
CONFIG_DIR_OVERRIDE=''
TEMP_DIR=''

# -----------------------------------------------------------------------------
#  Output (colourised when connected to a terminal)
# -----------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  c_reset='\033[0m'; c_ok='\033[32m'; c_info='\033[90m'
  c_warn='\033[33m'; c_err='\033[31m'
else
  c_reset=''; c_ok=''; c_info=''; c_warn=''; c_err=''
fi

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
  --restore <dir>      Roll back: move the given backup directory into place
                       as the configuration directory.
  --keep-config        Do not touch the configuration directory at all.
  --dry-run            Print every action, change nothing.
  --yes                Skip the confirmation prompt.

By default the configuration directory is moved to a timestamped backup
folder next to it, so nothing is lost.
EOF
}

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

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --restore)
        shift
        if [[ $# -eq 0 ]]; then err 'option --restore requires a value'; exit 1; fi
        restore_backup="$1"
        ;;
      --keep-config) KEEP_CONFIG=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --yes) YES=1 ;;
      --config-dir)
        shift
        if [[ $# -eq 0 ]]; then err 'option --config-dir requires a value'; exit 1; fi
        CONFIG_DIR_OVERRIDE="$1"
        ;;
      --) shift; break ;;
      *) err "unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

main() {
  printf '\n  %bmpv-redesigned - uninstall%b\n' "$c_ok" "$c_reset"
  printf '  ------------------------------------------------\n'
  printf '\n'

  parse_args "$@"

  CONFIG_DIR="$(resolve_config_dir)"
  local default_dir; default_dir="$(default_config_dir)"

  if [[ -n "$restore_backup" ]]; then
    if [[ ! -d "$restore_backup" ]]; then
      err "Backup not found: ${restore_backup}"
      exit 1
    fi
    if [[ -e "$CONFIG_DIR" ]]; then
      err "Configuration directory already exists: ${CONFIG_DIR}"
      info 'Remove it first, or choose a different --config-dir.'
      exit 1
    fi
    if [[ "$YES" -eq 0 && -t 0 ]]; then
      local answer=''
      read -r -p "Restore ${restore_backup} -> ${CONFIG_DIR}? [y/N] " answer || true
      case "$answer" in
        y|yes|Y|Yes) ;;
        *) printf '  Cancelled.\n'; exit 0 ;;
      esac
    fi
    mkdir -p -- "$(dirname -- "$CONFIG_DIR")"
    action "restore ${restore_backup} -> ${CONFIG_DIR}" mv -- "$restore_backup" "$CONFIG_DIR"
    ok "Restored to ${CONFIG_DIR}"
    printf '  Restart mpv to apply.\n\n'
    exit 0
  fi

  if [[ ! -e "$CONFIG_DIR" ]]; then
    info "Nothing to remove: ${CONFIG_DIR} does not exist."
    printf '\n'
    exit 0
  fi

  if [[ "$KEEP_CONFIG" -eq 1 ]]; then
    info "Keeping the configuration as requested: ${CONFIG_DIR}"
    printf '\n'
    exit 0
  fi

  # Refuse to stomp a running player against the default config dir.
  if command -v pgrep >/dev/null 2>&1 && pgrep -x mpv >/dev/null 2>&1; then
    if [[ "$CONFIG_DIR" == "$default_dir" ]]; then
      err 'mpv is running. Close it first.'
      exit 1
    fi
    info "Note: mpv is running, but not against ${CONFIG_DIR}."
  fi

  if [[ "$YES" -eq 0 && -t 0 ]]; then
    local answer=''
    printf '  A configuration exists at:\n    %s\n' "$CONFIG_DIR"
    read -r -p "  Move it to a timestamped backup? [y/N] " answer || true
    case "$answer" in
      y|yes|Y|Yes) ;;
      *) printf '  Cancelled.\n'; exit 0 ;;
    esac
  fi

  local stamp parent base backup n
  stamp="$(date +%Y%m%d-%H%M%S)"
  parent="$(dirname -- "$CONFIG_DIR")"
  base="$(basename -- "$CONFIG_DIR")"
  backup="${parent}/${base}-backup-${stamp}"
  n=1
  while [[ -e "$backup" ]]; do
    backup="${parent}/${base}-backup-${stamp}-${n}"
    n=$((n + 1))
  done

  action "move configuration -> ${backup}" mv -- "$CONFIG_DIR" "$backup"
  ok "Moved to ${backup}"
  printf '  Roll back with:\n'
  printf '    bash %s --restore %s\n\n' "$PROGRAM_NAME" "$backup"
}

main "$@"
