#!/usr/bin/env bash
#
# switch-skin.sh - swap the mpv OSC skin.
# Linux/macOS counterpart of config/switch-skin.cmd and config/switch-skin.ps1.
#
#   bash switch-skin.sh                 # interactive menu
#   bash switch-skin.sh liquidglass
#   bash switch-skin.sh modernz
#
# Why folders are moved instead of just pointing at a different file:
# mpv only puts a script's own directory on the Lua module path when the
# script lives in scripts/. The Liquid Glass skin needs require('lib/std')
# and friends, so it has to sit in scripts/uosc/ to work at all.
#
# So the active skin lives in scripts/ and the inactive one is parked in
# skins/. This script swaps them.
#
# Restart mpv afterwards.
#
set -euo pipefail
IFS=$'\n\t'

readonly PROGRAM_NAME='switch-skin.sh'

# skin name -> "live folder under scripts/ | parked folder under skins/"
skin_live()   { case "$1" in liquidglass) echo 'uosc';; modernz) echo 'modernz';; esac; }
skin_parked() { case "$1" in liquidglass) echo 'liquid-glass/uosc';; modernz) echo 'modernz';; esac; }

# -----------------------------------------------------------------------------
#  Output
# -----------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  c_reset='\033[0m'; c_ok='\033[32m'; c_info='\033[90m'
  c_warn='\033[33m'; c_err='\033[31m'
else
  c_reset=''; c_ok=''; c_info=''; c_warn=''; c_err=''
fi

ok()   { printf '      %sOK%s    %s\n' "$c_ok" "$c_reset" "$1"; }
info() { printf '            %s\n' "$1"; }
warn() { printf '      %sWARN%s  %s\n' "$c_warn" "$c_reset" "$1"; }
err()  { printf '      %sFAIL%s  %s\n' "$c_err" "$c_reset" "$1"; }

usage() {
  cat <<EOF
Usage: ${PROGRAM_NAME} [--config-dir <path>] [skin]

  skin: liquidglass | modernz   (default: interactive menu)

Examples:
  ${PROGRAM_NAME}            # interactive picker
  ${PROGRAM_NAME} liquidglass
  ${PROGRAM_NAME} modernz
EOF
}

resolve_config_dir() {
  if [[ -n "${MPV_CONFIG_DIR:-}" ]]; then
    printf '%s' "${MPV_CONFIG_DIR}"
  elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s/mpv' "${XDG_CONFIG_HOME}"
  else
    printf '%s/.config/mpv' "${HOME}"
  fi
}

lowercase() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

show_menu() {
  local choice=''
  printf '\n  Available skins:\n'
  printf '    liquidglass  - uosc Liquid Glass fork (glass, centred overlays, speedometer)\n'
  printf '    modernz      - ModernZ (maintained, menus, thumbnails, layouts)\n'
  printf '\n'
  read -r -p '  Skin [liquidglass] ' choice || true
  choice="$(lowercase "${choice:-liquidglass}")"
  printf '%s' "$choice"
}

main() {
  local config_dir scripts skins
  config_dir="$(resolve_config_dir)"
  scripts="${config_dir}/scripts"
  skins="${config_dir}/skins"

  local skin=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --config-dir)
        shift
        if [[ $# -eq 0 ]]; then err 'option --config-dir requires a value'; exit 1; fi
        config_dir="$1"
        scripts="${config_dir}/scripts"
        skins="${config_dir}/skins"
        ;;
      --) shift; break ;;
      *)
        if [[ -z "$skin" ]]; then skin="$1"; else err "unexpected argument: $1"; usage; exit 1; fi
        ;;
    esac
    shift
  done

  if [[ -z "$skin" ]]; then
    skin="$(show_menu)"
  fi
  skin="$(lowercase "$skin")"

  case "$skin" in
    liquidglass|modernz) ;;
    *) err "Unknown skin '${skin}'. Try: liquidglass | modernz"; exit 1 ;;
  esac

  if [[ ! -d "$scripts" ]]; then
    err "mpv scripts dir not found at ${scripts}"
    exit 1
  fi

  # Park every skin that is currently live, then bring the wanted one out.
  local name live parked from to
  for name in liquidglass modernz; do
    live="$(skin_live "$name")"
    parked="$(skin_parked "$name")"
    if [[ -d "${scripts}/${live}" ]]; then
      mkdir -p -- "$(dirname -- "${skins}/${parked}")"
      if [[ -e "${skins}/${parked}" ]]; then rm -rf -- "${skins}/${parked}"; fi
      mv -- "${scripts}/${live}" "${skins}/${parked}"
      info "parked ${live}"
    fi
  done

  live="$(skin_live "$skin")"
  parked="$(skin_parked "$skin")"
  from="${skins}/${parked}"
  to="${scripts}/${live}"

  if [[ ! -e "$from" ]]; then
    err "Could not find ${from}"
    exit 1
  fi

  mv -- "$from" "$to"
  ok "active ${live} (${skin})"
  printf '\n  Restart mpv to apply.\n\n'
}

main "$@"
