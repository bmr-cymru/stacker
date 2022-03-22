#!/bin/bash

# Stacker - partitionable disk template initialisation

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
#

_sysfs_block_device_state() {
    local dev="$1"
    cat "/sys/block/$dev/device/state" 2>/dev/null
}

_check_partition_state() {
    # Examine the partition layout on dev_path and return success
    # if it matches parts_file or failure otherwise.
    local dev_path="$1"
    local parts_file="$2"
    local esc_dev_path=$(printf $dev_path|sed -e 's/\//\\\//g')
    local part_idx=0
    local num_parts
    local pline
    local err
    local _ifs
    declare -a pvals
    declare -a parts_spec
    declare -a parts_disk
    stktrace "_check_partition_state $@"
    for pline in $(cat "$LAYER_DIR/$parts_file"); do
        if ! [[ $pline =~ \+.* ]]; then
            continue
        fi
        parts_spec["$part_idx"]=$(("${pline#+}" + 1))
        ((part_idx++))
    done
    num_parts="$part_idx"
    stktrace "Found $num_parts partitions in $parts_file"
    parts_disk=($(fdisk -l $dev_path | awk "/^$esc_dev_path/{print \$4}"))
    for (( part_idx=0; part_idx<num_parts; part_idx++ )); do
        if [[ ${parts_disk[$part_idx]} != ${parts_spec[$part_idx]} ]]; then
            err="${parts_disk[$part_idx]} != ${parts_spec[$part_idx]}"
            stktrace "Partition mismatch index=$part_idx ($err)"
            return 1
        fi
    done
    stktrace "On-disk partitions match $parts_file"
    return 0
}

_check_partition_nodes() {
    # Examine the /dev directory and return success if the device nodes
    # specified by parts_file are present.
    local dev_path="$1"
    local parts_file="$2"
    local new_part
    local pline
    local partsep
    if [[ "$dev_path" =~ .*nvme.* ]]; then
        partsep="p"
    fi
    cat "$LAYER_DIR/$parts_file" | while read pline; do
        if [[ $new_part == 1 ]]; then
            if ! [ -b "${dev_path}${partsep}${pline}" ]; then
                return 1
            fi
            new_part=0
        fi
        if [[ $pline == "p" ]]; then
            new_part=1
        fi
    done
    return $?
}

set_up() {
    stkdebug "Setting up $LAYER_NAME (type=$LAYER_TYPE)"
    _apply_partitions "$DEV_PATH"
}

tear_down() {
    stkdebug "Tearing down $LAYER_NAME"
    wipefs -a "$DEV_PATH"
}

status() {
    local ret=1
    local status="error"
    if [ -b "$DEV_PATH" ]; then
        if [ -f "/sys/block/$LAYER_NAME/device/state" ]; then
            SYSFS_STATE=$(_sysfs_block_device_state "$LAYER_NAME")
            if [ "$SYSFS_STATE" == "running" ]; then
                ret=0
                if _check_partition_state "$DEV_PATH" "$LAYER_NAME.parts"; then
                    if _check_partition_nodes "$DEV_PATH" "$LAYER_NAME.parts"; then
                        status="running"
                    else
                        status="ready"
                    fi
                else
                    status="configured"
                fi
            fi
       else
            ret=0
            if _check_partition_state "$DEV_PATH" "$LAYER_NAME.parts"; then
                if _check_partition_nodes "$DEV_PATH" "$LAYER_NAME.parts"; then
                    status="running"
                else
                    status="ready"
                fi
            else
                status="configured"
            fi
        fi
    else
        status="error"
    fi
    stkdebug "$LAYER_NAME status: $status"
    printf "%s\n" $status
    return $ret
}

