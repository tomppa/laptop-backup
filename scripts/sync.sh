#!/bin/bash

DEBUG="${1:-''}"
CONFIG_FOLDER='../config'
PROP_FILE='configuration.properties'

# properties is an associated array, i.e. keys can be strings or variables
declare -A properties

# includes and excludes are Bash arrays, i.e., with auto-numbered keys
declare -a includes
declare -a excludes

function loadProperties {
    local file="$CONFIG_FOLDER/$PROP_FILE"
    if [[ ! -f "$file" ]]; then
        echo "$PROP_FILE not found!"
        return 2
    fi

    while IFS='=' read -r origKey value; do
        local key="$origKey"
        # Replace all non alphanumerical characters (except underscore)
        # with an underscore
        key="${key//[!a-zA-Z0-9_]/_}"

        if [[ "$origKey" == "#"* ]]; then
            local ignoreComments
        elif [[ -z "$key" ]]; then
            local emptyLine
        else
            properties["$key"]="$value"
        fi
    done < "$file"

    if [[ "$DEBUG" == "--debug" ]]; then
        declare -p properties
    fi
}

function checkBucket {
    local params=()
    params+=(--bucket "${properties[s3_bucket]}")
    params+=(--profile="${properties[aws_profile]}")
    local bucketStatus=$(aws s3api head-bucket ${params[@]} 2>&1)
    
    if [[ -z "$bucketStatus" ]]; then
        echo "Bucket \"${properties[s3_bucket]}\" owned and exists";
        return 0
    elif echo "${bucketStatus}" | grep 'Invalid bucket name'; then
        return 1
    elif echo "${bucketStatus}" | grep 'Not Found'; then
        return 1
    elif echo "${bucketStatus}" | grep 'Forbidden'; then
        echo "Bucket exists but not owned"
        return 1
    elif echo "${bucketStatus}" | grep 'Bad Request'; then
        echo "Bucket name specified is less than 3 or greater than 63 characters"
        return 1
    else
        return 1
    fi
}

function sync {
    local params=()
    local local_folder="$HOME/$1"
    local bucket_folder="s3://${properties[s3_bucket]}$local_folder"

    params+=("$local_folder" "$bucket_folder")

    if [[ ${excludes[@]} ]]; then
        params+=("${excludes[@]}")
    fi
    
    if [[ ${includes[@]} ]]; then
        params+=("${includes[@]}")
    fi

    params+=("--profile=${properties[aws_profile]}")

    if [[ "${properties[dryrun]}" = true ]]; then
        params+=(--dryrun)
    fi

    aws s3 sync "${params[@]}"
}

function read_parameters {
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

function reset {
    unset includes excludes
    declare -a includes excludes
}

if [[ "$DEBUG" == "--debug" ]]; then
    set -x
fi

loadProperties

if [[ $? != 0 ]]; then
    exit
fi

checkBucket

if [[ $? != 0 ]]; then
    exit
fi

backup_config_folder="$CONFIG_FOLDER/${properties[backup_folder]}"

for folder in $backup_config_folder; do
    if [[ -d "$folder" && ! -L "$folder" ]]; then
        read_parameters "$folder/${properties[exclude_file_name]}" exclude
        read_parameters "$folder/${properties[include_file_name]}" include
        sync "${folder##*/}"
        reset
    fi
done
