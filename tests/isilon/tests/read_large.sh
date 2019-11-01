#!/bin/bash
# 
# @name read ifs large
# @description Read a "large" file from ifs, copying it to local disk
# @skip 3
# @probability 0.25
# @version 1 
# 

FILENAME=$( echo "${IFS_TEST_SUITE_LARGE_FILE}" | grep -oP "[^/]*$" )
cp ${IFS_TEST_SUITE_LARGE_FILE} "${IFS_TEST_SUITE_LOTS_LOC_DIR}/${FILENAME}"