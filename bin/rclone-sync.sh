#!/usr/bin/env bash
# Copyright (c) 2018 Herbert Shen <ishbguy@hotmail.com> All Rights Reserved.
# Released under the terms of the MIT License.

# source guard
[[ $RCLONE_SYNC_SOURCED -eq 1 ]] && return
declare -r RCLONE_SYNC_SOURCED=1
declare -r RCLONE_SYNC_ABS_SRC="$(realpath "${BASH_SOURCE[0]}")"
declare -r RCLONE_SYNC_ABS_DIR="$(dirname "$RCLONE_SYNC_ABS_SRC")"

# utilities
EXIT_CODE=0
warn() { echo -e "$@" >&2; ((++EXIT_CODE)); return ${WERROR:-1}; }
die() { echo -e "$@" >&2; exit $((++EXIT_CODE)); }
usage() { echo -e "$HELP"; }
version() { echo -e "$PRONAME $VERSION"; }
defined() { declare -p "$1" &>/dev/null; }
definedf() { declare -f "$1" &>/dev/null; }
is_sourced() { [[ -n ${FUNCNAME[1]} && ${FUNCNAME[1]} != "main" ]]; }
is_array() { local -a def=($(declare -p "$1" 2>/dev/null)); [[ ${def[1]} =~ a ]]; }
is_map() { local -a def=($(declare -p "$1" 2>/dev/null)); [[ ${def[1]} =~ A ]]; }
has_tool() { hash "$1" &>/dev/null; }
ensure() {
    local cmd="$1"; shift
    local -a info=($(caller 0))
    (eval "$cmd" &>/dev/null) || die "${info[2]}:${info[0]}:${info[1]}:" \
        "${FUNCNAME[0]} '$cmd' failed." "$@"
}
date_cmp() { echo "$(($(date -d "$1" +%s) - $(date -d "$2" +%s)))"; }
tmpfd() {
    local -a fds=($(ls /dev/fd)) &>/dev/null
    echo "$((${fds[$((${#fds[@]}-1))]:-99} + 1))"
}
pargs() {
    ensure "[[ $# -ge 3 ]]" "Need OPTIONS, ARGUMENTS and OPTSTRING"
    ensure "[[ -n $1 && -n $2 && -n $3 ]]" "Args should not be empty."
    ensure "is_map $1 && is_map $2" "OPTIONS and ARGUMENTS should be map."

    local -n __opt="$1"
    local -n __arg="$2"
    local optstr="$3"
    shift 3

    OPTIND=1
    while getopts "$optstr" opt; do
        [[ $opt == ":" || $opt == "?" ]] && die "$HELP"
        __opt[$opt]=1
        __arg[$opt]="$OPTARG"
    done
    shift $((OPTIND - 1))
}
chkobj() {
    ensure "[[ $# -gt 2 ]]" "Not enough args."
    ensure "definedf $1" "$1 should be a defined func."

    local -a miss
    local cmd="$1"
    local msg="$2"
    shift 2
    for obj in "$@"; do
        "$cmd" "$obj" || miss+=("$obj")
    done
    [[ ${#miss[@]} -eq 0 ]] || die "$msg: ${miss[*]}."
}
chkvar() { chkobj defined "You need to define vars" "$@"; }
chkfunc() { chkobj definedf "You need to define funcs" "$@"; }
chktool() { chkobj has_tool "You need to install tools" "$@"; }

# app funcs
rclone_do() {
    echo -e "$@"
    [[ -z $dry_run ]] && { "$@" || warn "Failed to do: $*"; } 
}
rclone_abs() { echo "$(($1 > 0? $1: -($1)))"; }
rclone_is_exist_dir() { rclone lsf "$1" &>/dev/null; }
rclone_is_empty_dir() { local out="$(rclone lsf "$1" 2>/dev/null)"; [[ -z $out ]]; }
rclone_first_sync() {
    local p1="$1"
    local p2="$2"
    local p1_empty p2_empty

    rclone_is_exist_dir "$p1" || rclone_do rclone mkdir "$p1" # || die "Can not mkdir $p1"
    rclone_is_exist_dir "$p2" || rclone_do rclone mkdir "$p2" # || die "Can not mkdir $p2"
    rclone_is_empty_dir "$p1" && p1_empty=1
    rclone_is_empty_dir "$p2" && p2_empty=1

    [[ $p1_empty || $p2_empty ]] || die "One of $p1 and $p2 should be empty."

    if [[ ! $p1_empty && $p2_empty ]]; then
        rclone_do rclone sync "$p1" "$p2"
    else
        rclone_do rclone sync "$p2" "$p1"
    fi
}
rclone_get_file_info() {
    local path="$1"
    local file="$2"
    local tmpfd=$(tmpfd)
    if [[ -n $file ]]; then
        eval "exec $tmpfd>&1"
        eval "exec 1>$file"
        # trap once
        trap "exec 1>&$tmpfd; exec $tmpfd>&-; trap '' RETURN" RETURN
    fi
    rclone lsf --format tp --csv --files-only -R "$path" | sort -t, -k2
}
rclone_read_file_info() {
    local -n files="$1"
    local info="$2"
    local old_ifs="$IFS"

    # info is csv file
    IFS=${3:-,}
    while read -r date file; do
        files[$file]="$date"
    done <"$info"
    IFS=$old_ifs
}
rclone_path_cat() {
    local -A ps
    for p in "$@"; do
        ps[${p//+(:|\/)/_}]=1
    done
    echo "${!ps[*]}"
}
rclone_set_inter() {
    local -n s1="$1"
    local -n s2="$2"
    local -n inter="$3"
    for e in "${!s1[@]}"; do
        [[ ${s2[$e]} ]] && inter[$e]=1
    done
}
rclone_set_diff() {
    local -n s1="$1"
    local -n s2="$2"
    local -n diff="$3"
    for e in "${!s1[@]}"; do
        [[ ${s2[$e]} ]] || diff[$e]=1
    done
}
rclone_sync_path() {
    local -n p1="$1"
    local -n p2="$2"
    local -n add="${1}_${2}_delta_add"
    local -n new="${1}_${2}_delta_new"
    local -n del="${1}_${2}_delta_del"

    for file in "${!add[@]}" "${!new[@]}"; do
        rclone_do rclone copyto "$p1/$file" "$p2/$file" && ((++sync_ok)) || ((++sync_fail))
    done
    for file in "${!del[@]}"; do
        rclone_do rclone deletefile "$p1/$file" && ((++sync_ok)) || ((++sync_fail))
    done
}
rclone_check_path() {
    local prev="$1_files_prev"
    local curr="$1_files_curr"
    local inter="$1_inter"
    local del="$1_delta_del"
    local add="$1_delta_add"
    local -n prev_ref="$prev"
    local -n curr_ref="$curr"
    local -n inter_ref="$inter"
    local -n del_ref="$del"
    local -n add_ref="$add"
    local -n new_ref="$1_delta_new"
    local -n old_ref="$1_delta_old"
    local -n uch_ref="$1_delta_uch"

    rclone_set_diff "$prev" "$curr" "$del"
    rclone_set_diff "$curr" "$prev" "$add"
    rclone_set_inter "$curr" "$prev" "$inter"
    for file in "${!inter_ref[@]}"; do
        local diff="$(date_cmp "${curr_ref[$file]}" "${prev_ref[$file]}")"
        if [[ $diff -gt 0 ]]; then
            new_ref[$file]=1
        elif [[ $diff -lt 0 ]]; then
            old_ref[$file]=1
        else
            uch_ref[$file]=1
        fi
    done
}
rclone_check_path_diff() {
    local -n p1p2_diff="$1_$2_diff"
    local -n p1p2_add="$1_$2_delta_add"
    local -n p1p2_del="$1_$2_delta_del"
    local -n p1_new="$1_delta_new"
    local -n p2_del="$2_delta_del"
    for file in "${!p1p2_diff[@]}"; do
        if [[ -z ${p2_del[$file]} ]]; then
            p1p2_add[$file]=1
        elif [[ ${p1_new[$file]} ]]; then
            p1p2_add[$file]=1
        else
            p1p2_del[$file]=1
        fi
    done

}
rclone_check_path_inter() {
    local -n p1="$1_files_curr"
    local -n p2="$2_files_curr"
    local -n p1p2_inter="$1_$2_inter"
    local -n p1p2_new="$1_$2_delta_new"
    local -n p1p2_old="$1_$2_delta_old"
    local -n p1p2_uch="$1_$2_delta_uch"
    local -n p2p1_new="$2_$1_delta_new"
    local -n p2p1_old="$2_$1_delta_old"
    local -n p2p1_uch="$2_$1_delta_uch"

    for file in "${!p1p2_inter[@]}"; do
        local diff="$(date_cmp "${p1[$file]}" "${p2[$file]}")"
        if [[ $diff -gt 0 ]]; then
            p1p2_new[$file]=1
            p2p1_old[$file]=1
        elif [[ $diff -lt 0 ]]; then
            p1p2_old[$file]=1
            p2p1_new[$file]=1
        else
            p1p2_uch[$file]=1
            p2p1_uch[$file]=1
        fi
    done
}
rclone_path_cmp() {
    local p1="$1_files_curr"
    local p2="$2_files_curr"
    local p1p2_inter="$1_$2_inter"
    local p1p2_diff="$1_$2_diff"
    local p2p1_diff="$2_$1_diff"

    rclone_set_inter "$p1" "$p2" "$p1p2_inter"
    rclone_set_diff "$p1" "$p2" "$p1p2_diff"
    rclone_set_diff "$p2" "$p1" "$p2p1_diff"
    rclone_check_path_diff "$1" "$2"
    rclone_check_path_inter "$1" "$2"
}
rclone_try() {
    local times=$1; shift
    for ((n = 0; n < times; n++)); do
        echo "Try $n time: $*"
        "$@" && { echo "Succeed."; return 0; } || echo "Failed!"
    done
    return 1
}

rclone_sync() {
    local PRONAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.0.1"
    local HELP=$(cat <<EOF
$PRONAME $VERSION
$PRONAME [-dhvD] path1 path2
    
    -d  dry run
    -h  print this help message 
    -v  print version number
    -D  turn on debug mode

This program is released under the terms of MIT License.
EOF
)
    local -A opts args
    local dry_run
    pargs opts args 'dhvD' "$@"
    shift $((OPTIND - 1))
    [[ ${opts[D]} ]] && set -x
    [[ ${opts[h]} ]] && usage && return 0
    [[ ${opts[v]} ]] && version && return 0
    [[ ${opts[d]} ]] && dry_run=1 && echo "Dry run"

    shopt -s extglob

    ensure "[[ $# -eq 2 && -n '$1' && -n '$2' ]]" "Need path1 and path2!\\n\\n$HELP"
    chktool rclone

    local path1="${1%%/}"
    local path2="${2%%/}"
    local info_dir="${RCLONE_SYNC_RC_DIR:-$HOME/.$PRONAME}"
    local path1_info="$info_dir/${path1//+(:|\/)/_}-${path2//+(:|\/)/_}-PATH1.info"
    local path2_info="$info_dir/${path1//+(:|\/)/_}-${path2//+(:|\/)/_}-PATH2.info"
    local max_diff=${RCLONE_SYNC_MAX_DIFF:-50}
    local try_time=${RCLONE_SYNC_TRY_TIME:-5}

    local -A path1_files_prev path1_files_curr
    local -A path2_files_prev path2_files_curr
    local -A path1_delta_add path1_delta_del path1_delta_new path1_delta_old path1_delta_uch
    local -A path2_delta_add path2_delta_del path2_delta_new path2_delta_old path2_delta_uch
    local -A path1_inter path2_inter
    local -A path1_path2_diff path2_path1_diff path1_path2_inter
    local -A path1_path2_delta_add path1_path2_delta_del path1_path2_delta_new path1_path2_delta_old path1_path2_delta_uch
    local -A path2_path1_delta_add path2_path1_delta_del path2_path1_delta_new path2_path1_delta_old path2_path1_delta_uch
    local sync_ok=0 sync_fail=0

    [[ -d $info_dir ]] || mkdir "$info_dir"
    if [[ ! -e $path1_info || ! -e $path2_info ]]; then
        warn "info file is not found, sync $path1 and $path2 for first time..."
        rclone_first_sync "$path1" "$path2" \
            && rclone_try "$try_time" rclone_get_file_info "$path1" "$path1_info" \
            && rclone_try "$try_time" rclone_get_file_info "$path2" "$path2_info" \
            || { rm -rf "$path1_info" "$path2_info"; return 1; }
        return 0
    fi

    local path1_info_curr=$(mktemp)
    local path2_info_curr=$(mktemp)
    trap 'rm -rf $path1_info_curr $path2_info_curr' SIGINT EXIT RETURN
    rclone_try "$try_time" rclone_get_file_info "$path1" "$path1_info_curr" || die "Can not get info files."
    rclone_try "$try_time" rclone_get_file_info "$path2" "$path2_info_curr" || die "Can not get info files."

    rclone_read_file_info path1_files_prev "$path1_info"
    rclone_read_file_info path2_files_prev "$path2_info"
    rclone_read_file_info path1_files_curr "$path1_info_curr"
    rclone_read_file_info path2_files_curr "$path2_info_curr"

    [[ $(rclone_abs $((${#path1_files_curr[@]} - ${#path2_files_curr[@]}))) -lt $max_diff ]] \
        || die "Over $max_diff files different, please check by yourself!"

    # path curr and prev cmp
    rclone_check_path path1
    rclone_check_path path2

    # path1 and path2 curr cmp
    rclone_path_cmp path1 path2

    echo ====================
    echo "DELTA in $path1"
    echo "add: ${!path1_path2_delta_add[*]}"
    echo "del: ${!path1_path2_delta_del[*]}"
    echo "new: ${!path1_path2_delta_new[*]}"
    echo "old: ${!path1_path2_delta_old[*]}"
    echo ====================
    echo "DELTA in $path2"
    echo "add: ${!path2_path1_delta_add[*]}"
    echo "del: ${!path2_path1_delta_del[*]}"
    echo "new: ${!path2_path1_delta_new[*]}"
    echo "old: ${!path2_path1_delta_old[*]}"
    echo ====================

    echo "Sync $path1 to $path2..."
    rclone_sync_path path1 path2
    echo "Sync $path2 to $path1..."
    rclone_sync_path path2 path1
    echo "Sync status: total $((sync_ok+sync_fail)), ok $sync_ok, fail $sync_fail."

    # update info files
    if [[ $sync_ok -gt 0 ]]; then
        echo "Update info files..."
        rclone_try "$try_time" rclone_get_file_info "$path1" "$path1_info_curr" \
            && rclone_try "$try_time" rclone_get_file_info "$path2" "$path2_info_curr" \
            && cp "$path1_info_curr" "$path1_info" && cp "$path2_info_curr" "$path2_info" \
            || warn "Fail to update info files!"
    fi

    return $sync_fail
}

is_sourced || rclone_sync "$@"

# vim:set ft=sh ts=4 sw=4:
