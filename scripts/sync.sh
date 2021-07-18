#!/bin/bash

DEBUG="${1:-''}"

# Get the current directory where this file is, so that the script can
# called from other directories without breaking up.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

CONFIG_FOLDER="$DIR/../config"
PROP_FILE='configuration.properties'

# properties is an associated array, i.e., keys can be strings or variables
# think Java HashMap or JavaScript Object
declare -A properties

# includes and excludes are Bash arrays, i.e., with auto-numbered keys
# think Java or JavaScript array
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
    # Declare inside a function automatically makes the variable a local
    # variable.S
    declare -a params
    params+=(--bucket "${properties[s3_bucket]}")
    params+=(--profile="${properties[aws_profile]}")

    local bucketStatus=$(aws s3api head-bucket ${params[@]} 2>&1)
    
    # The 'aws s3api head-bucket' returns an empty response, if everything's
    # ok or an error message, if something went wrong.
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
    declare -a params
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

# set -x shows the actual commands executed by the script, much better than
# trying to run echo or printf with each command separately.
if [[ "$DEBUG" == "--debug" ]]; then
    set -x
fi

loadProperties

# $? gives the return value of previous function call, non-zero value means
# that an error of some type occured
if [[ $? != 0 ]]; then
    exit
fi

checkBucket

if [[ $? != 0 ]]; then
    exit
fi

backup_config_folder="$CONFIG_FOLDER/${properties[backup_folder]}"

# Change shell options (shopt) to include filenames beginning with a dot
# in the file name expansion.
shopt -s dotglob

# Loop through files in given path.
for folder in $backup_config_folder; do
    # Check that file is a folder, and that it's not a symbolic link.
    if [[ -d "$folder" && ! -L "$folder" ]]; then
        read_parameters "$folder/${properties[exclude_file_name]}" exclude
        read_parameters "$folder/${properties[include_file_name]}" include
        sync "${folder##*/}"
        reset
    fi
done
