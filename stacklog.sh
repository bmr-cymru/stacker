#!/bin/bash

# stacklog.sh - Stacker logging module

# Based on dracut-logger.sh - https://github.com/dracutdevs/dracut
# Copyright 2010 Amadeusz Żołnowski <aidecoe@aidecoe.name>
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

export __STACKER_LOGGER__=1
export __STACKLOG_EXPORT_VARS__="sysloglvl stdloglvl fileloglvl logfile"

## @brief Logging facility module for stacker.
#
# @section intro Introduction
#
# The logger takes a bit from Log4j philosophy. There are defined 6 logging
# levels:
#   - TRACE (6)
#     The TRACE Level designates finer-grained informational events than the
#     DEBUG.
#   - DEBUG (5)
#     The DEBUG Level designates fine-grained informational events that are most
#     useful to debug an application.
#   - INFO (4)
#     The INFO level designates informational messages that highlight the
#     progress of the application at coarse-grained level.
#   - WARN (3)
#     The WARN level designates potentially harmful situations.
#   - ERROR (2)
#     The ERROR level designates error events that might still allow the
#     application to continue running.
#   - FATAL (1)
#     The FATAL level designates very severe error events that will presumably
#     lead the application to abort.
# Descriptions are borrowed from Log4j documentation:
# http://logging.apache.org/log4j/1.2/apidocs/org/apache/log4j/Level.html
#
# @section usage Usage
#
# First of all you have to start with stklog_init() function which initializes
# required variables. Don't call any other logging function before that one!
# If you're ready with this, you can use following functions which corresponds
# clearly to levels listed in @ref intro Introduction. Here they are:
#   - stktrace()
#   - stkdebug()
#   - stkinfo()
#   - stkwarn()
#   - stkerror()
#   - stkfatal()
# They take all arguments given as a single message to be logged. See stklog()
# function for details how it works. Note that you shouldn't use stklog() by
# yourself. It's wrapped with above functions.
#
# @see stklog_init() stklog()
#
# @section conf Configuration
#
# Logging is controlled by following global variables:
#   - @var stdloglvl - logging level to standard error (console output)
#   - @var sysloglvl - logging level to syslog (by logger command)
#   - @var fileloglvl - logging level to file
#   - @var kmsgloglvl - logging level to /dev/kmsg (only for boot-time)
#   - @var logfile - log file which is used when @var fileloglvl is higher
#   than 0
# and two global variables: @var maxloglvl and @var syslogfacility which <b>must
# not</b> be overwritten. Both are set by stklog_init(). @var maxloglvl holds
# maximum logging level of those three and indicates that stklog_init() was run.
# @var syslogfacility is set to 'user'.
#
# Logging level set by the variable means that messages from this logging level
# and above (FATAL is the highest) will be shown. Logging levels may be set
# independently for each destination (stderr, syslog, file, kmsg).
#
# @see stklog_init()


