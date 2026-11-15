#!/bin/bash

# fetch_areena.sh will run yle-dl to download a video from YLE Areena.
# pip3 install yle-dl is required.
# Usage: ./fetch_areena.sh <URL> [OUTPUT_DIR]
# <URL> is the Areena video URL.
# [OUTPUT_DIR] is optional output directory. If not given, current directory is used.
COMMAND="yle-dl -qq -vfat --maxbitrate best --create-dirs --restrict-filename-no-spaces --no-overwrite --xattrs --metadatalang fin"
URL=$1
OUTPUT_DIR=$2

if $OUTPUT_DIR; then
# --destdir will create subdirs automatically
    $COMMAND="$COMMAND --destdir \"$OUTPUT_DIR\" \"$URL\""
else
    $COMMAND="$COMMAND \"$URL\""
fi

# redirect errors to stdout
eval $COMMAND 2>&1