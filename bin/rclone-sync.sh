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

rclone_sync() {
    local PRONAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.0.1"
    local HELP=$(cat <<EOF
$PRONAME $VERSION
$PRONAME [-dhv] path1 path2
    
    -d  dry run
    -h  print this help message 
    -v  print version number

This program is released under the terms of MIT License.
EOF
)
    local -A opts args
    local dry_run
    pargs opts args 'dhv' "$@"
    shift $((OPTIND - 1))
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
            && rclone_get_file_info "$path1" >"$path1_info" \
            && rclone_get_file_info "$path2" >"$path2_info" \
            || { rm -rf "$path1_info" "$path2_info"; return 1; }
        return 0
    fi

    rclone_read_file_info path1_files_prev "$path1_info"
    rclone_read_file_info path2_files_prev "$path2_info"
    rclone_read_file_info path1_files_curr <(rclone_get_file_info "$path1")
    rclone_read_file_info path2_files_curr <(rclone_get_file_info "$path2")

    [[ $(rclone_abs $((${#path1_files_curr[@]} - ${#path2_files_curr[@]}))) -lt $max_diff ]] \
        || die "Over $max_diff files different, please check by yourself!"

    # path curr and prev cmp
    rclone_set_diff path1_files_prev path1_files_curr path1_delta_del
    rclone_set_diff path1_files_curr path1_files_prev path1_delta_add
    rclone_set_inter path1_files_curr path1_files_prev path1_inter
    for file in "${!path1_inter[@]}"; do
        local diff="$(date_cmp \
            "${path1_files_curr[$file]}" "${path1_files_prev[$file]}")"
        if [[ $diff -gt 0 ]]; then
            path1_delta_new[$file]=1
        elif [[ $diff -lt 0 ]]; then
            path1_delta_old[$file]=1
        else
            path1_delta_uch[$file]=1
        fi
    done

    # path2 curr and prev cmp
    rclone_set_diff path2_files_prev path2_files_curr path2_delta_del
    rclone_set_diff path2_files_curr path2_files_prev path2_delta_add
    rclone_set_inter path2_files_curr path2_files_prev path2_inter
    for file in "${!path2_inter[@]}"; do
        local diff="$(date_cmp \
            "${path2_files_curr[$file]}" "${path2_files_prev[$file]}")"
        if [[ $diff -gt 0 ]]; then
            path2_delta_new[$file]=1
        elif [[ $diff -lt 0 ]]; then
            path2_delta_old[$file]=1
        else
            path2_delta_uch[$file]=1
        fi
    done

    # path1 and path2 curr cmp
    rclone_set_inter path1_files_curr path2_files_curr path1_path2_inter
    rclone_set_diff path1_files_curr path2_files_curr path1_path2_diff
    rclone_set_diff path2_files_curr path1_files_curr path2_path1_diff
    for file in "${!path1_path2_diff[@]}"; do
        if [[ -z ${path2_delta_del[$file]} ]]; then
            path1_path2_delta_add[$file]=1
        elif [[ ${path1_delta_new[$file]} ]]; then
            path1_path2_delta_add[$file]=1
        else
            path1_path2_delta_del[$file]=1
        fi
    done
    for file in "${!path2_path1_diff[@]}"; do
        if [[ -z ${path1_delta_del[$file]} ]]; then
            path2_path1_delta_add[$file]=1
        elif [[ ${path2_delta_new[$file]} ]]; then
            path2_path1_delta_add[$file]=1
        else
            path2_path1_delta_del[$file]=1
        fi
    done
    for file in "${!path1_path2_inter[@]}"; do
        local diff="$(date_cmp \
            "${path1_files_curr[$file]}" "${path2_files_curr[$file]}")"
        if [[ $diff -gt 0 ]]; then
            path1_path2_delta_new[$file]=1
            path2_path1_delta_old[$file]=1
        elif [[ $diff -lt 0 ]]; then
            path1_path2_delta_old[$file]=1
            path2_path1_delta_new[$file]=1
        else
            path1_path2_delta_uch[$file]=1
            path2_path1_delta_uch[$file]=1
        fi
    done

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
        rclone_get_file_info "$path1" >"$path1_info" \
            && rclone_get_file_info "$path2" >"$path2_info" \
            || warn "Fail to update info files!"
    fi

    return $sync_fail
}

is_sourced || rclone_sync "$@"

# vim:set ft=sh ts=4 sw=4: