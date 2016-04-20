#!/bin/bash

# Copyright (C) 2016 Deepin Technology Co., Ltd.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

###* Depends
depends=(iperf3 awk bc ip lshw mktemp gnuplot /sbin/iwconfig /sbin/ethtool )

###* Basic Configuration
LC_ALL=C

app_file="${0}"
app_name="$(basename $0)"

declare -a iperf_ports
for i in $(seq 50); do
  port=$(expr 5200 + "${i}")
  iperf_ports+=("${port}")
done

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
      printf "${YELLOW}==> $(gettext "WARNING:")${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
  fi
}

error() {
  local mesg="$1"; shift
  printf "${RED}==> $(gettext "ERROR:")${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

abort() {
  error "$@"
  error "$(gettext "Aborting...")"
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

get_ifc_array_for_wired() {
  msg "Get interfaces for wired device"
  for ifc in $(/sbin/iwconfig 2>&1 1>/dev/null | grep 'no wireless extensions' | awk '{print $1}'); do
    msg2 "${ifc}"
    ifc_array+=("${ifc}")
  done
}

get_ifc_array_for_wireless() {
  msg "Get interfaces for wireless device"
  for ifc in $(/sbin/iwconfig 2>/dev/null | grep 'IEEE' | awk '{print $1}'); do
    msg2 "${ifc}"
    ifc_array+=("${ifc}")
  done
}

ignore_virtual_interfaces() {
  msg "Ignore virtual interfaces"
  declare -a real_ifc_array
  declare -a fixed_ifc_array
  for ifc in $(lshw -C network 2>/dev/null | grep 'logical name' | awk '{print $3}'); do
    real_ifc_array+=("${ifc}")
  done
  for ifc in "${ifc_array[@]}"; do
    local found=
    for real_ifc in "${real_ifc_array[@]}"; do
      if [ "${real_ifc}" = "${ifc}" ]; then
        found=t
        break
      fi
    done
    if [ "${found}" ]; then
      fixed_ifc_array+=("${ifc}")
    else
      msg2 "ignore ${ifc}"
    fi
  done
  ifc_array=("${fixed_ifc_array[@]}")
}

get_ip_array() {
  msg "Get IP addresses for network device"
  for ifc in "${ifc_array[@]}"; do
    local ip="$(ip address show ${ifc} | grep 'inet ' | awk '{print $2}' | awk -F/ '{print $1}' | head -1)"
    if [ -n "${ip}" ]; then
      msg2 "${ifc}: ${ip}"
      ip_array+=("${ifc}|${ip}")
    else
      msg2 "${ifc}: no ip address"
    fi
  done
}

get_wired_speed() {
  /sbin/ethtool "$1" 2>/dev/null | grep 'Speed' | awk '{print $2}' | awk -FM '{print $1}'
}

get_wireless_speed() {
  /sbin/iwconfig "$1" | grep 'Bit Rate' | awk '{print $2}' | awk -F= '{print $2}'
}

check_iperf3_result() {
  local result_file="${1}"
  local ifc="${2}"
  local category="${3}"
  local device_speed=50 # 50 Mbits/s
  local speed_scale=15 # TODO magic number here

  msg "Check iperf3 result for ${ifc}: ${result_file}"

  if [ "${category}" = "wired" ]; then
    device_speed="$(get_wired_speed ${ifc})"
  else
    device_speed="$(get_wireless_speed ${ifc})"
  fi
  local prefer_speed=$(bc -l <<<"${device_speed}/${speed_scale}")
  msg2 "guess device prefer speed: ${device_speed}/${speed_scale}=${prefer_speed} Mbit/s"

  msg2 "format iperf3 data"
  local fixed_file="$(mktemp /tmp/iperf3_fixed_result_XXXXXX)"
  awk '$(11) ~ /^KBytes/ {print i++, $7}' "${result_file}" > "${fixed_file}"

  msg2 "generate gnuplot chart"
  gnuplot <<<"
set terminal png
set output 'gnuplot-iperf3-${ifc}.png'
set autoscale
set xlabel 'time (s)'
set xtics '60'
set ylabel 'Mbits'
set arrow from graph 0,first ${prefer_speed} to graph 1,first ${prefer_speed} nohead lc rgb '#1A97AD' front
plot '${fixed_file}' using 1:2 title 'iperf3' with lines,
"

  msg2 "check if network disconnected during the time"
  local ok=t
  local i=0
  local all_speed=0
  local min_speed=0.5
  for s in $(cat "${fixed_file}" | awk '{print $2}'); do
    ((i++))
    all_speed=$(bc <<< "${all_speed} + ${s}")
    if [ $(bc <<<"${s} < ${min_speed}") -eq 1 ]; then
      warning "looks network disconnected: ${s} < ${min_speed}"
      ok=
      break
    fi
  done

  msg2 "check if network average speed is OK"
  if [ "${ok}" ]; then
    if [ $(bc <<<"${all_speed}/${i} >= ${prefer_speed}") -eq 1 ]; then
      msg2 "network average speed is OK: ${all_speed}/${i} >= ${prefer_speed}"
    else
      msg2 "network average speed is incorrect: ${all_speed}/${i} < ${prefer_speed}"
      ok=
    fi
  fi

  rm "${fixed_file}"
  if [ "${ok}" ]; then
    return 0
  else
    return 1
  fi
}

###* Main loop

arg_server='192.168.1.1'
arg_category='wireless'
arg_time=3600
arg_help=

declare -a ifc_array

# each item will contains interface info such as ("eth0|192.168.1.100")
declare -a ip_array

show_usage() {
  cat <<EOF
${app_name} [-s <server>] [-c <category>] [-t <time>] [-h]
Options:
    -s, --server, iperf3 server
    -c, --category, could be wired or wireless (default: wireless)
    -t, --time, the seconds to run for iperf3 client (default: 3600)
    -h, --help, show this message
EOF
}

# dispatch arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -s|--server) arg_server="$2"; shift; shift;;
    -c|--category) arg_category="$2"; shift; shift;;
    -t|--time) arg_time="$2"; shift; shift;;
    -h|--help) arg_help=t; break;;
    *)  shift;;
  esac
