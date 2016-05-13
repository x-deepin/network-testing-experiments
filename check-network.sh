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
for p in {5201..5250}; do
  iperf_ports+=("${p}")
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

collect_error() {
  errors+=("$1")
}

collect_results() {
  results+=("$1")
}

print_real_ifcs() {
  for ifc in $(lshw -short -C network 2>/dev/null | sed '1,2d' | awk '{print $2}'); do
    echo "${ifc}"
  done
}

get_wireless_ifc_array() {
  for ifc in $(/sbin/iwconfig 2>/dev/null | grep 'IEEE' | awk '{print $1}'); do
    wireless_ifc_array+=("${ifc}")
  done
}
is_wireless_ifc() {
  local ifc="$1"
  local found=
  for tmp_ifc in "${wireless_ifc_array[@]}"; do
    if [ "${tmp_ifc}" = "${ifc}" ]; then
      found=t
      break
    fi
  done
  if [ "${found}" ]; then
    return
  else
    return 1
  fi
}

print_ifc_ip() {
  local ifc="${1}"
  ip address show ${ifc} | grep 'inet ' | awk '{print $2}' | awk -F/ '{print $1}' | head -1
}

# print network device ID which format looks like pci@8086:10f5, usb@148f:5370
print_ifc_id() {
  # get bus info through lshw
  local businfo="$(lshw -businfo -c network 2>/dev/null | sed '1,2d' | awk -v ifc="${ifc}" '$2 ~ ifc{print $1}')"
  local type="${businfo%%@*}"
  local busid="${businfo##*@}"
  if [ "${type}" = "usb" ]; then
    # fix bus id for usb device, "usb@10:1" -> "usb@10-1"
    busid="${busid/:/-}"
  fi
  local buspath="/sys/bus/${type}/devices/${busid}"
  if [ "${type}" = "usb" ]; then
    local idVendor="$(cat ${buspath}/idVendor)"
    local idProduct="$(cat ${buspath}/idProduct)"
  elif [ "${type}" = "pci" ]; then
    local idVendor="$(cat ${buspath}/vendor | sed 's/^0x//')"
    local idProduct="$(cat ${buspath}/device | sed 's/^0x//')"
  fi
  echo "${type}@${idVendor}:${idProduct}"
}

print_ifc_desc() {
  local ifc="$1"
  lshw -short -c network 2>/dev/null | sed '1,2d' | awk -v ifc="${ifc}" '$2 ~ ifc{for (i=4;i<NF;i++)printf $i " "; print $NF}'
}

get_ifc_details() {
  msg "Get network interface details"
  get_wireless_ifc_array
  for ifc in $(print_real_ifcs); do
    local type=
    if is_wireless_ifc "${ifc}"; then
      type="wireless"
    else
      type="wired"
    fi
    local ip="$(print_ifc_ip "${ifc}")"
    local id="$(print_ifc_id "${ifc}")"
    local desc="$(print_ifc_desc "${ifc}")"
    local item="${type}|${ifc}|${ip}|${id}|${desc}"
    msg2 "${item}"
    ifc_details+=("${item}")
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
  if [ -z "${device_speed}" ]; then
    warning "Get device speed failed, use 50 Mbits/s as default"
    device_speed=50
  fi
  local prefer_speed=$(bc -l <<<"${device_speed}/${speed_scale}")
  msg2 "guess device prefer speed: ${device_speed}/${speed_scale}=${prefer_speed} Mbit/s"

  msg2 "format iperf3 data"
  local fixed_file="$(mktemp /tmp/iperf3_fixed_result_XXXXXX)"
  awk '$(11) ~ /Bytes$/ {print i++, $7}' "${result_file}" > "${fixed_file}"
  head -5 "${fixed_file}"

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
    local real_speed="$(bc -l <<<"${all_speed} / ${i}")"
    if [ $(bc <<<"${real_speed} >= ${prefer_speed}") -eq 1 ]; then
      msg2 "network average speed is OK: ${all_speed}/${i}=${real_speed} >= ${prefer_speed}"
    else
      msg2 "network average speed is incorrect: ${all_speed}/${i}=${real_speed} < ${prefer_speed}"
      ok=
    fi
  fi

  if [ "${ok}" ]; then
    rm "${fixed_file}"
    return 0
  else
    return 1
  fi
}

###* Main loop

arg_server='192.168.1.1'
arg_category='wireless'
arg_devicenum=
arg_time=3600
arg_help=

# collect errors to keep code continue and report at end
declare -a errors

# collect all test results
declare -a results

declare -a wireless_ifc_array
declare -a none_wireless_ifc_array

# each item will contains interface details in format
# "type|ifc|ip|id|desc" such as:
#   ("wired|enp0s25|192.168.1.101|pci@8086:10f5|82567LM Gigabit Network Connection",
#    "wireless|wlp3s0|192.168.1.102|pci@8086:4237|PRO/Wireless 5100 AGN [Shiloh] Network Connection",
#    "wireless|wlx7cdd90b2c508|192.168.1.103|usb@148f:5370|Wireless interface")
declare -a ifc_details

show_usage() {
  cat <<EOF
${app_name} [-s <server>] [-c <category>] [-n <devicenum>] [-t <time>] [-h]
Options:
    -s, --server, iperf3 server
    -c, --category, could be wired or wireless (default: wireless)
    -n, --devicenum, the prefer network device number in local to test
    -t, --time, the seconds to run for iperf3 client (default: 3600)
    -h, --help, show this message
EOF
}

# dispatch arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -s|--server) arg_server="$2"; shift; shift;;
    -c|--category) arg_category="$2"; shift; shift;;
    -n|--devicenum) arg_devicenum="$2"; shift; shift;;
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
msg2 "DeviceNum: ${arg_devicenum}"
msg2 "Time: ${arg_time}"

get_ifc_details

active_ifc_num=0
for item in "${ifc_details[@]}"; do
  type="$(echo "${item}" | awk -F'|' '{print $1}')"
  if [ ! "${arg_category}" = "${type}" ]; then
    continue
  fi

  ifc="$(echo "${item}" | awk -F'|' '{print $2}')"
  ip="$(echo "${item}" | awk -F'|' '{print $3}')"
  id="$(echo "${item}" | awk -F'|' '{print $4}')"
  desc="$(echo "${item}" | awk -F'|' '{print $5}')"
  if [ -n "${ip}" ]; then
    ((active_ifc_num++))
  else
    collect_results "[IGNORE] inactive interface ${ifc}[${id}](${desc})"
    continue
  fi

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
    collect_results "[PASS] ${ip} for ${ifc}[${id}](${desc})"
  else
    collect_results "[FAILED] ${ifc}[${id}](${desc})"
    collect_error "network speed for interface ${ifc} is incorrect"
  fi
  rm "${result_file}"
done

if [ "${arg_devicenum}" ]; then
  if [ "${active_ifc_num}" -ne "${arg_devicenum}" ]; then
    collect_error "actived network device number is wrong, prefer ${arg_devicenum}, but in fact is ${active_ifc_num}"
  fi
fi

if [ "${active_ifc_num}" -eq 0 ]; then
  warning "there is no ip address for ${arg_category} devices"
fi

msg "Results"
for r in "${results[@]}"; do
  msg2 "${r}"
done

if [ "${#errors[@]}" -ne 0 ]; then
  error "collected errors:"
  for e in "${errors[@]}"; do
    msg2 "${e}"
  done
  abort "error occured"
fi

# Local Variables:
# mode: sh
# mode: orgstruct
# orgstruct-heading-prefix-regexp: "^\s*###"
# sh-basic-offset: 2
# End:
