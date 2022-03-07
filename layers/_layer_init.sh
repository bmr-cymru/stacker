#!/bin/bash

# Stacker - layer template initialisation

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

LAYER=$(basename "$LAYER_PATH")
LAYER_DIR=$(dirname "$LAYER_PATH")
LAYER_NAME="${LAYER#[0-9][0-9]-}"
LAYER="${LAYER%-*}"

stackerbasedir=$(dirname "$(readlink -f "$LAYER_PATH")")/..
stackerbasedir=$(realpath "$stackerbasedir")
# shellcheck source=../stacker-functions.sh
. "$stackerbasedir"/stacker-functions.sh
# shellcheck source=../stacklog.sh
. "$stackerbasedir"/stacklog.sh

# Test whether or not we appear to be running under the stkr harness or not;
# this is a hack to allow simple testing of layer template scripts from the
# command-line:
#
# # /var/lib/stacker/stacks/thin/00-loop0 status
# ready
#
# The layer will log to its own log file named $LAYER_NAME.log to avoid
# clobbering /var/log/stacker.log.
if ! [[ "$__STACKER_LOGGER__" ]]; then
    TMPDIR="$LAYER_DIR/tmp"
    mkdir -p "$TMPDIR"
    # shellcheck disable=SC2034
    STACKER_TMPDIR=$(mktemp -p "$TMPDIR/" -d -t stacker.XXXXXX)

    logfile="$(realpath "$LAYER_DIR"/"$LAYER_NAME".log)"
    fileloglvl=6

    stklog_init
fi

# Load stack configuration
STACK_CONF="${LAYER_DIR}/stack.conf"
# shellcheck disable=SC2154
if [ "$__stack_conf__" == "" ]; then
    # shellcheck disable=SC1090
    . "$STACK_CONF"
fi

# Load layer configuration
LAYER_CONF="${LAYER_DIR}/${LAYER_NAME}.conf"
# shellcheck disable=SC1090
. "$LAYER_CONF"

DEV_PATH="/dev/$LAYER_NAME"

_apply_partitions() {
    local out_path="$1"
    local parts_file
    parts_file="${LAYER_DIR}/${LAYER_NAME}.parts"
    stkdebug "Applying partition layout from $parts_file to $out_path"
    if [[ -f $parts_file ]]; then
        fdisk "$out_path" < "$parts_file" 1>/dev/null
    fi
}

check_status() {
    local lstatus
    local expect="$1"
    shift
    lstatus=$(status)
    if [ "$expect" != "" ]; then
        if [ "$lstatus" == "$expect" ]; then
            return 0
        fi
    else
        if [ "$lstatus" != "error" ]; then
            return 0
        fi
    fi
    return 1
}

set_up() {
    stkdebug "Setting up $LAYER_NAME (type=$LAYER_TYPE)"
}

tear_down() {
    stkdebug "Tearing down $LAYER_NAME"
}

start() {
    stkdebug "Starting $LAYER_NAME"
}

dm_stop() {
    dmsetup remove "$LAYER_NAME"
}

stop() {
    stkinfo "Stopping $LAYER_NAME"
    if ! check_status running; then
        stkerror "Layer not running $LAYER_NAME"
        return 1
    fi
    if [[ $DM_LAYER == 1 ]]; then
        dm_stop
    fi
}

resume() {
    if ! [[ $DM_LAYER == 1 ]]; then
        stkerror "$LAYER_TYPE does not support resume"
        return 1
    fi
    stkinfo "Resuming $LAYER_NAME"
    dmsetup resume "$LAYER_NAME"
}

suspend() {
    if ! [[ $DM_LAYER == 1 ]]; then
        stkerror "$LAYER_TYPE does not support suspend"
        return 1
    fi
    stkinfo "Suspending $LAYER_NAME"
    dmsetup suspend "$LAYER_NAME"
}

dm_status() {
    if ! [[ $DM_LAYER == 1 ]]; then
        stkerror "$LAYER_TYPE does not support dmstatus"
        return 1
    fi
    dmsetup status "$LAYER_NAME"
}

# All layer templates must override status.
status() {
    printf "%s\n" error
}

dev_path() {
    printf "%s\n" "$DEV_PATH"
}

_layer_main() {
    case "$1" in
      set_up)
          set_up
          ;;
      tear_down)
          tear_down
          ;;
      start)
          start
          ;;
      stop)
          stop
          ;;
      restart)
          stop
          start
          ;;
      status)
          status
          ;;
      dev_path)
          dev_path
          ;;
      *)
          echo "Usage: $LAYER_NAME {set_up|tear_down|start|stop|restart|status|dev_path}"
          return 1
    esac
}

_dm_layer_main() {
    declare -g DM_LAYER=1
    case "$1" in
      suspend)
          suspend
          return
          ;;
      resume)
          resume
          return
          ;;
      dmstatus)
          dm_status
          return
          ;;
      *)
          # Fall through to _layer_main()
          ;;
    esac
    _layer_main "$@"
}

# vim: set et ts=4 sw=4 :
