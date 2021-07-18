#!/bin/bash

set -x

DRYRUN=true

s3_bucket_uri='s3://laptopbackupstack-backupbucket87437600-1t7jods4leuhe'
aws_profile='--profile=personal'
backup_config_folder='../config/backup/*'
include_file='includes.txt'
exclude_file='excludes.txt'

includes=()
excludes=()

sync () {
    local params=()
    local local_folder="$HOME/$1"
    local bucket_folder="$s3_bucket_uri""$local_folder"

    params+=("$local_folder" "$bucket_folder")

    if [[ ${excludes[@]} ]]; then
        params+=("${excludes[@]}")
    fi
    
    if [[ ${includes[@]} ]]; then
        params+=("${includes[@]}")
    fi

    params+=("$aws_profile")

    if [[ "$DRYRUN" = true ]]; then
        params+=(--dryrun)
    fi

    aws s3 sync "${params[@]}"
}

read_parameters () {
    if [[ -f "$1" ]]; then
        while read line; do
            if [[ $2 == "include" ]]; then
                includes+=(--include "$line")
            elif [[ $2 == "exclude" ]]; then
                excludes+=(--exclude "$line")
            fi
        done < $1
    fi
}

reset () {
    includes=()
    excludes=()
}

for folder in $backup_config_folder; do
    if [[ -d "$folder" && ! -L "$folder" ]]; then
        read_parameters $folder/$exclude_file exclude
        read_parameters $folder/$include_file include
        sync "${folder##*/}"
        reset
    fi
done