stklog_init() {
    local __oldumask
    local ret=0
    local errmsg
    [ -z "$stdloglvl" ] && stdloglvl=4
    [ -z "$sysloglvl" ] && sysloglvl=0

    # Skip initialization if it's already done.
    [ -n "$maxloglvl" ] && return 0
    if [ -z "$fileloglvl" ]; then
        fileloglvl=0
    elif ((fileloglvl > 0)); then
        if [[ $logfile ]]; then
            __oldumask=$(umask)
            # 0600 mode
            umask 0177
            ! [ -e "$logfile" ] && : > "$logfile"
            umask "$__oldumask"
            if [[ -w $logfile ]] && [[ -f $logfile ]]; then
                # Mark new run in the log file
                echo >> "$logfile"
                if command -v date > /dev/null; then
                    echo "=== $(date) ===" >> "$logfile"
                else
                    echo "===============================================" >> "$logfile"
                fi
                echo >> "$logfile"
            else
                # We cannot log to file, so turn this facility off.
                fileloglvl=0
                ret=1
                errmsg="'$logfile' is not a writable file"
            fi
        fi
    fi

    if ((sysloglvl > 0)); then
        if [[ -d /run/systemd/journal ]] \
            && type -P systemd-cat &> /dev/null \
            && systemctl --quiet is-active systemd-journald.socket &> /dev/null \
            && { echo "stacker-$STACKER_VERSION" | systemd-cat -t 'stacker' &> /dev/null; }; then
            readonly _systemdcatfile="$STACKER_TMPDIR/systemd-cat"
            mkfifo "$_systemdcatfile"
            readonly _dlogfd=15
            export _dlogfd
            systemd-cat -t 'stacker' --level-prefix=true < "$_systemdcatfile" &
            exec 15> "$_systemdcatfile"
        elif ! [[ -S /dev/log ]] && [[ -w /dev/log ]] || ! command -v logger > /dev/null; then
            # We cannot log to syslog, so turn this facility off.
            sysloglvl=0
            ret=1
            errmsg="No '/dev/log' or 'logger' included for syslog logging"
        fi
    fi

    if ((sysloglvl > 0)); then
        syslogfacility=${syslogfacility:=user}
        readonly syslogfacility
        export syslogfacility
    fi

    local lvl
    local maxloglvl_l=0
    for lvl in $stdloglvl $sysloglvl $fileloglvl $kmsgloglvl; do
        ((lvl > maxloglvl_l)) && maxloglvl_l=$lvl
    done
    readonly maxloglvl=$maxloglvl_l
    export maxloglvl

    if ((stdloglvl < 6)) && ((fileloglvl < 6)) && ((sysloglvl < 6)); then
        unset stktrace
        stktrace() { :; }
    fi

    if ((stdloglvl < 5)) && ((fileloglvl < 5)) && ((sysloglvl < 5)); then
        unset stkdebug
        stkdebug() { :; }
    fi

    if ((stdloglvl < 4)) && ((fileloglvl < 4)) && ((sysloglvl < 4)); then
        unset stkinfo
        stkinfo() { :; }
    fi

    if ((stdloglvl < 3)) && ((fileloglvl < 3)) && ((sysloglvl < 3)); then
        unset stkwarn
        stkwarn() { :; }
        unset stkwarning
        stkwarning() { :; }
    fi

    if ((stdloglvl < 2)) && ((fileloglvl < 2)) && ((sysloglvl < 2)); then
        unset stkerror
        stkerror() { :; }
    fi

    if ((stdloglvl < 1)) && ((fileloglvl < 1)) && ((sysloglvl < 1)); then
        unset stkfatal
        stkfatal() { :; }
    fi

    [ -n "$errmsg" ] && derror "$errmsg"

    return $ret
}

# @brief Converts numeric logging level to the first letter of level name.
#
# @param lvl Numeric logging level in range from 1 to 6.
# @retval 1 if @a lvl is out of range.
# @retval 0 if @a lvl is correct.
# @result Echoes first letter of level name.
_lvl2char() {
    case "$1" in
        1) echo F ;;
        2) echo E ;;
        3) echo W ;;
        4) echo I ;;
        5) echo D ;;
        6) echo T ;;
        *) return 1 ;;
    esac
}

## @brief Converts numeric level to logger priority defined by POSIX.2.
#
# @param lvl Numeric logging level in range from 1 to 6.
# @retval 1 if @a lvl is out of range.
# @retval 0 if @a lvl is correct.
# @result Echoes logger priority.
_lvl2syspri() {
    printf -- "%s" "$syslogfacility."
    case "$1" in
        1) echo crit ;;
        2) echo error ;;
        3) echo warning ;;
        4) echo info ;;
        5) echo debug ;;
        6) echo debug ;;
        *) return 1 ;;
    esac
}

