#!/bin/bash
# 
# @name read ifs large
# @description Read a "large" file from ifs, copying it to local disk
# @skip 3
# @version 1 
# @after read ifs large
# 

[[ -z ${IFS_TEST_SUITE_LARGE_FILE} ]] && exit

FILENAME=$( echo "${IFS_TEST_SUITE_LARGE_FILE}" | grep -oP "[^/]*$" )
cp "${IFS_TEST_SUITE_LOTS_LOC_DIR}/${FILENAME}" ${IFS_TEST_SUITE_LARGE_FILE}