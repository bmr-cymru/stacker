#!/bin/bash

# stacker-functions.sh - helper functions used by stacker

# Copyright 2021-2022 Red Hat, Inc. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## Parse a size or offset value with optional unit suffix.
#
# Parameters:
#  size - The value to parse.
#
# Accepts a string in the form "[+-]?[0-9]+[bBkKmMgGtTpP]?". The optional
# unit suffixes correspond to the following values:
#
#  b|B  bytes
#  k|K  kibibytes 1024
#  m|M  mebibytes 1024**2
#  g|G  gibibytes 1024**3
#  t|T  tebibytes 1024**4
#  p|P  pebibytes 1024**5
#
# The value is printed as the number of sectors reflecting any unit suffix
# value. Values passed as bytes (b|B) must represent a whole number of
# sectors.
parse_units() {
    local sectors=""
    if [[ $1 == --sectors ]] || [[ $1 == -s ]]; then
        sectors="yes"
        shift
    fi
    local unitval="$1"
    local suffixes="bBkKmMgGtTpP"
    local numval=${unitval%[$suffixes]}
    local suffix=${unitval##*[0-9]}
    local ssize=512
    local value
    if ! [[ $suffix =~ [$suffixes] ]] && [[ $suffix != "" ]]; then
        stkerror "Unknown sufix: $suffix"
        return 1
    fi
    if ! [[ $numval =~ ^[+-]?[0-9]+$ ]]; then
        stkerror "Argument requires an integer: $unitval"
        return 1
    fi
    if (( numval < 0)); then
        stkerror "Argument $unitval must not be negative"
        return 1
    fi
    case "$suffix" in
        b|B|"")
            sval="0"
            ;;
        k|K)
            sval="10"
            ;;
        m|M)
            sval="20"
            ;;
        g|G)
            sval="30"
            ;;
        t|T)
            sval="40"
            ;;
        p|P)
            sval="50"
            ;;
    esac
    value="$((numval << sval))"
    if [[ $sectors ]]; then
        if ((value % ssize)); then
            stkerror "$unitval is not a whole number of sectors"
            return 1
        fi
        value=$((value >> 9))
    fi
    printf "%d\n" "$value"
    return 0
}

## Print a size value in human readable form
#
# Parameters:
#   size The size value to display.
size_to_units() {
    local size="$1"
    numfmt --to=iec-i --suffix=B "$size"
}

## Print the size of the device found at <device_path> in sectors.
#
# Parameters:
#   dev_path A path to a block device node.
dev_sectors() {
    # device_sectors <device_path>
    # Print the size of the device found at <device_path>
    local dev_path="$1"
    local dev_size
    if ! dev_size="$(blockdev --getsz "$dev_path" 2>/dev/null)"; then
        stkerror "Could not read block device size for $dev_path"
        return 1
    fi
    printf "%s\n" "$dev_size"
    return 0
}

## Test for the existence of a device-mapper device named <dm_name>.
#
# Parameters:
#   dm_name The device-mapper name to query.
dm_exists() {
    local dm_name="$1"
    dmsetup info "$dm_name" &>/dev/null
    return $?
}

## Convert a device-mapper name to a kernel device name.
#
# Prints the kernel device corresponding to <dm_name> (e.g. "dm-0"),
# or the empty string if <dm_name> does not match a device-mapper
# device.
#
# Parameters:
#   dm_name
dm_name_to_kernel() {
    local dm_name="$1"
    local dev_target
    if ! dev_target=$(basename "$(readlink /dev/mapper/"$dm_name" 2>/dev/null)"); then
        stkerror "Could not readlink /dev/mapper/$dm_name"
        return 1
    fi
    echo "$dev_target"
    return 0
}

## Test whether the device-mapper device dm_name is currently suspended.
#
# Parameters:
#   dm_name The name of the device-mapper device to query.
dm_suspended() {
    local dm_name="$1"
    local dm_dev
    if ! dm_dev="$(dm_name_to_kernel "$dm_name")"; then
        stkerror "Could not get kernel name for $dm_name"
        return 1
    fi
    susp=$(cat /sys/block/"$dm_dev"/dm/suspended)
    test "$susp" == "1"
}

## Test for the existence of listed devices.
#
# Parameters:
#   devices - the list of devices to test for.
have_devices() {
    local ret=0
    local devices=("$@")
    for dev in "${devices[@]}"; do
        if [[ ":" =~ [$dev] ]]; then
            dev="${dev%:*}"
        fi
        if ! dm_exists "$dev"; then
            if ! [ -b "/dev/$dev" ]; then
                ret=1
                break
            fi
        fi
    done
    return "$ret"
}

## Emit a global declare -p string
#
# Parameters:
#   name - the name of the global variable to emit.
#
# This is a hack to work around the fact that the bash 'declare -p'
# builtin discards the -g (global) attribute when emitting variable
# declarations. This causes configuration values that are sourced
# in a shell function to become local in scope regardless of the
# attributes of the variable they are intended to recreate.
_declare_p_global() {
    declare -p "$1" | sed 's/^declare -\([aAfFiIlnrtux]\)/declare -g\1/'
}

# vim: set et ts=4 sw=4 :
