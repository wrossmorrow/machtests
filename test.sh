#!/bin/bash

YENTESTS_HELP_STRING="YENTESTS - infrastructure for running regular tests on the 
GSB's yen research computing servers. 

DESCRIPTION

  This code is the infrastructure for running regular tests on the yens. 

ARGUMENTS 

  Command line option flags: 

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

  Command line options with arguments: 

    t (string) - Specific list of test folders to run (comma separated, bash regex ok)
    e (string) - Specific list of test folders to exclude (comma separated, bash regex ok)
    R ([0-9]+) - Reset locally-stored, monotonic run index to a specific value matching [0-9]+. Use with caution. 

EXAMPLES

  

CONTACT

  Data, Analytics, and Research Computing: gsb_darcresearch@stanford.edu
  Written by Ferdi Evalle and W. Ross Morrow

"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# UTILITY FUNCTIONS
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# test command and setup result variables
# $@ = commands, options to test
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

function _testCommand() {

	[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
		&& log "testing command \"${@}\""

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
	rm "${YENTESTS_TMP_LOG_DIR}/mem.log"
    
	# set temporary log files for catching test run output
	YENTESTS_TEST_TIMELOG="${YENTESTS_TMP_LOG_DIR}/time.log"
	YENTESTS_TEST_OUTLOG="${YENTESTS_TMP_LOG_DIR}/output.log"
	YENTESTS_TEST_ERRLOG="${YENTESTS_TMP_LOG_DIR}/error.log"

	# use env var to signal whether to use a timeout
	if [[ -z ${YENTESTS_TEST_TIMEOUT} ]] ; then

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "running test without a timeout"

		[[ -n ${YENTESTS_DRY_RUN} ]] \
			&& log "++ dryrun: here we would actually run \"${@}\" (without a timeout)... ++" \
			|| { time -p ${@} > ${YENTESTS_TEST_OUTLOG} 2> ${YENTESTS_TEST_ERRLOG} ; } > ${YENTESTS_TEST_TIMELOG} 2>&1

	else # test command with timeout

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "running test with timeout: ${YENTESTS_TEST_TIMEOUT}s"

		[[ -n ${YENTESTS_DRY_RUN} ]] \
			&& log "++ dryrun: here we would actually run \"${@}\" (with a timeout)... ++" \
			|| { timeout --preserve-status ${YENTESTS_TEST_TIMEOUT} \
					/usr/bin/time -p -o ${YENTESTS_TEST_TIMELOG} ${@} > ${YENTESTS_TEST_OUTLOG} 2> ${YENTESTS_TEST_ERRLOG} ; }

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
	if [[ ${YENTESTS_TEST_EXITCODE} -eq 0 ]] ; then 
		export YENTESTS_TEST_STATUS="P"
	else 
		export YENTESTS_TEST_STATUS="F"
		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "FAIL: ${YENTESTS_TEST_ERROR}"
		[[ ${YENTESTS_TEST_ERROR} =~ "No such file" ]] \
			&& ls -al && ls -al tests \
				&& echo ${YENTESTS_TEST_TIMELOG} \
				&& echo ${YENTESTS_TEST_OUTLOG} \
				&& echo ${YENTESTS_TEST_ERRLOG}
	fi

	# prepare (csv) output line
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_RUNID},${YENTESTS_TEST_NAME},${YENTESTS_TEST_STATUS}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_TEST_TIMEDOUT},${YENTESTS_TEST_EXITCODE}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${YENTESTS_TEST_DURATION},${YENTESTS_TEST_ERROR}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_CPU_INFO_05},${TMP_CPU_INFO_10},${TMP_CPU_INFO_15}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_MEM_USED},${TMP_MEM_AVAIL}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_PROC_INFO_R},${TMP_PROC_INFO_N}"

	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_DATETIME},${YENTESTS_TEST_OUTCSV}"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# FINISHED TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	if [[ -n ${YENTESTS_DRY_RUN} ]] ; then
		log "${YENTESTS_TEST_OUTCSV}"
	else 
		echo "${YENTESTS_TEST_OUTCSV}" >> ${YENTESTS_TEST_RESULTS}
	fi

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE RESULTS TO SQLITE
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 



	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE (CSV) RESULTS TO S3
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# how to handle this efficiently? write every-single-result to S3, or combine into a host-test-batch? 
	
	if [[ -n ${YENTESTS_UPLOAD_TO_S3} ]] ; then 
		echo "${YENTESTS_TEST_OUTCSV}" >> ${YENTESTS_TMP_LOG_DIR}/s3upload.csv 
	fi

	# when all tests are finished, we'll use the AWS CLI to upload

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
	[[ ${YENTESTS_TEST_STATUS} =~ "F" ]] \
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
	#		mema   - 
	#		memu   - 
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
						-X POST "${_YENTESTS_INFLUXDB_URL}" --data-binary "${TMP_INFLUXDB_DATA}" )
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
	if [[ $# -gt 0 ]] ; then

		# create a hash of the test command passed

		# export a test id to store ** NOT CONCURRENT SAFE **
		export YENTESTS_TEST_NAME=${YENTESTS_TEST_NAME}
		export YENTESTS_TEST_HASH=${YENTESTS_TEST_HASH}

		# run the actual test command routine
		_testCommand $@

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

function deferTestScript() {

	# clean up customized environment

	#if [[ -f .env-revert ]] ; then 
	#	set -a && source .env-revert && set +a
	#	rm .env-revert
	#fi

	# IMPORTANT!! unset any YENTESTS_ vars to run the next test suite "clean"
	# unset is a shell builtin, so we can't use xargs: See
	# 
	# 	https://unix.stackexchange.com/questions/209895/unset-all-env-variables-matching-proxy
	# 
	while read V ; do unset $V ; done < <( env | grep '^YENTESTS_' | awk -F'=' '{ print $1 }' )

	[[ $( env | grep '^YENTESTS' | wc -l ) -ge 1 ]] \
		&& log "WARNING: looks like environment wasn't cleaned properly..."

}

# a custom "exit" routine to call below, that does variable clean up. this is important
# to wrap in case we bail early due to skipping logic
function exitTestScript() {
	
	TMP_FILE_NAME=$( echo ${YENTESTS_TEST_FILE} | grep -oP '[^/]*$' )

	# modify "todo" file by deleting matching line for this test
	if [[ -f ${_YENTESTS_TESTS_TODO_FILE} ]] ; then 
		sed -Ei.bak "/${TMP_FILE_NAME}|${YENTESTS_TEST_NAME}/d" ${_YENTESTS_TESTS_TODO_FILE}
		rm ${_YENTESTS_TESTS_TODO_FILE}.bak
	fi

	# append information to "done" file
	if [[ -f ${_YENTESTS_TESTS_DONE_FILE} ]] ; then 
		echo "${TMP_FILE_NAME},${YENTESTS_TEST_NAME},${YENTESTS_TEST_STATUS}" >> ${_YENTESTS_TESTS_DONE_FILE}
	fi

	# run the cleanup defined above
	deferTestScript

}

# ok, test functions
function testScript() {

	# don't do anything unless passed a "real" file
	if [[ $# -gt 0 && -f ${1} ]] ; then

		# start exporting all variable definitions included below
		set -a

			[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
				&& log "loading environment..."

			# load default variables and any environment variables specific to this test suite
			# also, though, store which variables the local .env file adds or alters, so we can take 
			# them away later
			source ${_YENTESTS_TEST_HOME}/.defaults

			if [[ -f .env ]] ; then 

				env > .env-global

				source .env

				# capture (possible) changes
				env > .env-local
				grep -vxFf .env-global .env-local > .env-changes

				# ok, so if a variable exists in .env-changes and it...
				# 
				# 	does NOT exist in .env-global, we should unset it when done
				# 	DOES exist in .env-global, we should revert to its previous value
				# 

				# list variables that existed before and were changed
				cat .env-global  | sed -En 's/^([A-Z][^=]*)=(.*)/^\1/Ip' > .env-global-vars

				# unset those declarations that were added
				cat .env-changes | grep -vf .env-global-vars | awk -F'=' '{ print "unset "$1 }' > .env-revert

				# filter the previous env to that list
				cat .env-changes | grep -f .env-global-vars | awk -F'=' '{ print "^"$1 }' > .env-changed-vars
				cat .env-global  | grep -f .env-changed-vars >> .env-revert

				# clean up
				rm .env-global .env-local .env-changes .env-global-vars .env-changed-vars

			fi

			# strip PWD (not FULL path, just PWD) from filename, if it was passed
			YENTESTS_TEST_FILE=$( echo ${1/$PWD/} | sed -E 's|^/+||' )

			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
			# 
			# EXAMINE FRONTMATTER
			# 
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

			[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
				&& log "parsing frontmatter in ${YENTESTS_TEST_FILE}..."

			# define (and export) the test's name, as extracted from the script's frontmatter
			# or... provided in the environment? environment might not guarantee uniqueness. 
			YENTESTS_TEST_NAME=$( sed -En 's|^[ ]*#[ ]*@name (.*)|\1|p;/^[ ]*#[ ]*@name /q' ${YENTESTS_TEST_FILE} )
			if [[ -z ${YENTESTS_TEST_NAME} ]] ; then 
				YENTESTS_TEST_NAME=$( echo ${PWD/$_YENTESTS_TEST_HOME/} | sed -E 's|^/+||' )/${1}
			fi

			# parse out any prerequisites from frontmatter... 
			AFTERLINE=$( sed -En 's|^[ ]*#[ ]*@after (.*)$|\1|p;/^[ ]*#[ ]*@after /q' ${YENTESTS_TEST_FILE} )
			if [[ -n ${AFTERLINE} ]] ; then
				# search through "after"'s, finding if _all_ are in done file... otherwise bail
				# from this perspective, it could be better to store the reverse: a "todo" file
				# with this code exiting if a line exists in that file for a prerequisite
				IFS=","
				for P in ${AFTERLINE} ; do
					if [[ -n $( grep ${P} ${_YENTESTS_TESTS_TODO_FILE} ) ]] ; then
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "deferring \"${YENTESTS_TEST_NAME}\":: prerequisite \"${P}\" not completed"
						deferTestScript
						return
					fi
				done
			fi

			# off-cycle or randomly executed? 
			TMPLINE=$( sed -En 's,^[ ]*#[ ]*@skip ([0-9]+|[0]*\.[0-9]+)[ ]*$,\1,p;/^[ ]*#[ ]*@skip /q' ${YENTESTS_TEST_FILE} )
			if [[ -n ${TMPLINE} ]] ; then
				if [[ ${TMPLINE} =~ 0*.[0-9]+ ]] ; then 
					TMPLINE=$( python -c "from random import random; print( random() <= ${TMPLINE} )" )
					if [[ ${TMPLINE} =~ True ]] ; then 
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "Skipping \"${YENTESTS_TEST_NAME}\" based on probability"
						YENTESTS_TEST_STATUS='S'
						exitTestScript
						return
					fi 
				else 
					# set skip = 3, means run once in every four runs. or RUNID % (skip+1) == 0
					if [[ $(( ${YENTESTS_TEST_RUNID} % $(( ${TMPLINE} + 1 )) )) -ne 0 ]] ; then
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
							&& log "Skipping \"${YENTESTS_TEST_NAME}\" based on cycle, defined by YENTESTS_TEST_RUNID."
						YENTESTS_TEST_STATUS='S'
						exitTestScript
						return
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

						YENTESTS_TEST_HASH_VERSION=$( echo ${YENTESTS_TEST_HASH_LINE} | sed -En "s|^${PWD}/${YENTESTS_TEST_FILE},([^,]+),.*|\1|p" )
						if [[ ${YENTESTS_TEST_HASH_VERSION} -ne ${YENTESTS_TEST_VERSION} ]] ; then
							YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
							sed -i.bak "s|^${PWD}/${YENTESTS_TEST_FILE},[^,]+,(.*)|${PWD}/${YENTESTS_TEST_FILE},${YENTESTS_TEST_VERSION},${YENTESTS_TEST_HASH}|" ${YENTESTS_HASH_LOG}
						else 
							YENTESTS_TEST_HASH=$( echo ${YENTESTS_TEST_HASH_LINE} | sed -En "s|^${PWD}/${YENTESTS_TEST_FILE},[^,]+,(.*)|\1|" )
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

		# run the test
		log "starting \"${YENTESTS_TEST_NAME}\" (${YENTESTS_TEST_FILE})" 
		_testCommand bash ${YENTESTS_TEST_FILE}
		log "finished \"${YENTESTS_TEST_NAME}\" (${YENTESTS_TEST_STATUS})"

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
		# 
		# DONE
		# 
		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

		exitTestScript

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

	# export the suite name as a "global" env var, just the folder name
	# this will thus be accessible in subroutines here if we want to use 
	# it to identify/tag, locate, or print anything
	export _YENTESTS_TEST_SUITE_NAME=${1}

	# enter the declared test suite directory
	cd ${1}
	
	# run test.sh file in target folder, if it exists... always first
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

		# empty "done" and "todo" file(s)
		> ${_YENTESTS_TESTS_DONE_FILE}
		> ${_YENTESTS_TESTS_TODO_FILE}
		
		# setup "todo" file
		TMP_TEST_COUNT=0
		for T in tests/*.sh ; do
			TMP_TEST_NAME=$( sed -En 's|^[ ]*#[ ]*@name (.*)|\1|p;/^[ ]*#[ ]*@name /q' ${T} )
			if [[ -z ${TMP_TEST_NAME} ]] ; then 
				TMP_TEST_NAME=$( echo ${PWD/$_YENTESTS_TEST_HOME/} | sed -E 's|^/+||' )/${T}
			fi
			echo "${T},${TMP_TEST_NAME}" | grep -oP '[^/]*$' >> ${_YENTESTS_TESTS_TODO_FILE}
			TMP_TEST_COUNT=$(( TMP_TEST_COUNT + 1 ))
		done

		# loop through the count, break "early" if finished ("todo" file empty)
		for I in `seq 1 ${TMP_TEST_COUNT}` ; do 
			while read S ; do 
				[[ -f "tests/${S}" ]] && testScript "tests/${S}"
			done < <( cat ${_YENTESTS_TESTS_TODO_FILE} | cut -d, -f1 )
			[[ $( wc -l < ${_YENTESTS_TESTS_TODO_FILE} ) -eq 0 ]] && break
		done

		# clean up 
		rm ${_YENTESTS_TESTS_TODO_FILE} ${_YENTESTS_TESTS_DONE_FILE}

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

# parse args AFTER reading .env, to effect overrides
while getopts "hrdvlsiwLIWSt:e:R:" OPT ; do
	case "${OPT}" in
		h) echo "${YENTESTS_HELP_STRING}" && exit 0 ;;
		r) echo "" > ${YENTESTS_TEST_RIDF} ;;
		d) YENTESTS_DRY_RUN=1 ;;
		v) YENTESTS_VERBOSE_LOGS=1 ;;
		l) unsetEnvVarsMatchingPrefix "YENTESTS_(S3|INFLUXDB)" ;;
		w) unsetEnvVarsMatchingPrefix "YENTESTS_SQLITE" ;;
		I) unsetEnvVarsMatchingPrefix "YENTESTS_INFLUXDB" ;;
		W) unsetEnvVarsMatchingPrefix "YENTESTS_S3" ;;
		S) unsetEnvVarsMatchingPrefix "YENTESTS_SQLITE" ;;
		t) [[ -z ${YENTESTS_TEST_EXCL} ]] \
				&& YENTESTS_TEST_LIST=${OPTARG} \
				|| echo "WARNING: Already provided a list to exclude, can't also provide a list to include. Ignoring the latter." \
				;; 
		e) [[ -z ${YENTESTS_TEST_LIST} ]] \
				&& YENTESTS_TEST_EXCL=${OPTARG} \
				|| echo "WARNING: Already provided a list to include, can't also provide a list to exclude. Ignoring the latter." \
				;; 
		R) [[ ${OPTARG} =~ ^[0-9]+$ ]] && echo "${OPTARG}" > ${YENTESTS_TEST_RIDF} ;;
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

if [[ -n ${YENTESTS_VERBOSE_LOGS} ]] ; then 
function log() {
	echo "$( date +"%FT%T.%N" ):${PWD}: $1"
}
else 
function log() {
	echo "$( date +"%FT%T.%N" ): $1"
}
fi

else 

# make sure runlog location exists
mkdir -p ${YENTESTS_RUN_LOG%/*}
if [[ -n ${YENTESTS_VERBOSE_LOGS} ]] ; then 
function log() {
	echo "$( date +"%FT%T.%N" ):${PWD}: $1" >> ${YENTESTS_RUN_LOG}
}
else 
function log() {
	echo "$( date +"%FT%T.%N" ): $1" >> ${YENTESTS_RUN_LOG}
}
fi

fi
export -f log

# construct a usable influxdb URL ("global" env var)
export _YENTESTS_INFLUXDB_URL="${YENTESTS_INFLUXDB_HOST}:${YENTESTS_INFLUXDB_PORT}/write?db=${YENTESTS_INFLUXDB_DB}&u=${YENTESTS_INFLUXDB_USER}&p=${YENTESTS_INFLUXDB_PWD}&precision=s"

if [[ -n ${YENTESTS_S3_ACCESS_KEY_ID} \
		&& -n ${YENTESTS_S3_SECRET_ACCESS_KEY} \
		&& -n ${YENTESTS_S3_BUCKET} ]] ; then 
	echo "looks like S3 defined"
	_YENTESTS_AWS_COMMAND="AWS_ACCESS_KEY_ID=${YENTESTS_S3_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${YENTESTS_S3_SECRET_ACCESS_KEY} aws"
	${_YENTESTS_AWS_COMMAND} s3 ls s3://${YENTESTS_S3_BUCKET}/${YENTESTS_S3_PREFIX}
	[[ $? -eq 0 ]] && _YENTESTS_UPLOAD_TO_S3==1
fi
[[ -n ${_YENTESTS_UPLOAD_TO_S3} ]] \
	&& echo "looks like S3 connection is ok"

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

# define "todo" file, if not customized
[[ -n ${YENTESTS_TESTS_TODO_FILE} ]] \
	&& export _YENTESTS_TESTS_TODO_FILE=${YENTESTS_TESTS_TODO_FILE} \
	|| export _YENTESTS_TESTS_TODO_FILE="${YENTESTS_TMP_LOG_DIR}/${YENTESTS_TEST_HOST}-todo"

# define "done" file, if not customized
[[ -n ${YENTESTS_TESTS_DONE_FILE} ]] \
	&& export _YENTESTS_TESTS_DONE_FILE=${YENTESTS_TESTS_DONE_FILE} \
	|| export _YENTESTS_TESTS_DONE_FILE="${YENTESTS_TMP_LOG_DIR}/${YENTESTS_TEST_HOST}-done"

# if tests listed to exclude, make a test list with all those NON matching 
# test suite directory names
if [[ -n ${YENTESTS_TEST_EXCL} ]] ; then 

	for d in tests/** ; do 

		TEST_SUITE_DIR=$( echo ${d} | grep -oP "[^/]*$" )

		INCLUDE_TEST=0
		while read LI ; do 
			if [[ ${TEST_SUITE_DIR} =~ ${LI} ]] ; then INCLUDE_TEST=1 && break ; fi
		done < <( echo ${YENTESTS_TEST_EXCL} | tr ',' '\n' )
		if [[ ${INCLUDE_TEST} -eq 0 ]] ; then
			[[ -z ${YENTESTS_TEST_LIST} ]] \
				&& YENTESTS_TEST_LIST="${TEST_SUITE_DIR}" \
				|| YENTESTS_TEST_LIST="${YENTESTS_TEST_LIST},${TEST_SUITE_DIR}"
		fi

	done

	[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
		&& log "Including: ${YENTESTS_TEST_LIST}"

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
for d in tests/** ; do 

	# if passed a list, only run tests in that list; otherwise, run ALL tests
	if [[ -n ${YENTESTS_TEST_LIST} ]] ; then 
		TEST_SUITE_DIR=$( echo ${d} | grep -oP "[^/]*$" )
		while read LI ; do 
			if [[ ${TEST_SUITE_DIR} =~ ${LI} ]] ; then runTestSuite ${d} && break ; fi
		done < <( echo ${YENTESTS_TEST_LIST} | tr ',' '\n' )

	else
		runTestSuite ${d}
	fi 

done

# upload to s3 if we upload to s3
if [[ -n ${_YENTESTS_UPLOAD_TO_S3} \
		&& -f ${YENTESTS_TMP_LOG_DIR}/s3upload.csv ]] ; then 
	${_YENTESTS_AWS_COMMAND} s3 cp ${YENTESTS_TMP_LOG_DIR}/s3upload.csv \
		"s3://${YENTESTS_S3_BUCKET}/${YENTESTS_S3_PREFIX}/${YENTESTS_TEST_HOST}-$( date +%s ).csv"
	rm ${YENTESTS_TMP_LOG_DIR}/s3upload.csv
fi 

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

# don't need the "global" environment variables (_YENTESTS_*) anymore
while read V ; do unset $V ; done < <( env | grep '^_YENTESTS_' | awk -F'=' '{ print $1 }' )

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 