## @brief Converts stacklog numeric level to syslog log level
#
# @param lvl Numeric logging level in range from 1 to 6.
# @retval 1 if @a lvl is out of range.
# @retval 0 if @a lvl is correct.
# @result Echoes kernel console numeric log level
#
# Conversion is done as follows:
#
# <tt>
#   none     -> LOG_EMERG (0)
#   none     -> LOG_ALERT (1)
#   FATAL(1) -> LOG_CRIT (2)
#   ERROR(2) -> LOG_ERR (3)
#   WARN(3)  -> LOG_WARNING (4)
#   none     -> LOG_NOTICE (5)
#   INFO(4)  -> LOG_INFO (6)
#   DEBUG(5) -> LOG_DEBUG (7)
#   TRACE(6) /
# </tt>
#
# @see /usr/include/sys/syslog.h
_stklvl2syslvl() {
    local lvl

    case "$1" in
        1) lvl=2 ;;
        2) lvl=3 ;;
        3) lvl=4 ;;
        4) lvl=6 ;;
        5) lvl=7 ;;
        6) lvl=7 ;;
        *) return 1 ;;
    esac

    [ "$syslogfacility" = user ] && echo $((8 + lvl)) || echo $((24 + lvl))
}

## @brief Prints to stderr and/or writes to file or syslog given message with
# given level (priority).
#
# @param lvl Numeric logging level.
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
#
# @note This function is not supposed to be called manually. Please use
# stktrace(), stkdebug(), or others instead which wrap this one.
#
# This is core logging function which logs given message to standard error, file
# and/or syslog (with POSIX shell command <tt>logger</tt>).
# The format is following:
#
# <tt>X: some message</tt>
#
# where @c X is the first letter of logging level. See module description for
# details on that.
#
# Message to syslog is sent with tag @c stacker. Priorities are mapped as
# following:
#   - @c FATAL to @c crit
#   - @c ERROR to @c error
#   - @c WARN to @c warning
#   - @c INFO to @c info
#   - @c DEBUG and @c TRACE both to @c debug
_do_stklog() {
    local lvlc
    local lvl="$1"
    shift
    lvlc=$(_lvl2char "$lvl") || return 0
    local msg="$*"
    local lmsg="$lvlc: $*"

    ((lvl <= stdloglvl)) && printf -- '%s\n' "$msg" >&2

    if ((lvl <= sysloglvl)); then
        if [[ "$_dlogfd" ]]; then
            printf -- "<%s>%s\n" "$(($(_stklvl2syslvl "$lvl") & 7))" "$msg" >&$_dlogfd
        else
            logger -t "stacker[$$]" -p "$(_lvl2syspri "$lvl")" -- "$msg"
        fi
    fi

    if ((lvl <= fileloglvl)) && [[ -w $logfile ]] && [[ -f $logfile ]]; then
        echo "$(date) $lmsg" >> "$logfile"
    fi
}

## @brief Internal helper function for _do_stklog()
#
# @param lvl Numeric logging level.
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
#
# @note This function is not supposed to be called manually. Please use
# stktrace(), stkdebug(), or others instead which wrap this one.
#
# This function calls _do_stklog() either with parameter msg, or if
# none is given, it will read standard input and will use every line as
# a message.
#
# This enables:
# stkwarn "This is a warning"
# echo "This is a warning" | stkwarn
stklog() {
    [ -z "$maxloglvl" ] && return 0
    (($1 <= maxloglvl)) || return 0

    if (($# > 1)); then
        _do_stklog "$@"
    else
        while read -r line || [ -n "$line" ]; do
            _do_stklog "$1" "$line"
        done
    fi
}

# @brief Logs message at TRACE level (6)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stktrace() {
    set +x
    stklog 6 "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

## @brief Logs message at DEBUG level (5)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stkdebug() {
    set +x
    stklog 5 "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

## @brief Logs message at INFO level (4)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stkinfo() {
    set +x
    stklog 4 "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

## @brief Logs message at WARN level (3)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stkwarn() {
    set +x
    stklog 3 "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

## @brief It's an alias to stkwarn() function.
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stkwarning() {
    set +x
    stkwarn "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

## @brief Logs message at ERROR level (2)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stkerror() {
    set +x
    stklog 2 "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

## @brief Logs message at FATAL level (1)
#
# @param msg Message.
# @retval 0 It's always returned, even if logging failed.
stkfatal() {
    set +x
    stklog 1 "$@"
    if [ -n "$debug" ]; then
        set -x
    fi
}

