#!/bin/bash

# Get the current directory where this file is, so that the script can
# called from other directories without breaking up.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

CONFIG_FOLDER="$DIR/../config"
PROP_FILE='configuration.properties'

# This is an associated array, i.e., keys can be strings or variables
# think Java HashMap or JavaScript Object
declare -A properties

# These are Bash arrays, i.e., with auto-numbered keys
# think Java or JavaScript array
declare -a includes excludes params

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

    if [[ "${properties[debug]}" = true ]]; then
        declare -p properties
    fi
}

function getBucketName {
    # Declare inside a function automatically makes the variable a local
    # variable.
    declare -a params
    params+=(--name "${properties[bucket_parameter_name]}")
    params+=(--profile="${properties[aws_profile]}")

    # Get the bucket name from SSM Parameter Store, where it's stored.
    # Logic is:
    # 1) run the AWS CLI command
    # 2) grab 5th line from the output with sed
    # 3) grab the 2nd word of the line with awk
    # 4) substitute first all double quotes with empty string,
    #    and then all commas with empty string, using sed
    local bucketName=$(aws ssm get-parameter "${params[@]}" | \
                       sed -n '5p' | \
                       awk '{ print $2 }' | \
                       sed -e 's/"//g' -e 's/,//g')

    properties[s3_bucket]="$bucketName"
}

function checkBucket {
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

function create_params {
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

    if [[ "${properties[debug]}" = true ]]; then
        declare -p params
    fi
}

# Sync is automatically recursive, and it can't be turned off. Thus,
# use copy when need to avoid recursion.
function sync {
    aws s3 sync "${params[@]}"
}

function copy {
    local basePath="${params[0]}*"

    # Loop through files in given path.
    for file in $basePath; do
        # Check that file is not a folder or a symbolic link.
        if [[ ! -d "$file" && ! -L "$file" ]]; then
            # Remove first parameter, i.e., local folder, since with copy, we
            # need to specify individual files instead of the base folder.
            unset params[0]
            aws s3 cp "$file" "${params[@]}"
        fi
    done
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
    unset includes excludes params
}

function handleFolder {
    read_parameters "${1}/${properties[exclude_file_name]}" exclude
    read_parameters "${1}/${properties[include_file_name]}" include
    
    # Remove the path until the last forward slash.
    create_params "${1##*/}"
    
    if [[ "$2" == "sync" ]]; then
        sync
    elif [[ "$2" == "copy" ]]; then
        copy
    else
        echo "Don't know what to do."
    fi

    reset
}

function usage {
    cat << EOF
Usage: ${0##*/} [-dDh]

    -d, --debug   enable debug mode
    -D, --dryrun  execute commands in dryrun mode, i.e., don't upload anything
    -h, --help    display this help and exit

EOF
}

while getopts ":dDh-:" option; do
    case "$option" in
        -)
            case "${OPTARG}" in
                debug)
                    properties[debug]=true
                    ;;
                dryrun)
                    properties[dryrun]=true
                    ;;
                help)
                    # Send output to stderr instead of stdout by using >&2.
                    usage >&2
                    exit 2
                    ;;
                *)
                    echo "Unknown option --$OPTARG" >&2
                    usage >&2
                    exit 2
                    ;;
            esac
            ;;
        d)
            properties[debug]=true
            ;;
        D) 
            properties[dryrun]=true
            ;;
        h)
            usage >&2
            exit 2
            ;;
        *)
            echo "Unknown option -$OPTARG" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# set -x shows the actual commands executed by the script, much better than
# trying to run echo or printf with each command separately.
if [[ "${properties[debug]}" = true ]]; then
    set -x
fi

loadProperties

# $? gives the return value of previous function call, non-zero value means
# that an error of some type occured
if [[ $? != 0 ]]; then
    exit
fi

getBucketName

if [[ $? != 0 ]]; then
    exit
fi

checkBucket

if [[ $? != 0 ]]; then
    exit
fi

# Add the asterisk in the end for the for loop to work, i.e.,
# to loop through all files in the folder.
backup_config_path="$CONFIG_FOLDER/${properties[backup_folder]}*"

# Change shell options (shopt) to include filenames beginning with a dot
# in the file name expansion.
shopt -s dotglob

# Loop through files in given path, i.e., subfolders of home folder.
for folder in $backup_config_path; do
    # Check that file is a folder, and that it's not a symbolic link.
    if [[ -d "$folder" && ! -L "$folder" ]]; then
        handleFolder "$folder" "sync"
    fi
done

# Also include the files in home folder itself, but use copy to avoid
# recursion (home folder contains over 500k files, and takes forever to
# go through them with sync, even with an exclusion pattern).
# Remove the last character (asterisk) from the end of the config path.
handleFolder "${backup_config_path::-1}" "copy"
