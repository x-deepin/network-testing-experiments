#!/bin/bash

# Copyright (C) 2016 Deepin Technology Co., Ltd.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

###* Depends
depends=(nmcli awk sed)

###* Basic Configuration
LC_ALL=C

app_file="${0}"
app_name="$(basename $0)"

###* Help functions
msg() {
  local mesg="$1"; shift
  printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

msg2() {
  local mesg="$1"; shift
  printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

warning() {
  if [ -z "${IGNORE_WARN}" ]; then
    local mesg="$1"; shift
    printf "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
  fi
}

error() {
  local mesg="$1"; shift
  printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

abort() {
  error "$@"
  error "Aborting..."
  exit 1
}

setup_colors() {
  unset ALL_OFF BOLD BLUE GREEN RED YELLOW
  if [[ -t 2 && $USE_COLOR != "n" ]]; then
    # prefer terminal safe colored and bold text when tput is supported
    if tput setaf 0 &>/dev/null; then
      ALL_OFF="$(tput sgr0)"
      BOLD="$(tput bold)"
      BLUE="${BOLD}$(tput setaf 4)"
      GREEN="${BOLD}$(tput setaf 2)"
      RED="${BOLD}$(tput setaf 1)"
      YELLOW="${BOLD}$(tput setaf 3)"
    else
      ALL_OFF="\e[0m"
      BOLD="\e[1m"
      BLUE="${BOLD}\e[34m"
      GREEN="${BOLD}\e[32m"
      RED="${BOLD}\e[31m"
      YELLOW="${BOLD}\e[33m"
    fi
  fi
}
setup_colors

is_cmd_exists() {
  if type -a "$1" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

ensure_cmd_exists() {
  if ! is_cmd_exists "$1"; then
    abort "command not exists: $1"
  fi
}

get_self_funcs() {
  grep -o "^${1}.*()" "${app_file}" | sed "s/^\(.*\)()/\1/" | sort
}

get_commands() {
  get_self_funcs "cmd_" | sed 's/^cmd_//'
}

get_commands_with_usage() {
  for c in $(get_commands); do
    local usage="$(usage_${c})"
    if [ -z "${usage}" ]; then
      echo "    ${c}"
    else
      echo "    ${c}: ${usage}"
    fi
  done
}

# return devices and types
get_all_nm_devices() {
  nmcli device | sed 1d | awk '{print $1, $2}'
}

get_all_nm_wired_devices() {
  get_all_nm_devices | awk '$2 ~ /ethernet/{print $1}'
}

get_all_nm_wireless_devices() {
  get_all_nm_devices | awk '$2 ~ /wifi/{print $1}'
}

# return UUID, TYPE and ignore other fields
get_all_nm_conns() {
  local conns_info="$(nmcli connection show)"
  local conns_items="$(echo "${conns_info}" | sed 1d)"
  local conns_items_fixed="$(echo "${conns_items}" | sed 's/^.*\(.\{8\}-.\{4\}-.\{4\}-.\{4\}-.\{12\}\)/\1/')"
  echo "${conns_items_fixed}" | awk '{print $1,$2}'
}
get_all_nm_wired_conns() {
  get_all_nm_conns | awk '$2 ~ /802-3-ethernet/{print $1}'
}
get_all_nm_wireless_conns() {
  get_all_nm_conns | awk '$2 ~ /802-11-wireless/{print $1}'
}

remove_nm_conn() {
  msg2 "remove connection $1"
  nmcli connection delete uuid "$1"
}

###* Commands
cmd_clear-connections() {
  msg "Clear all NetworkManager connections"
  for uuid in $(get_all_nm_conns | awk '{print $1}'); do
    remove_nm_conn "${uuid}"
  done
}
usage_clear-connections() {
  echo
}

cmd_clear-wired-connections() {
  msg "Clear all NetworkManager wired connections"
  for uuid in $(get_all_nm_wired_conns); do
    remove_nm_conn "${uuid}"
  done
}
usage_clear-wired-connections() {
  echo
}

cmd_clear-wireless-connections() {
  msg "Clear all NetworkManager wireless connections"
  for uuid in $(get_all_nm_wireless_conns); do
    remove_nm_conn "${uuid}"
  done
}
usage_clear-wireless-connections() {
  echo
}

cmd_connect-wired() {
  msg "Add and active wired connection for all wired adapters"
  echo TODO
}
usage_connect-wired() {
  echo TODO
}

cmd_connect-wireless() {
  msg "Add and active wireless connection for all wireless adapters"
  local ssid="$1"
  local pwd="$2"
  msg2 "Options: ssid=${ssid}, password=${pwd}"

  for if in $(get_all_nm_wireless_devices); do
    # add connection manually instead of using "nmcli dev wifi connect" here to fix hidden SSID issue
    msg2 "adding wireless connection for SSID ${if}..."
    nmcli connection add type wifi con-name "${ssid}" ifname "${if}" ssid "${ssid}"
    nmcli connection modify "${ssid}" wifi-sec.key-mgmt wpa-psk
    nmcli connection modify "${ssid}" wifi-sec.psk "${pwd}"

    msg2 "connecting with ifname ${if}..."
    nmcli connection up "${ssid}" ifname "${if}"
  done
}
usage_connect-wireless() {
  echo "<SSID> <password>"
}


###* Main loop

arg_cmd=
arg_help=

show_usage() {
  cat <<EOF
${app_name} <command> [args...] [-h]
Options:
    -h, --help, show this message
Command list:
$(get_commands_with_usage)
EOF
}

# dispatch arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) arg_help=t; break;;
    *) arg_cmd="$1"; shift; break;;
  esac
done

if [ "${arg_help}" -o -z "${arg_cmd}" ]; then
  show_usage
  exit 1
fi

# check depends
for cmd in "${depends[@]}"; do
  ensure_cmd_exists "${cmd}"
done

# call target command
cmd_"${arg_cmd}" "$@"

# Local Variables:
# mode: sh
# mode: orgstruct
# orgstruct-heading-prefix-regexp: "^\s*###"
# sh-basic-offset: 2
# End:
