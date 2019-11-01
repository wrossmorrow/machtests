#!/bin/bash
# 
# @name read ifs lots
# @description Read "lots" of small files from ifs
# @version 1 
# 

if [[ ${IFS_TEST_SUITE_LOTS_LIMIT} =~ [0-9]+ ]] ; then 
	COUNT=0
	for F in ${IFS_TEST_SUITE_LOTS_IFS_DIR}/* ; do
		FILENAME=$( echo "${F}" | grep -oP "[^/]*$" )
		cp ${F} "${IFS_TEST_SUITE_LOTS_LOC_DIR}/${FILENAME}"
		COUNT=$(( COUNT + 1 )) && [[ ${COUNT} -ge ${IFS_TEST_SUITE_LOTS_LIMIT} ]] && break
	done
else 
	for F in ${IFS_TEST_SUITE_LOTS_IFS_DIR}/* ; do
		FILENAME=$( echo "${F}" | grep -oP "[^/]*$" )
		cp ${F} "${IFS_TEST_SUITE_LOTS_LOC_DIR}/${FILENAME}"
	done
fi