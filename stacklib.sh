#!/bin/bash

# stacklib.sh - stacker scripting interface

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

#
# Functions to control and interact with the stacker environment
#

# Begin a new stack definition.
#
# Parameters:
#   name The name of the new device stack.
#
# This function creates a new empty stack configuration called 'name'.
# Subsequent calls to stack definition functions will affect this stack
# by default.
stk_new() {
    local name="$1"
    shift
    declare -g STACK_NAME="$name"
    declare -g STACK_DIR="$STACKER_STACKS/$name"
    declare -g STACK_TOP=0
    declare -g _STACK_WRITTEN
    if [ ! -e "$STACK_DIR" ]; then
        if ! mkdir "$STACK_DIR"; then
            stkfatal "Could not create stack directory $STACK_DIR"
            exit 1
        fi
    else
        stkfatal "stack exists: $name"
        exit 1
    fi
    stkinfo "Beginning new stack $name at $STACK_DIR"
    declare -gA LAYERS
    declare -gA DEV_PATHS
    declare -gA DEV_SIZES
}

## Load an existing stack definition.
#
# Parameters:
#   name The name of the device stack.
#
# This function loads an existing stack definition named 'name' and
# allows the running script to interact with it and define or modify
# the stack layers.
stk_load() {
    local name="$1"
    local stack_conf
    local layers
    local layer
    local lname
    local lnum
    shift
    declare -g STACK_NAME="$name"
    declare -g STACK_DIR="$STACKER_STACKS/$name"
    declare -g _STACK_WRITTEN
    declare -gA LAYERS

    if ! [[ -d "$STACK_DIR" ]]; then
        stkfatal "Could not load stack '$name': stack directory not found"
        exit 1
    fi

    stack_conf="$STACK_DIR/stack.conf"
    if ! [[ -f "$stack_conf" ]]; then
        stkfatal "Stack configuration file $stack_conf not found"
        exit 1
    fi
    . $stack_conf

    layers=("$STACK_DIR"/[0-9][0-9]-*)
    for layer in ${layers[@]}; do
        lname=$(basename "$layer")
        lnum=${lname%%-*}
        lname=${lname##[0-9][0-9]-}
        LAYERS["$lname"]="$lnum"
    done
}

## End a stack definition.
#
# Parameters:
#  None
#
# End the current stack definition and write the configuration
# to stack.conf.
stk_end() {
    local conf_file="$STACK_DIR/stack.conf"
    stkdebug "Writing stack coniguration to $conf_file"
    stkdebug "Stack top is: $STACK_TOP"
    printf "%s\n" "# Stacker configuration file ($STACK_NAME)" > "$conf_file"
    if [[ ${DEV_PATHS[*]} ]]; then
        _declare_p_global DEV_PATHS >> "$conf_file"
    fi
    if [[ ${DEV_SIZES[*]} ]]; then
        _declare_p_global DEV_SIZES >> "$conf_file"
    fi
    _declare_p_global STACK_TOP >> "$conf_file"
    _STACK_WRITTEN=1
}

## Start a previously configured stack
#
# Parameters:
#
#  name - the name of the stack to be started.
stk_start() {
    stkr_start "$@"
}

## Attempt to stop a previously configured stack
#
# Parameters:
#
#  name - the name of the stack to be stopped.
stk_stop() {
    stkr_stop "$@"
}

#
# Internal helper functions
#

_layer_types_init() {
    local lpath
    local lname
    declare -gA LAYER_TYPES
    for lpath in "$stackerbasedir"/layers/[^_]*; do
        lname=$(basename "$lpath")
        LAYER_TYPES["$lname"]="$lpath"
    done
}

_install_layer() {
    # install_layer <type> <name>
    local ltype="$1"
    local lname="$2"
    local lnum="$3"
    local target="${LAYER_TYPES[$ltype]}"
    local linkname="$STACK_DIR/$lnum-$lname"
    stktrace "Installing layer $lnum-$lname -> $ltype into $STACK_DIR"
    if [ "$target" == "" ]; then
        stkfatal "Unknown layer type: $ltype"
        exit 127
    fi
    if ! target=$(realpath --relative-to "$STACK_DIR" "$target"); then
        stkfatal "Could not normalise link path $target"
        exit 1
    fi
    if ! ln -s "$target" "$linkname"; then
        stkfatal "Could not create layer symlink $linkname -> $target"
        exit 1
    fi
    LAYERS["$lname"]="$lnum"
}

_in_stack() {
    if [ "$STACK_NAME" != "" ]; then
        return 0
    else
        return 0
    fi
}

_check_in_stack() {
    local stack_fn="$1"
    if ! _in_stack; then
        stkfatal "No stack defined: $stack_fn() called before stk_new()"
        exit 1
    fi
}
#
# Functions for defining devices
#

_part_conf() {
    # _part_conf <name> <part_fmt> [part_args]
    #
    local name="$1"
    shift
    local part_fmt="$1"
    shift
    local dev_size
    local ptype
    local part_idx=1
    local part_size
    local num_parts
    local parts_file
    local part_name
    local space_used
    local fmt_idx
    local psize
    local idx
    declare -a part_sizes
    stktrace "_part_conf $name $part_fmt $@"
    parts_file="${STACK_DIR}/${name}.parts"
    if [[ "$1" != "--gpt" ]] && [[ "$1" != "--mbr" ]]; then
        stkfatal "Invalid partition spec: $@"
        exit 1
    else
        ptype=${1##--}
        shift
    fi
    if ! [[ $part_fmt =~ .*%d ]]; then
        stkfatal "Invalid partition name format: '$part_fmt'"
        exit 1
    fi
    dev_size="${DEV_SIZES["$name"]}"
    stktrace "Whole device size: $dev_size"
    for part_size in "$@"; do
        if [[ $part_size == "-" ]]; then
            space_used=2049
            if [[ $ptype == "gpt" ]]; then
                ((space_used += 33))
            fi
            for (( idx=1; idx<part_idx; idx++ )); do
                ((space_used += 2048 + ${part_sizes[$idx]}))
            done
            psize="$((dev_size - space_used))"
            stktrace "Fixed space: $space_used, final partition: $psize"
            if ((psize <= 2048)); then
                stkfatal "Partition layout larger than device: $@ ($dev_size)"
                exit 1
            fi
            part_sizes["$part_idx"]="$((dev_size - space_used))"
        elif ! part_sizes["$part_idx"]=$(parse_units -s "$part_size"); then
            stkfatal "Invalid partition size string: $part_size"
            stkfatal "Could not parse partition spec: --$ptype $@"
            exit 1
        fi
        if ! part_name=$(printf "$part_fmt" "$part_idx"); then
            stkfatal "Could not format partition name: $part_fmt $part_idx"
            exit 1
        fi
        DEV_PATHS["$part_name"]="/dev/$part_name"
        DEV_SIZES["$part_name"]="${part_sizes[$part_idx]}"
        ((part_idx++))
    done
    num_parts="$((part_idx - 1))"
    stkdebug "Parsed $num_parts partitions ${part_sizes[*]}"
    (
        if [[ "$ptype" == "gpt" ]]; then
            printf "g\n"
        else
            printf "o\n"
        fi
        for (( part_idx=1; part_idx<=num_parts; part_idx++)); do
            printf "n\n"
            if [[ "$ptype" == "mbr" ]]; then
                printf "p\n"
            fi
            printf "$part_idx\n"
            printf "\n"
            if [[ ${part_sizes[$part_idx]} != "0" ]]; then
                printf "+$((${part_sizes[$part_idx]} - 1))\n"
            else
                printf "\n"
            fi
        done
        printf "w\n"
    ) > "$parts_file"
    stkdebug "Wrote partition layout to $parts_file"
    return 0
}

_loop_conf() {
    # loop_conf <loopN> <SizeMB>
    # loopN.conf format:
    #   BACKING_FILE="/var/.../loopN.img"
    #   BACKING_FILE_SIZE="$loop_size"

    local name="$1"
    local loop_size="$2"
    cat > "${STACK_DIR}/${name}.conf" <<EOF
BACKING_FILE="$STACK_DIR/$name.img"
BACKING_FILE_SIZE="${loop_size}"
EOF
}

loop_dev() {
    # loop_dev <loopN> <Size> [partitions]
    local name="$1"
    shift
    local loop_size
    local lnum=00
    local lost
    stktrace "loop_dev $@"
    if ! loop_size=$(parse_units "$1"); then
        stkfatal "Could not parse loop device size: $1"
        exit 1
    fi
    shift
    _check_in_stack loop_dev || return 1
    _check_name "$name"
    if ! [[ "$name" =~ ^loop[0-9]+$ ]]; then
        stkfatal "Invalid loop device name: $name"
        exit 1
    fi

    if ! [[ "$loop_size" =~ ^[0-9]+$ ]]; then
        stkfatal "Invalid size for loop device $name: $size"
        exit 1
    fi

    lost=$((loop_size % 512))
    if [ "$lost" != "0" ]; then
        stkwarn "$name size is not a whole number of sectors ($lost bytes lost)"
    fi

    DEV_PATHS["$name"]="/dev/$name"
    DEV_SIZES["$name"]=$((loop_size >> 9))
    _install_layer loop "$name" "$lnum"
    _loop_conf "$name" "$loop_size"
    _part_conf "$name" "${name}p%d" "$@"
    stkinfo "Configured $name as $lnum-$name -> loop"
}

_disk_conf() {
    local name="$1"
    local disk_size="$2"
    cat > "${STACK_DIR}/${name}.conf" <<EOF
DISK_SIZE="${disk_size}"
EOF
}

_disk_dev() {
    stktrace "_disk_dev $@"
    local disk_type="$1"
    shift
    local part_fmt="$1"
    shift
    local name="$1"
    shift
    local size_arg
    local size_err
    local size
    local lnum=00
    if ! size_arg=$(parse_units -s "$1"); then
        stkfatal "Could not parse $disk_type disk size: $1"
        return 1
    fi
    shift
    if ! size=$(dev_sectors "/dev/$name"); then
        stkfatal "Could not determine size of $name"
    fi
    stkdebug "Device $name size=$size size_arg=$size_arg"
    if ((size < size_arg)); then
        size_err="($(size_to_units "$size" < $(size_to_units "$size_arg"))"
        stkfatal "Device too small: $name $size_err"
    fi
    DEV_PATHS["$name"]="/dev/$name"
    DEV_SIZES["$name"]="$size"
    _install_layer "$disk_type" "$name" "$lnum"
    _disk_conf "$name" "$size"
    _part_conf "$name" "${name}${part_fmt}" "$@"
    stkinfo "Configured $name as $lnum-$name -> $disk_type"
}

sd_dev() {
    # sd_dev <sdX> <MinSize> [partitions]
    stkinfo "sd_dev $@"
    _check_in_stack sd_dev || return 1
    _disk_dev sd "%d" "$@"
}

vd_dev() {
    # vd_dev <vdX> <MinSize> [partitions]
    stkdebug "vd_dev $@"
    _check_in_stack vd_dev || return 1
    _disk_dev vd "%d" "$@"
}

nvme_dev() {
    # vd_dev <nvmeXnY> <MinSize> [partitions]
    _check_in_stack nvme_dev || return 1
    _disk_dev nvme "p%d" "$@"
}

_linear_conf() {
    # linear_conf <linearN> [<devices>]
    local name="$1"
    shift
    local devices=("$@")
    cat > "${STACK_DIR}/${name}.conf" <<EOF
DEVICES=(${devices[@]})
EOF
}

_parse_linear_devices() {
    if [[ "$1" == "--size" ]] || [[ "$1" == "-s" ]]; then
        local size=1
        shift
    fi
    local devargs=("$@")
    local devices=()
    local dev_str
    local dev_path
    local dev_size=0
    local start=0
    local offset=0
    local length=0
    local range=""
    local sectors
    # shellcheck disable=SC2153
    for dev_str in "${devargs[@]}"; do
        dev="${dev_str%%:*}"
        # shellcheck disable=SC2153
        dev_path="${DEV_PATHS[$dev]}"
        range="${dev_str##*:}"
        offset="${range%%+*}"
        length="${range##*+}"
        dev_size="${DEV_SIZES[$dev]}"
        if ! [[ $dev_path ]] || ! [[ $dev_size ]]; then
            stkerror "Unknown device: $dev"
            return 1
        fi
        if [[ $offset == "" ]] || [[ $offset == "$range" ]]; then
            offset=0
        fi
        if [[ $length == "" ]] || [[ $length == "$range" ]]; then
            length="$((dev_size << 9))"
        fi
        if ! [[ "$size" ]]; then
            stktrace "parsing $name member $dev range=$range offset=$offset length=$length"
            if ! offset=$(parse_units -s "$offset"); then
                stkerror "Could not parse offset value: $offset"
                return 1
            fi
            if ! length=$(parse_units -s "$length"); then
                stkerror "Could not parse length value: $length"
                return 1
            fi
        fi
        ((start += length))
        devices+=("$dev:$offset+$length")
    done
    sectors="$start"
    if ! [[ "$size" ]]; then
        stkdebug "Normalized linear devices: ${devices[*]} sectors=$sectors"
    fi
    if ! [[ "$size" ]]; then
        printf "%s\n" "${devices[@]}"
    else
        printf "%d\n" "$sectors"
    fi
}

_check_name() {
    local name="$1"
    local valid_chars="a-zA-Z0-9_-"
    local i
    if [[ "${LAYERS[$name]}" ]]; then
        stkfatal "Duplicate device name: $name (already assigned to ${LAYERS[$name]}-${name})"
        exit 1
    fi
    for ((i=0; i < ${#name}; i++)); do
        if ! [[ "${name:$i:1}" =~ [$valid_chars] ]]; then
            stkfatal "Invalid character in device name $name: '${name:$i:1}'"
            exit 1
        fi
    done
    return 0
}

_find_layer() {
    local devices=("$@")
    local dev
    local dev_lnum
    local max_lnum=0
    local lnum

    for dev in "${devices[@]}"; do
        stkdebug "Looking up layer for $dev"
        if [[ $dev =~ loop[0-9]*p[0-9] ]]; then
            dev="${dev%p[0-9]*}"
        fi
        if [[ $dev =~ (vd|sd)[a-z]*[0-9] ]]; then
            dev="${dev%[0-9]*}"
        fi
        if [[ ":" =~ [$dev] ]]; then
            dev="${dev%:*}"
        fi
        dev_lnum="${LAYERS[$dev]}"
        if ! [[ "$dev_lnum" ]]; then
            stkfatal "No layer index found for $dev"
            return 1
        fi
        if ((dev_lnum > max_lnum)); then
            max_lnum="$dev_lnum"
        fi
    done
    lnum="$max_lnum"
    # Make space for insertions
    if ((lnum % 10)); then
        ((lnum += (10 - max_lnum % 10) ))
    fi
    if (((lnum - max_lnum) < 3)); then
        ((lnum+=10))
    fi

    printf "%02d\n" "$lnum"
}

## Define a new linear device-mapper device in the current stack.
#
# Parameters:
#   name - The device-mapper name of the new device
#   devices* - one or more devices to be mapped by the new device
#
# Defines a new linear device mapping one or more previously
# defined devices. Devices are specified by name with an optional
# suffix giving an offset and length for the mapping. Offsets and
# length values are given as integer strings with optional unit
# suffix.
#
# Examples:
#   linear_dev l0 loop0 loop1  # Map the whole of /dev/loop{0,1}
#   linear_dev l1 loop0:0+512M # Map the first 512M of /dev/loop0
#   linear_dev l1 sda:0+1G sdb:1+1G # Map the first 1GiB of sda
#                                   # and the 2nd 1GiB of sdb.
linear_dev() {
    local name="$1"
    shift
    local devices=("$@")
    local lnum
    local dev
    _check_in_stack linear_dev
    _check_name "$name"

    if [[ "${LAYERS[$name]}" ]]; then
        stkfatal "Duplicate device name: $name (already assigned to ${LAYERS[$name]}-${name})"
        exit 1
    fi

    if ! devices=($(_parse_linear_devices "${devices[@]}")); then
        stkfatal "Could not parse devices: ${devices[*]}"
        exit 1
    fi
    if ! lnum=$(_find_layer "${devices[@]}"); then
        stkfatal "Could not determine layer number for $name"
        exit 1
    fi
    if ! DEV_SIZES["$name"]=$(_parse_linear_devices -s "${devices[@]}"); then
        stkfatal "Could not determine linear device size for $name"
        exit 1
    fi
    ((lnum > $STACK_TOP)) && STACK_TOP="$lnum"
    DEV_PATHS["$name"]="/dev/mapper/$name"
    _install_layer linear "$name" "$lnum"
    _linear_conf "$name" "${devices[@]}"
    stkinfo "Configured $name as $lnum-$name -> linear"
}

_thin_check_feature_arg() {
    local arg="$1"
    shift
    local allowed=("$@")
    for allow in "${allowed[@]}"; do
        if [[ "$arg" == "$allow" ]]; then
            return 0
        fi
    done
    return 1
}

## Define a new thin-pool device-mapper device in the current stack.
#
# Parameters
#   name - The device-mapper name of the pool device
#   metadata_dev - The metadata device for the pool
#   data_dev - The data device for the pool
#   block_size - The data block size for the pool
#   low_water_mark - The pool space water mark at which a dm event is emitted
#
thin_pool() {
    local name="$1"
    local metadata_dev="$2"
    local data_dev="$3"
    local block_size="${4:-128}"
    local low_water_mark="${5:-128}"
    shift 5
    local feature_args=("$@")
    local feature_arg
    local allow_feature_args=(
        "skip_block_zeroing"
        "ignore_discard"
        "no_discard_passdown"
        "read_only"
        "error_if_no_space"
    )
    local lnum
    local devices=("$metadata_dev" "$data_dev")
    local min_block_size=128
    local max_block_size=2097152
    _check_in_stack thin_pool
    _check_name "$name"

    if [[ "${LAYERS[$name]}" ]]; then
        stkfatal "Duplicate device name: $name (already assigned to ${LAYERS[$name]}-${name})"
        exit 1
    fi

    if ((block_size < min_block_size)); then
        stkfatal "Thin pool data_block_size cannot be < $min_block_size sectors (found $block_size)"
        exit 1
    fi
    if ((block_size > max_block_size)); then
        stkfatal "Thin pool data_block_size cannot be > $max_block_size sectors (found $block_size)"
        exit 1
    fi
    for feature_arg in "${feature_args[@]}"; do
        if ! _thin_check_feature_arg "$feature_arg" "${allow_feature_args[@]}"; then
            stkfatal "Unknown thin-pool feature argument: $feature_arg"
            exit 1
        fi
    done

    if ! lnum=$(_find_layer "${devices[@]}"); then
        stkfatal "Could not determine layer number for $name"
        exit 1
    fi

    ((lnum > $STACK_TOP)) && STACK_TOP="$lnum"
    DEV_PATHS["$name"]="/dev/mapper/$name"
    DEV_SIZES["$name"]=DEV_SIZES["$data_dev"]
    _install_layer thin-pool "$name" "$lnum"
    cat > "${STACK_DIR}/${name}.conf" <<EOF
DEVICES=(${devices[@]})
METADATA_DEVICE=${metadata_dev}
DATA_DEVICE=${data_dev}
DATA_BLOCK_SIZE=${block_size}
LOW_WATER_MARK=${low_water_mark}
FEATURE_ARGS=(${feature_args[@]})
EOF
    stkinfo "Configured $name as $lnum-$name -> thin-pool"
}

thin_dev() {
    local name="$1"
    local pool_dev="$2"
    local dev_id="$3"
    local dev_size="$4"
    local devices=("$pool_dev")
    local lnum
    _check_in_stack thin_dev
    _check_name "$name"

    if ((dev_id < 0)); then
        stkfatal "Invalid thin_dev_id: $dev_id"
        exit 1
    fi

    if ! [[ "${LAYERS["$pool_dev"]}" ]]; then
        stkfatal "Unknown pool device: $pool_dev"
        exit 1
    fi

    if ! dev_size=$(parse_units -s "$dev_size"); then
        stkfatal "Could not parse thin device size: $dev_size"
        exit 1
    fi

    if ! lnum=$(_find_layer "${devices[@]}"); then
        stkfatal "Could not determine layer number for $name"
        exit 1
    fi

    ((lnum > $STACK_TOP)) && STACK_TOP="$lnum"
    DEV_PATHS["$name"]="/dev/mapper/$name"
    DEV_SIZES["$name"]="$dev_size"
    _install_layer thin "$name" "$lnum"
    cat > "${STACK_DIR}/${name}.conf" <<EOF
DEVICES=(${devices[@]})
POOL_DEVICE="${pool_dev}"
THIN_DEV_ID="${dev_id}"
THIN_DEV_SIZE="${dev_size}"
EOF
    stkinfo "Configured $name as $lnum-$name -> thin"
}

cache_dev() {
    local name="$1"
    local metadata_dev="$2"
    local cache_dev="$3"
    local origin_dev="$4"
    local block_size="${5:-512}"
    local mode="${6:-writeback}"
    local policy="${7:-default}"
    local lnum
    local devices=("$metadata_dev" "$cache_dev" "$origin_dev")
    local min_block_size=64
    local max_block_size=2097152
    _check_in_stack cache
    _check_name "$name"

    if ((block_size < min_block_size)); then
        stkfatal "Cache block_size cannot be < $min_block_size sectors (found $block_size)"
        exit 1
    fi
    if ((block_size > max_block_size)); then
        stkfatal "Cache block_size cannot be > $max_block_size sectors (found $block_size)"
        exit 1
    fi
    if ((block_size % 64)); then
        stkfatal "Cache block size must be a multiple of 64 sectors"
        exit 1
    fi
    if ! lnum=$(_find_layer "${devices[@]}"); then
        stkfatal "Could not determine layer number for $name"
        exit 1
    fi

    ((lnum > $STACK_TOP)) && STACK_TOP="$lnum"
    DEV_PATHS["$name"]="/dev/mapper/$name"
    DEV_SIZES["$name"]=DEV_SIZES["$origin_dev"]
    _install_layer cache "$name" "$lnum"
    cat > "${STACK_DIR}/${name}.conf" <<EOF
DEVICES=(${devices[@]})
METADATA_DEVICE=${metadata_dev}
CACHE_DEVICE=${cache_dev}
ORIGIN_DEVICE=${origin_dev}
BLOCK_SIZE=${block_size}
CACHE_MODE=${mode}
EOF
    stkinfo "Configured $name as $lnum-$name -> cache"
}

_writecache_check_feature_arg() {
    local arg="$1"
    shift
    local allowed=("$@")
    local value
    for allow in "${allowed[@]}"; do
        if [[ "$arg" =~ $allow ]]; then
            value="${BASH_REMATCH[1]}"
            if [[ "=" =~ [$arg] ]]; then
                printf "%s %s\n" "${arg%%=*}" "$value"
            else
                printf "%s\n" "$arg"
            fi
            return 0
        fi
    done
    return 1
}

writecache_dev() {
    stktrace "writecache_dev $@"
    local name="$1"
    local cache_type="$2"
    local cache_dev="$3"
    local origin_dev="$4"
    local block_size="${5:-4096}"
    shift 5
    stktrace "writecache feature args: $@"
    local feature_args=("$@")
    local feature_arg
    local allow_feature_args=(
        "start_sector=([0-9]*)"
        "high_watermark=([0-9]*)"
        "low_watermark=([0-9]*)"
        "writeback_jobs=([0-9]*)"
        "autocommit_blocks=([0-9]*)"
        "autocommit_time=([0-9]*)"
        "fua"
        "nofua"
        "cleaner"
        "max_age=([0-9]*)"
        "metadata_only"
        "pause_writeback=([0-9*)"
    )
    local arg
    local lnum
    local devices=("$cache_dev" "$origin_dev")
    local min_block_size=512
    local max_block_size=4096
    declare -a optional_args
    _check_in_stack writecache
    _check_name "$name"

    if ((block_size < min_block_size)); then
        stkfatal "Writecache block_size cannot be < $min_block_size sectors (found $block_size)"
        exit 1
    fi
    if ((block_size > max_block_size)); then
        stkfatal "Writecache block_size cannot be > $max_block_size sectors (found $block_size)"
        exit 1
    fi
    # FIXME: check block_size >= device logical block size

    for feature_arg in "${feature_args[@]}"; do
        stktrace "Checking writecache feature_arg $feature_arg"
        if ! arg=$(_writecache_check_feature_arg "$feature_arg" "${allow_feature_args[@]}"); then
            stkfatal "Invalid writecache feature argument: $feature_arg"
            exit 1
        fi
        optional_args+=($arg) # args with value split to two array elements
    done

    stkdebug "Parsed ${#optional_args[*]} optional arguments: ${optional_args[*]}"

    if ! lnum=$(_find_layer "${devices[@]}"); then
        stkfatal "Could not determine layer number for $name"
        exit 1
    fi

    ((lnum > $STACK_TOP)) && STACK_TOP="$lnum"
    DEV_PATHS["$name"]="/dev/mapper/$name"
    DEV_SIZES["$name"]=DEV_SIZES["$origin_dev"]
    _install_layer writecache "$name" "$lnum"
    cat > "${STACK_DIR}/${name}.conf" <<EOF
DEVICES=(${devices[@]})
CACHE_TYPE=${cache_type}
CACHE_DEVICE=${cache_dev}
ORIGIN_DEVICE=${origin_dev}
BLOCK_SIZE=${block_size}
OPTIONAL_ARGS=(${optional_args[*]})
EOF
    stkinfo "Configured $name as $lnum-$name -> writecache"
}

#
# Init hooks
#

_layer_types_init

# vim: set et ts=4 sw=4 :