done

if [ "${arg_help}" ]; then
  show_usage
  exit 1
fi

# check depends
for cmd in "${depends[@]}"; do
  ensure_cmd_exists "${cmd}"
done

msg "Options"
msg2 "Server: ${arg_server}"
msg2 "Category: ${arg_category}"
msg2 "Time: ${arg_time}"

if [ "${arg_category}" = "wired" ]; then
  get_ifc_array_for_wired
else
  get_ifc_array_for_wireless
fi
ignore_virtual_interfaces
get_ip_array

if [ "${#ip_array[@]}" -eq 0 ]; then
  abort "there is no ip address for ${arg_category} devices"
fi

for item in "${ip_array[@]}"; do
  ifc="${item%%|*}"
  ip="${item##*|}"
  msg "Collecting iperf3 data with binding address ${ip}(${ifc})"
  result_file="$(mktemp /tmp/iperf3_result_XXXXXX)"
  for p in "${iperf_ports[@]}"; do
    if iperf3 -p "${p}" -B "${ip}" -c "${arg_server}" -f m -t "${arg_time}" > "${result_file}"; then
      msg2 "finish with iperf3 server ${ip}:${p}"
      break
    else
      msg2 "ignore ${ip}:${p}"
    fi
  done
  if check_iperf3_result "${result_file}" "${ifc}" "${arg_category}"; then
    msg "network speed for interface ${ifc} is OK"
  else
    abort "network speed for interface ${ifc} is incorrect"
  fi
  rm "${result_file}"
done

# Local Variables:
# mode: sh
# mode: orgstruct
# orgstruct-heading-prefix-regexp: "^\s*###"
# sh-basic-offset: 2
# End:
