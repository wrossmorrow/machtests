#!/bin/bash

# 
# (1) fill neccessary environment
# (2) define test's "RUNID"
# (3) loop through structured sub-folders
# 		• run each test.sh file
#		• run each *.sh file in tests/ subfolders
# 		• each such test run needs a "TESTID" that stays the same across runs - use a hash
#		• we should also parse our "front matter" tags... maybe for version?
# 

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# DEFINE UTILITY FUNCTIONS
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# test command and setup result variables
# $1 = command to test
# 
# This function expects the following to be defined: 
# 
# 	TBD
# 
# This function defines (locally) the following: 
# 
# 	YENTESTS_TEST_EXITCODE - 
# 	YENTESTS_TEST_OUTPUT   - 
# 	YENTESTS_TEST_DURATION - 
# 	YENTESTS_TEST_STATUS   - 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

function _testCommand() {

	[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
		&& log "testing command \"${1}\""

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# START TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# get test start time (in a format suitable for influxdb, and for CSV/logging)
	YENTESTS_TEST_START_S=$( date +%s )
	YENTESTS_TEST_DATETIME=$( date +"%FT%T.%N" )

	# get and parse CPU/load info
	TMP_CPU_INFO=$( cat /proc/loadavg )
	TMP_CPU_INFO_05=$( echo ${TMP_CPU_INFO} | awk '{ print $1 }' )
	TMP_CPU_INFO_10=$( echo ${TMP_CPU_INFO} | awk '{ print $2 }' )
	TMP_CPU_INFO_15=$( echo ${TMP_CPU_INFO} | awk '{ print $3 }' )
	TMP_PROC_INFO_R=$( echo ${TMP_CPU_INFO} | awk '{ print $4 }' | awk -F'/' '{ print $1 }' )
	TMP_PROC_INFO_N=$( echo ${TMP_CPU_INFO} | awk '{ print $4 }' | awk -F'/' '{ print $2 }' )

	# get and parse mem usage info
	head -n 3 /proc/meminfo > "${YENTESTS_TMP_LOG_DIR}/mem.log"
	TMP_MEM_TOTAL=$( sed -En 's/^MemTotal:[ ]*([0-9]+) kB/\1/p' "${YENTESTS_TMP_LOG_DIR}/mem.log" )
	TMP_MEM_AVAIL=$( sed -En 's/^MemAvailable:[ ]*([0-9]+) kB/\1/p' "${YENTESTS_TMP_LOG_DIR}/mem.log" )
	TMP_MEM_USED=$(( TMP_MEM_TOTAL - TMP_MEM_AVAIL ))
    
	# set temporary log files for catching test run output
	YENTESTS_TEST_TIMELOG="${YENTESTS_TMP_LOG_DIR}/time.log"
	YENTESTS_TEST_OUTLOG="${YENTESTS_TMP_LOG_DIR}/output.log"
	YENTESTS_TEST_ERRLOG="${YENTESTS_TMP_LOG_DIR}/error.log"

	# use env var to signal whether to use a timeout
	if [[ -z ${YENTESTS_TEST_TIMEOUT} ]] ; then

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "running test without a timeout"

		[[ -n ${YENTESTS_DRY_RUN} ]] \
			&& log "++ dryrun: here we would actually run a test (without a timeout)... ++" \
			|| { time -p ${1} > ${YENTESTS_TEST_OUTLOG} 2> ${YENTESTS_TEST_ERRLOG} ; } > ${YENTESTS_TEST_TIMELOG} 2>&1

	else # test command with timeout

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "running test with timeout: ${YENTESTS_TEST_TIMEOUT}s"

		[[ -n ${YENTESTS_DRY_RUN} ]] \
			&& log "++ dryrun: here we would actually run a test (with a timeout)... ++" \
			|| { timeout --preserve-status ${YENTESTS_TEST_TIMEOUT} \
					/usr/bin/time -p -o ${YENTESTS_TEST_TIMELOG} ${1} > ${YENTESTS_TEST_OUTLOG} 2> ${YENTESTS_TEST_ERRLOG} ; }

	fi
	YENTESTS_TEST_EXITCODE=${?}

	# check error log
	[[ -f ${YENTESTS_TEST_ERRLOG} ]] \
		&& YENTESTS_TEST_ERROR=$( cat ${YENTESTS_TEST_ERRLOG} ) \
		|| YENTESTS_TEST_ERROR="test error log not created"

	# check time log is not empty and set duration from time log
	if [[ -f ${YENTESTS_TEST_TIMELOG} && -s ${YENTESTS_TEST_TIMELOG} ]]; then
		YENTESTS_TEST_DURATION=$( egrep -i '^real' ${YENTESTS_TEST_TIMELOG} | awk '{ print $2 }' )
		TMP_TEST_TIMEDOUT='false'
	else # time log doesn't exist or is empty; means the command timed out
		YENTESTS_TEST_DURATION=${YENTESTS_TEST_TIMEOUT}
		TMP_TEST_TIMEDOUT='true'
	fi
	# set a min value for time so the record can be caught by the kapacitor alert
	[[ ${YENTESTS_TEST_DURATION} == '0.00' ]] && YENTESTS_TEST_DURATION=0.0001

	# check exit code and set success flag 
	# 
	# This could be customized to other exit codes...
	[[ ${YENTESTS_TEST_EXITCODE} -eq 0 ]] \
		&& TMP_PASS="P" || TMP_PASS="F"

	# prepare (csv) status line
	YENTESTS_TEST_STATUS="${YENTESTS_TEST_RUNID},${YENTESTS_TEST_NAME},${TMP_PASS}"
	YENTESTS_TEST_STATUS="${YENTESTS_TEST_STATUS},${TMP_TEST_TIMEDOUT},${YENTESTS_TEST_EXITCODE}"
	YENTESTS_TEST_STATUS="${YENTESTS_TEST_STATUS},${YENTESTS_TEST_DURATION},${YENTESTS_TEST_ERROR}"
	YENTESTS_TEST_STATUS="${YENTESTS_TEST_STATUS},${TMP_CPU_INFO_05},${TMP_CPU_INFO_10},${TMP_CPU_INFO_15}"
	YENTESTS_TEST_STATUS="${YENTESTS_TEST_STATUS},${TMP_MEM_USED},${TMP_MEM_AVAIL}"
	YENTESTS_TEST_STATUS="${YENTESTS_TEST_STATUS},${TMP_PROC_INFO_R},${TMP_PROC_INFO_N}"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# FINISHED TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	if [[ -n ${YENTESTS_DRY_RUN} ]] ; then
		log "${YENTESTS_TEST_DATETIME},${YENTESTS_TEST_STATUS}"
	else 
		echo "${YENTESTS_TEST_DATETIME},${YENTESTS_TEST_STATUS}" >> ${YENTESTS_TEST_RESULTS}
	fi

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE RESULTS TO INFLUXDB
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# NOTE: replace spaces in names (and host?) with _ to prevent invalid field format error return from 
	# influxdb

	# string we'll want to write to influxdb... 
	# 
	# 	tags: each of these things we might want to search/groupby over and should be indexed
	# 
	# 		host - the host the test was run on
	# 		test - the name of the test
	# 		hash - the hash of the test run, like a test version number
	# 		code - the exit code from the test
	#		fail - a simple flag to check failure
	#		tout - flag for timeout
	# 		runid? currently a field
	# 
	TMP_INFLUXDB_TAGS="host=${YENTESTS_TEST_HOST},test=${YENTESTS_TEST_NAME//[ ]/_}"
	TMP_INFLUXDB_TAGS="${TMP_INFLUXDB_TAGS},tver=${YENTESTS_TEST_VERSION},hash=${YENTESTS_TEST_HASH}"
	TMP_INFLUXDB_TAGS="${TMP_INFLUXDB_TAGS},code=${YENTESTS_TEST_EXITCODE},tout=${TMP_TEST_TIMEDOUT}"
	[[ ${TMP_PASS} =~ "F" ]] \
		&& TMP_INFLUXDB_TAGS="${TMP_INFLUXDB_TAGS},fail=true" \
		|| TMP_INFLUXDB_TAGS="${TMP_INFLUXDB_TAGS},fail=false"


	# 	fields: these things we might want to plot/aggregate
	# 
	#		runid  - the runid of the test run (? should this be a tag?)
	# 		xtime  - execution time of the test
	#		cpu    - (FUTURE) the cpu utilization of the test
	#		mem    - (FUTURE) the memory utilization of the test
	# 		cpu05  - 
	# 		cpu10  - 
	# 		cpu15  - 
	#		rprocs - the number of processes currently running (<= # cpus)
	#		nprocs - the number of processes currently defined
	# 
	TMP_INFLUXDB_FIELDS="runid=${YENTESTS_TEST_RUNID},xtime=${YENTESTS_TEST_DURATION}"
	TMP_INFLUXDB_FIELDS="${TMP_INFLUXDB_FIELDS},cpu05=${TMP_CPU_INFO_05},cpu10=${TMP_CPU_INFO_10},cpu15=${TMP_CPU_INFO_15}"
	TMP_INFLUXDB_FIELDS="${TMP_INFLUXDB_FIELDS},memu=${TMP_MEM_USED},mema=${TMP_MEM_AVAIL}"
	TMP_INFLUXDB_FIELDS="${TMP_INFLUXDB_FIELDS},rprocs=${TMP_PROC_INFO_R},nprocs=${TMP_PROC_INFO_N}"

	# construct LPF string
	TMP_INFLUXDB_DATA="${YENTESTS_INFLUXDB_DB},${TMP_INFLUXDB_TAGS} ${TMP_INFLUXDB_FIELDS} ${YENTESTS_TEST_START_S}"

	# post data to the yentests database in InfluxDB
	if [[ -n ${YENTESTS_DRY_RUN} ]] ; then 
		log "to influxdb: ${TMP_INFLUXDB_DATA}"
	else 
		CURL_STAT=$( curl -k -s -w "%{http_code}" -o ${TMP_LOG_DIR}/curl.log \
						-X POST "${YENTESTS_INFLUXDB_URL}" --data-binary "${TMP_INFLUXDB_DATA}" )
		if [[ ${CURL_STAT} -ne 204 ]] ; then 
			log "post to influxdb appears to have failed (${CURL_STAT})"
			[[ -f ${TMP_LOG_DIR}/curl.log ]] \
				&& cat ${TMP_LOG_DIR}/curl.log
		else
			[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
				&& log "wrote test summary data to influxdb"
		fi
		rm ${TMP_LOG_DIR}/curl.log > /dev/null 2>&1 
	fi

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# CLEAN UP
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# clean up log files
	for f in "time" "output" "error" ; do  
		rm -f "${YENTESTS_TMP_LOG_DIR}/${f}.log" > /dev/null
	done

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# DONE
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# test a command only, and setup result variables
# 
# This function expects the following to be defined: 
# 
# 	
# 
# This function defines (and exports) the following:
# 
#	YENTESTS_TEST_NAME - 
#	YENTESTS_TEST_VERSION - the test version, as read from frontmatter
#	YENTESTS_TEST_HASH_VERSION - the test version in the current hash log file
#	YENTESTS_TEST_HASH - the hash of the test script, used to id tests
#	
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

function testCommand() {

	# don't do anything unless passed a command
	if [[ -z $1 ]] ; then

		# create a hash of the test command passed

		# export a test id to store ** NOT CONCURRENT SAFE **
		export YENTESTS_TEST_NAME=${YENTESTS_TEST_NAME}
		export YENTESTS_TEST_HASH=${YENTESTS_TEST_HASH}

		# run the actual test command routine
		_testCommand ${1}

	fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# test a script and setup result variables
# 
# This function expects the following to be defined: 
# 
# 	
# 
# This function defines (and exports) the following:
# 
#	YENTESTS_TEST_FILE - the filename passed here (excluding its path up to PWD)
#	YENTESTS_TEST_NAME - the given test name, from the environment or from 
#	YENTESTS_TEST_VERSION - the test version, as read from frontmatter
#	YENTESTS_TEST_HASH_VERSION - the test version in the current hash log file
#	YENTESTS_TEST_HASH - the hash of the test script, used to id tests
#	
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

function testScript() {

	# don't do anything unless passed a "real" file
	if [[ $# -gt 0 && -f ${1} ]] ; then

		# start exporting all variable definitions included below
		set -a

			[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
				&& log "loading environment..."

			# load default variables and any environment variables specific to this test suite
			source ${_YENTESTS_TEST_HOME}/.defaults
			[[ -f .env ]] && source .env

			# strip PWD (not FULL path, just PWD) from filename, if it was passed
			YENTESTS_TEST_FILE=$( echo ${1/$PWD/} | sed -E 's|^/+||' )

			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
			# 
			# EXAMINE FRONTMATTER
			# 
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

			if [[ -n ${YENTESTS_VERBOSE_LOGS} ]] ; then
				log "parsing frontmatter..."
				sed -En 's|^[ ]*#[ ]*@[a-zA-Z]+ (.*)|\0|p' ${YENTESTS_TEST_FILE}
			fi

			# define (and export) the test's name, as extracted from the script's frontmatter
			# or... provided in the environment? environment might not guarantee uniqueness. 
			if [[ -z ${YENTESTS_TEST_NAME} ]] ; then 
				YENTESTS_TEST_NAME=$( sed -En 's|^[ ]*#[ ]*@name (.*)|\1|p;/^[ ]*#[ ]*@name /q' ${YENTESTS_TEST_FILE} )
				if [[ -z ${YENTESTS_TEST_NAME} ]] ; then 
					YENTESTS_TEST_NAME=$( echo ${PWD/$_YENTESTS_TEST_HOME/} | sed -E 's|^/+||' )/${1}
				fi
			fi

			# parse out any prerequisites from frontmatter... 
			AFTERLINE=$( sed -En 's|^[ ]*#[ ]*@after (.*)$|\1|p;/^[ ]*#[ ]*@after /q' ${YENTESTS_TEST_FILE} )
			if [[ -n ${AFTERLINE} ]] ; then
				# search through "after"'s, finding if _all_ are in done file... otherwise bail
				# from this perspective, it could be better to store the reverse: a "todo" file
				# with this code exiting if a line exists in that file for a prerequisite
				echo "prerequisites"
			fi

			# off-cycle or randomly executed? 
			TMPLINE=$( sed -En 's,^[ ]*#[ ]*@skip ([0-9]+|[0]*\.[0-9]+).*,\1,p;/^[ ]*#[ ]*@skip /q' ${YENTESTS_TEST_FILE} )
			if [[ -n ${TMPLINE} ]] ; then
				log "skip defined in \"${YENTESTS_TEST_NAME}\""
				if [[ ${TMPLINE} =~ 0*.[0-9]+ ]] ; then 
					TMPLINE=$( python -c "from random import random; print( random() > ${TMPLINE} )" )
					if [[ ${TMPLINE} =~ True ]] ; then 
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "Skipping \"${YENTESTS_TEST_NAME}\" based on probability"
						exit
					fi 
				else 
					# set skip = 3, means run once in every four runs. or RUNID % (skip+1) == 0
					if [[ $(( ${YENTESTS_TEST_RUNID} % $(( ${TMPLINE} + 1 )) )) -ne 0 ]] ; then
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "Skipping \"${YENTESTS_TEST_NAME}\" based on cycle, defined by YENTESTS_TEST_RUNID."
						exit
					else 
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "Running \"${YENTESTS_TEST_NAME}\" based on skip/cycle, defined by YENTESTS_TEST_RUNID."
					fi
				fi
			else 
				TMPLINE=$( sed -En 's|^[ ]*#[ ]*@skip |\0|p;/^[ ]*#[ ]*@skip /q' ${YENTESTS_TEST_FILE} )
				[[ -n ${TMPLINE} ]] && [[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
					&& log "@skip provided in frontmatter but seems to be malformed..."
			fi

			# define test version (with a default)
			YENTESTS_TEST_VERSION=$( sed -En 's|^[ ]*#[ ]*@version ([0-9]+)(.*)|\1|p;/^[ ]*#[ ]*@version /q' ${YENTESTS_TEST_FILE} )
			[[ -z ${YENTESTS_TEST_VERSION} ]] && YENTESTS_TEST_VERSION=0

			# unset the timeout if "notimeout" declared in the test script frontmatter
			# if "notimeout" declared, ignore any specified timeout
			if [[ -n $( sed -En "s|^[ ]*#[ ]*@notimeout|\0|p;/^[ ]*#[ ]*@notimeout/q" ${YENTESTS_TEST_FILE} ) ]] ; then 
				unset YENTESTS_TEST_TIMEOUT
			else 
				# if timeout given in script frontmatter (in seconds), replace timeout
				if [[ -n $( sed -En "s|^[ ]*#[ ]*@timeout [0-9]+|\0|p;/^[ ]*#[ ]*@timeout [0-9]+/q" ${YENTESTS_TEST_FILE} ) ]] ; then 
					YENTESTS_TEST_TIMEOUT=$( sed -En "s|^[ ]*#[ ]*@timeout ([0-9]+)|\1|p;/^[ ]*#[ ]*@timeout [0-9]+/q" ${YENTESTS_TEST_FILE} )
				fi
			fi

			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
			# 
			# READ OR CONSTRUCT TEST HASH
			# 
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

			[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
				&& log "reading/creating test script hash..."

			# if we have a hash log file to store hashes in, use that
			if [[ -n ${YENTESTS_HASH_LOG} ]] ; then 

				if [[ -f ${YENTESTS_HASH_LOG} ]] ; then  # hash file exists; search it first

					# find the hash of this test-version to use as a test id across runs, or create/update it
					YENTESTS_TEST_HASH_LINE=$( grep "^${PWD}/${YENTESTS_TEST_FILE}" ${YENTESTS_HASH_LOG} )
					if [[ -z ${YENTESTS_TEST_HASH_LINE} ]] ; then 

						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "no current hash line in hash log file..."

						YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
						echo "${PWD}/${YENTESTS_TEST_FILE},${YENTESTS_TEST_VERSION},${YENTESTS_TEST_HASH}" >> ${YENTESTS_HASH_LOG}

					else 

						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "changing hash log file line..."

						YENTESTS_TEST_HASH_VERSION=$( echo ${YENTESTS_TEST_HASH_LINE} | sed -E "s|^${PWD}/${YENTESTS_TEST_FILE},([^,]+),.*|\1|" )
						YENTESTS_TEST_HASH=$( echo ${YENTESTS_TEST_HASH_LINE} | sed -E "s|^${PWD}/${YENTESTS_TEST_FILE},[^,]+,(.*)|\1|" )
						if [[ ${YENTESTS_TEST_HASH_VERSION} -ne ${YENTESTS_TEST_VERSION} ]] ; then
							YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
							sed -i.bak "s|^${PWD}/${YENTESTS_TEST_FILE},[^,]+,(.*)|${PWD}/${YENTESTS_TEST_FILE},${YENTESTS_TEST_VERSION},${YENTESTS_TEST_HASH}|" ${YENTESTS_HASH_LOG}
						fi

					fi

				else  # create a hash log file here

					[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
						&& log "creating hash log file..."

					YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
					echo "${PWD}/${YENTESTS_TEST_FILE},${YENTESTS_TEST_VERSION},${YENTESTS_TEST_HASH}" > ${YENTESTS_HASH_LOG}

				fi 

			else # no known hash file to log this value in, so just do the naive thing and create the hash every time
				YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
			fi

		# no more exports
		set +a 

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
		# 
		# RUN THE TEST
		# 
		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

		log "starting \"${YENTESTS_TEST_NAME}\"" 

		# run the test
		_testCommand "bash ${YENTESTS_TEST_FILE}"

		log "finished \"${YENTESTS_TEST_NAME}\" (${TMP_PASS})"

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
		# 
		# CLEAR VARIABLES
		# 
		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

		# IMPORTANT!! unset any YENTESTS_ vars to run the next test suite "clean"
		# unset is a shell builtin, so we can't use xargs: See
		# 
		# 	https://unix.stackexchange.com/questions/209895/unset-all-env-variables-matching-proxy
		# 
		while read V ; do unset $V ; done < <( env | grep '^YENTESTS_' | awk -F'=' '{ print $1 }' )

		[[ $( env | grep '^YENTESTS' | wc -l ) -ge 1 ]] \
			&& log "WARNING: looks like environment wasn't cleaned"

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
		# 
		# DONE
		# 
		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# run a test suite in a folder
# 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

function runTestSuite() {

	# enter the declared test suite directory
	cd ${1}
	
	# run test.sh file in target folder, if it exists
	[[ -f test.sh ]] && testScript test.sh

	# if there is a "tests" __subfolder__, run ANY scripts in that
	# (run ANY scripts so we don't have to mess with making a "manifest")
	# any such script should expect to run from the suite directory
	# 
	# here is where we can assert ordering... with multiple passes 
	# over the tests subfolder, a "done" list, and reading "after"
	# (and/or "before"?) front matter elements (if any)
	# 
	# There can be as many as #files passes, no more. We can maintain 
	# a done list with "filename,testname" rows and check the list
	# when checking frontmatter. If there is an "after" element, read
	# the done list checking for a matching filename or testname. 
	# 
	if [[ -d tests ]] ; then 
		for t in tests/*.sh ; do testScript ${t} ; done
	fi
	
	# leave the test suite directory by returning to the working directory for all tests
	cd ${_YENTESTS_TEST_HOME}
	
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# ARGUMENT PARSING
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# 
# -r: reset run ids
# -d: dryrun tests; that is, just setup for each test but don't actually run any of them
# -v: use verbose prints to the logs
# -l: "local only", meaning no S3 or influxdb (even if defined)
# -w: "web only", meaning no sqlite (even if defined)
# -I: NO influxdb, even if defined
# -W: NO S3, even if defined
# -S: NO sqlite, even if defined
# 

function unsetEnvVarsMatchingPrefix() {
	env | grep "^${1}" | awk -F'=' '{ print $2 }' | xargs -i unset {}
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# PREPROCESSING: SETUP ENVIRONMENT AND THINGS FOR TEST RUNS
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# tests home folder... use _ first to keep this variable defined
# export _YENTESTS_TEST_HOME=/ifs/yentools/yentests
export _YENTESTS_TEST_HOME=${PWD}

# for this process, move to the tests home directory
cd ${_YENTESTS_TEST_HOME}

# setup module system
source /etc/profile.d/lmod.sh

# setup environment variables
# 
# We'll expect
# 
# 	YENTESTS_TEST_{LOGS,HOST,RIDF,RESULTS,TIMEOUT}
# 	YENTESTS_{HASH,RUN}_LOG
# 	YENTESTS_SQLITE_{DB,FILE} 										if storing in a local sqlite database
# 	YENTESTS_S3_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,BUCKET,PREFIX} 	if dumping to S3
# 	YENTESTS_INFLUXDB_{HOST,PORT,DB,USER,PWD}						if sending data to influxdb
# 
[[ -f .env ]] && set -a && source .env && set +a

# set defaults for those vars that need defaults
[[ -z ${YENTESTS_TEST_HOST}    ]] && YENTESTS_TEST_HOST=${HOSTNAME}
[[ -z ${YENTESTS_TEST_LOGS}    ]] && YENTESTS_TEST_LOGS=${PWD}/logs/${YENTESTS_TEST_HOST}
[[ -z ${YENTESTS_TEST_TIMEOUT} ]] && YENTESTS_TEST_TIMEOUT=60
[[ -z ${YENTESTS_TEST_RIDF}    ]] && YENTESTS_TEST_RIDF=${YENTESTS_TEST_LOGS}/runid
[[ -z ${YENTESTS_TEST_RESULTS} ]] && YENTESTS_TEST_RESULTS=${PWD}/results/${YENTESTS_TEST_HOST}
[[ -z ${YENTESTS_HASH_LOG}     ]] && YENTESTS_HASH_LOG=/tmp/yentests/test-hashes.log

YENTESTS_HELP_STRING="YENTESTS - infrastructure for running regular tests on the 
GSB's yen research computing servers. 

Option flags: 

	h - print this message and exit. 
	r - reset locally-stored, monotonic run index. use with caution. 
	d - do a dry-run; that is, don't actually run any tests themselves
	v - print verbose logs for the tester
	l - store local results only (always configured)
	s - store ONLY sqlite3 results (if configured)
	i - store ONLY influxdb results (if configured)
	w - store ONLY S3 results (if configured)
	L - do NOT store local results (delete after completion)
	S - do NOT store results in sqlite3 (even if configured)
	I - do NOT store results in influxdb (even if configured)
	W - do NOT store results in S3 (even if configured)

Options with arguments: 

	t (csv string) - specific list of test folders to run (comma separated, regex style)
	R ([0-9]+) - reset locally-stored, monotonic run index to a specific value matching [0-9]+. use with caution. 

"

# parse args AFTER reading .env, to effect overrides
while getopts "hrdvlsiwLIWSt:R:" OPT ; do
	case "${OPT}" in
		h) echo "${YENTESTS_HELP_STRING}" && exit 0 ;;
		r) echo "!" > ${YENTESTS_TEST_RIDF} ;;
		d) YENTESTS_DRY_RUN=1 ;;
		v) YENTESTS_VERBOSE_LOGS=1 ;;
		t) YENTESTS_TEST_LIST=${OPTARG} ;;
		l) unsetEnvVarsMatchingPrefix "YENTESTS_(S3|INFLUXDB)" ;;
		w) unsetEnvVarsMatchingPrefix "YENTESTS_SQLITE" ;;
		I) unsetEnvVarsMatchingPrefix "YENTESTS_INFLUXDB" ;;
		W) unsetEnvVarsMatchingPrefix "YENTESTS_S3" ;;
		S) unsetEnvVarsMatchingPrefix "YENTESTS_SQLITE" ;;
		t) YENTESTS_TEST_LIST && log "listing tests... ${OPTARG}" ;; 
		R) echo "reset-set runid... ${OPTARG}" ;; 
		[?]) print >&2 "Usage: $0 [-s] [-d seplist] file ..." && exit 1 ;;
	esac
done
shift $(( ${OPTIND} - 1 ))

# make sure log directory(s) exists
mkdir -p ${YENTESTS_TEST_LOGS}

# create location of temporary log dir and make sure it exists
YENTESTS_TMP_LOG_DIR="${YENTESTS_TEST_LOGS}/tmp"
export YENTESTS_TMP_LOG_DIR
mkdir -p ${YENTESTS_TMP_LOG_DIR}

# make sure results location exists
mkdir -p ${YENTESTS_TEST_RESULTS%/*}

# create and export the log function to make it accessible in children
if [[ -z ${YENTESTS_RUN_LOG} ]] ; then
function log() {
	echo "$( date +"%FT%T.%N" ): $1"
}
else 
# make sure runlog location exists
mkdir -p ${YENTESTS_RUN_LOG%/*}
function log() {
	echo "$( date +"%FT%T.%N" ): $1" >> ${YENTESTS_RUN_LOG}
}
fi
export -f log

# construct a usable influxdb URL
export YENTESTS_INFLUXDB_URL="${YENTESTS_INFLUXDB_HOST}:${YENTESTS_INFLUXDB_PORT}/write?db=${YENTESTS_INFLUXDB_DB}&u=${YENTESTS_INFLUXDB_USER}&p=${YENTESTS_INFLUXDB_PWD}&precision=s"

# read TEST_ID from a file here, in the home directory. this will be 
# a sequential, unique index... convenient because we could compare
# test runs "chronologically" according to the partial order thus 
# constructed. However, it does impose a requirement for care...
if [[ -f ${YENTESTS_TEST_RIDF} ]] ; then 
	YENTESTS_TEST_RUNID=$( cat ${YENTESTS_TEST_RIDF} )
	YENTESTS_TEST_RUNID=$(( YENTESTS_TEST_RUNID + 1 ))
else 
	# at least make sure the directory exists
	mkdir -p ${YENTESTS_TEST_RIDF%/*}
	# intialize the RUNID to 1
	YENTESTS_TEST_RUNID=1
fi 

# re-write the runid into the run id file
echo "${YENTESTS_TEST_RUNID}" > ${YENTESTS_TEST_RIDF}
export YENTESTS_TEST_RUNID # SHOULD BE AVAILABLE 

# create TEST_ID as a date-like string? that would be globally unique, 
# but not _immediately_ comparable

# at least make sure the directory exists
if [[ ! -f ${YENTESTS_HASH_LOG} ]] ; then 
	mkdir -p ${YENTESTS_HASH_LOG%/*}
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# RUN TESTS
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

log "starting yentests..."

# store relevant env vars for use in test suites... we will clean and reload this on each run
# quotes here make sure we can abstract away bash shell special character issues (like with $ or &)
env | grep '^YENTESTS_' | sed -E 's|^([^=]+=)(.*)$|\1"\2"|g' > .defaults

# loop over test suites...
for d in tests/*/ ; do 

	# if passed a list, only run tests in that list
	if [[ -n ${YENTESTS_TEST_LIST} ]] ; then 

		while read LI ; do 
			if [[ $( echo ${d} | grep -oP "[^/]*$" ) =~ ${LI} ]] ; then 
				runTestSuite ${d}
				break
			fi
		done < <( echo ${YENTESTS_TEST_LIST} | tr ',' '\n' )

	else # otherwise, run ALL tests
		runTestSuite ${d}
	fi 

done

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# POSTPROCESSING
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# don't need .defaults anymore
rm .defaults > /dev/null

# don't need this in the environment anymore
unset _YENTESTS_TEST_HOME

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 