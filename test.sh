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
    D - KEEP defaults file, so that it can be reviewed outside of a particular call
    v - print verbose logs for the tester
    l - store local results only
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
  Tests originally written by Ferdi Evalle
  This package and infrastructure written by W. Ross Morrow

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

# quick way/wrapper to unset environment variables matching a prefix
# 
# unset is a shell builtin, so we can't use xargs: See
# 
# 	https://unix.stackexchange.com/questions/209895/unset-all-env-variables-matching-proxy
# 
# for details. hence the alien monster below
# 
function unsetEnvVarsMatchingPrefix() {
	while read V ; do unset ${V} ; done < <( env | grep "^${1}" | awk -F'=' '{ print $1 }' )
}

# make an "open"(-ish) directory
function makeOpenDirectory() {
	mkdir -p ${1} && chmod g+rw ${1}
}

# modify environment variables in a revertable way, as stored in .env-revert
function createRevertableEnvironment() {

	# store the current "global" environment
	env > .env-global

	# do overwrites or definitions from the test suite, should it exxist
	source .env

	# capture any changes by writing to a local environment file, and then comparing
	# that to the global one
	env > .env-local
	grep -vxFf .env-global .env-local > .env-changes

	# ok, so if a variable EXISTS in .env-changes AND it...
	# 
	# 	does NOT exist in .env-global, then we should UNSET it when done
	# 	DOES exist in .env-global, then we should REVERT to its previous value
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

}

# things to do when we are "deferring" execution of a test script (say, because a
# prerequisite testing script has not run yet or has failed)
function deferTestScript() {

	# clean up any customized environment for the test script literally being run
	if [[ -f .env-revert ]] ; then 
		set -a && source .env-revert && set +a
		rm .env-revert
	fi

	# IMPORTANT!! unset any YENTESTS_ vars to run the next test suite "clean"
	unsetEnvVarsMatchingPrefix "YENTESTS_DEFAULT"

	[[ $( env | grep '^YENTESTS_DEFAULT' | wc -l ) -ge 1 ]] \
		&& log "WARNING: looks like environment wasn't cleaned properly..."

}

# a custom "exit" routine to call that does variable clean up. this is important
# to wrap in case we bail early due to skipping logic
function exitTestScript() {
	
	TMP_FILE_NAME=$( echo ${YENTESTS_TEST_FILE} | grep -oP '[^/]*$' )

	# modify "todo" file by deleting matching line for this test
	if [[ -f ${YENTESTS_TESTS_TODO_FILE} ]] ; then 
		sed -Ei.bak "/${TMP_FILE_NAME}|${YENTESTS_TEST_NAME}/d" ${YENTESTS_TESTS_TODO_FILE}
		rm ${YENTESTS_TESTS_TODO_FILE}.bak
	fi

	# append information to "done" file
	if [[ -f ${YENTESTS_TESTS_DONE_FILE} ]] ; then 
		echo "${TMP_FILE_NAME},${YENTESTS_TEST_NAME},${YENTESTS_TEST_STATUS}" >> ${YENTESTS_TESTS_DONE_FILE}
	fi

	# run the cleanup associated with deferment (which is nested "under" a clean exit)
	deferTestScript

}

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

# this is the "real" command testing function. 
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

	# get and parse generic machine CPU/processes info
	TMP_CPU_INFO=$( cat /proc/loadavg )
	TMP_CPU_INFO_05=$( echo ${TMP_CPU_INFO} | awk '{ print $1 }' )
	TMP_CPU_INFO_10=$( echo ${TMP_CPU_INFO} | awk '{ print $2 }' )
	TMP_CPU_INFO_15=$( echo ${TMP_CPU_INFO} | awk '{ print $3 }' )
	TMP_PROC_INFO_R=$( echo ${TMP_CPU_INFO} | awk '{ print $4 }' | awk -F'/' '{ print $1 }' )
	TMP_PROC_INFO_N=$( echo ${TMP_CPU_INFO} | awk '{ print $4 }' | awk -F'/' '{ print $2 }' )

	# get and parse generic machine memory usage info
	head -n 3 /proc/meminfo > "${YENTESTS_TMP_LOG_DIR}/mem.log"
	TMP_MEM_TOTAL=$( sed -En 's/^MemTotal:[ ]*([0-9]+) kB/\1/p' "${YENTESTS_TMP_LOG_DIR}/mem.log" )
	TMP_MEM_AVAIL=$( sed -En 's/^MemAvailable:[ ]*([0-9]+) kB/\1/p' "${YENTESTS_TMP_LOG_DIR}/mem.log" )
	TMP_MEM_USED=$(( TMP_MEM_TOTAL - TMP_MEM_AVAIL ))
	rm "${YENTESTS_TMP_LOG_DIR}/mem.log"
    
	# set temporary log files for catching test run output
	YENTESTS_TEST_TIMELOG="${YENTESTS_TMP_LOG_DIR}/time.log"
	YENTESTS_TEST_OUTLOG="${YENTESTS_TMP_LOG_DIR}/output.log"
	YENTESTS_TEST_ERRLOG="${YENTESTS_TMP_LOG_DIR}/error.log"

	# 
	# RUN THE TEST, AS ${@}, OR DRYRUN PRINT
	# 
	# use env var to signal whether to use a timeout
	if [[ -z ${YENTESTS_DEFAULT_TEST_TIMEOUT} ]] ; then

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "running test without a timeout"

		[[ -n ${YENTESTS_DRY_RUN} ]] \
			&& log "++ dryrun: here we would actually run \"${@}\" (without a timeout)... ++" \
			|| { time -p ${@} > ${YENTESTS_TEST_OUTLOG} 2> ${YENTESTS_TEST_ERRLOG} ; } > ${YENTESTS_TEST_TIMELOG} 2>&1

	else # test command with timeout

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "running test with timeout: ${YENTESTS_DEFAULT_TEST_TIMEOUT}s"

		[[ -n ${YENTESTS_DRY_RUN} ]] \
			&& log "++ dryrun: here we would actually run \"${@}\" (with a timeout)... ++" \
			|| { timeout --preserve-status ${YENTESTS_DEFAULT_TEST_TIMEOUT} \
					/usr/bin/time -p -o ${YENTESTS_TEST_TIMELOG} ${@} > ${YENTESTS_TEST_OUTLOG} 2> ${YENTESTS_TEST_ERRLOG} ; }

	fi
	YENTESTS_TEST_EXITCODE=${?}

	# check error log
	[[ -f ${YENTESTS_TEST_ERRLOG} ]] \
		&& YENTESTS_TEST_ERROR=$( cat ${YENTESTS_TEST_ERRLOG} ) \
		|| YENTESTS_TEST_ERROR="test error log not created"

	# check time log is not empty and set duration from time log
	# if there is no time log (or if it is empty) then the test timed out
	if [[ -f ${YENTESTS_TEST_TIMELOG} && -s ${YENTESTS_TEST_TIMELOG} ]]; then
		YENTESTS_TEST_DURATION=$( egrep -i '^real' ${YENTESTS_TEST_TIMELOG} | awk '{ print $2 }' )
		TMP_TEST_TIMEDOUT='false'
	else # time log doesn't exist or is empty; means the command timed out
		YENTESTS_TEST_DURATION=${YENTESTS_DEFAULT_TEST_TIMEOUT}
		TMP_TEST_TIMEDOUT='true'
	fi
	# set a positive minimum value for time so the record can be caught by the kapacitor alert
	[[ ${YENTESTS_TEST_DURATION} == '0.00' ]] && YENTESTS_TEST_DURATION=0.0001

	# check exit code and set success flag 
	# 
	# NOTE: This could be customized to other exit codes... either with env or frontmatter
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

	# prepare (csv) output line, which should contain: 
	# 
	#   datetime,
	#	runid,
	#	name,
	#	status,
	#	timedout?,
	#	exitcode,
	#	duration,
	#	error,
	#	cpuinfo(5m,10m,15m),
	#	memory used,
	#	memory avail,
	#	processes running, 
	#	processes defined
	# 
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_DATETIME},${YENTESTS_TEST_RUNID}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${YENTESTS_TEST_NAME},${YENTESTS_TEST_STATUS}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_TEST_TIMEDOUT},${YENTESTS_TEST_EXITCODE}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${YENTESTS_TEST_DURATION},${YENTESTS_TEST_ERROR}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_CPU_INFO_05},${TMP_CPU_INFO_10},${TMP_CPU_INFO_15}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_MEM_USED},${TMP_MEM_AVAIL}"
	YENTESTS_TEST_OUTCSV="${YENTESTS_TEST_OUTCSV},${TMP_PROC_INFO_R},${TMP_PROC_INFO_N}"

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

	# TBD - WRM doesn't know or care that much about SQLite

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE (CSV) RESULTS TO S3
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# how to handle this efficiently? write every-single-result to S3, or combine into a host-test-batch? 
	# I think host-tests batch
	
	if [[ -n ${YENTESTS_UPLOAD_TO_S3} ]] ; then 
		echo "${YENTESTS_TEST_OUTCSV}" >> ${YENTESTS_TMP_LOG_DIR}/s3upload.csv 
	fi

	# when ALL tests are finished, we'll use the AWS CLI to upload... NOT after EACH test runs

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE RESULTS TO INFLUXDB
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# NOTE: replace spaces in names (and host?) with _ to prevent invalid field format error return from 
	# influxdb. We'll presume these occur only in the test names. 

	if [[ -n ${YENTESTS_UPLOAD_TO_INFLUXDB} ]] ; then 

		# string we'll want to write to influxdb... 
		# 
		# 	tags: each of these things we might want to search/groupby over and should be INDEXED
		# 
		# 		host - the host the test was run on
		# 		test - the name of the test
		# 		hash - the hash of the test run, like a test version number, even if that isn't changed in the test script
		# 		code - the exit code from the test
		#		fail - a simple flag to check failure
		#		tout - flag for timeout
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
		# 		cpu05  - the  5m CPU utilization average on the machine at test start time
		# 		cpu10  - the 10m CPU utilization average on the machine at test start time
		# 		cpu15  - the 15m CPU utilization average on the machine at test start time
		#		mema   - memory available on the machine at test start time
		#		memu   - memory used on the machine at test start time
		#		rprocs - the number of processes currently running (<= # cpus) at test start time
		#		nprocs - the number of processes currently defined (including idle) at test start time
		# 
		TMP_INFLUXDB_FIELDS="runid=${YENTESTS_TEST_RUNID},xtime=${YENTESTS_TEST_DURATION}"
		TMP_INFLUXDB_FIELDS="${TMP_INFLUXDB_FIELDS},cpu05=${TMP_CPU_INFO_05},cpu10=${TMP_CPU_INFO_10},cpu15=${TMP_CPU_INFO_15}"
		TMP_INFLUXDB_FIELDS="${TMP_INFLUXDB_FIELDS},memu=${TMP_MEM_USED},mema=${TMP_MEM_AVAIL}"
		TMP_INFLUXDB_FIELDS="${TMP_INFLUXDB_FIELDS},rprocs=${TMP_PROC_INFO_R},nprocs=${TMP_PROC_INFO_N}"

		# construct Line Protocol Format (LPF) string. See influxdata docs about this format
		TMP_INFLUXDB_DATA="${YENTESTS_INFLUXDB_DB},${TMP_INFLUXDB_TAGS} ${TMP_INFLUXDB_FIELDS} ${YENTESTS_TEST_START_S}"

		# post data to the yentests database in InfluxDB
		if [[ -n ${YENTESTS_DRY_RUN} ]] ; then 
			log "INFLUXDB:: to ${YENTESTS_INFLUXDB_URL} : ${TMP_INFLUXDB_DATA}"
		else 
			echo "${TMP_INFLUXDB_DATA}" >> ${YENTESTS_TMP_LOG_DIR}/influxupload.lpf
		fi

	fi

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# CLEAN UP
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	# clean up log files
	for f in "time" "output" "error" "curl" ; do  
		rm -f "${YENTESTS_TMP_LOG_DIR}/${f}.log" > /dev/null 2>&1 
	done

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# DONE
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

}

# this is a wrapper test command. NOTE THIS IS NOT CURRENTLY BEING CALLED...
# 
# WHY IS THIS BEING WRAPPER? WHAT IS LEFT TO ORGANIZE? 
# 
function testCommand() {

	# don't do anything unless passed a command
	[[ $# -gt 0 ]] || return

	# ALOT TBD?

	# run the actual test command routine
	_testCommand $@

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# TEST A SCRIPT AND SETUP RESULT VARIABLES
#	
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# function to test scripts themselves
function testScript() {

	# don't do anything unless passed a "real" file
	[[ $# -gt 0 && -f ${1} ]] || return

	# start exporting all variable definitions included below, including source statements
	set -a

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "loading environment..."

		# load DEFAULT variables (for all tests) AND any environment variables specific to this test suite
		# also, though, store which variables the local .env file adds or alters, so we can take 
		# them away later to revert to a "clean" environment
		source ${YENTESTS_TEST_HOME}/.defaults

		# load environment variables stored for a test suite, carefully
		[[ -f .env ]] && createRevertableEnvironment 

		# strip PWD (not FULL path, just PWD) from filename, if it was "passed"
		YENTESTS_TEST_FILE=$( echo ${1/$PWD/} | sed -E 's|^/+||' )

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
		# 
		# EXAMINE SCRIPT FRONTMATTER, AND OVERWRITE OR APPEND
		# 
		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "parsing frontmatter in ${YENTESTS_TEST_FILE}..."

		# define (and export) the test's name, as extracted from the script's frontmatter
		# (or... provided in the environment? environment might not guarantee uniqueness.)
		YENTESTS_TEST_NAME=$( sed -En 's|^[ ]*#[ ]*@name (.*)|\1|p;/^[ ]*#[ ]*@name /q' ${YENTESTS_TEST_FILE} )
		if [[ -z ${YENTESTS_TEST_NAME} ]] ; then 
			YENTESTS_TEST_NAME=$( echo ${PWD/$YENTESTS_TEST_HOME/} | sed -E 's|^/+||' )/${1}
		fi

		# parse out any prerequisites from frontmatter... 
		AFTERLINE=$( sed -En 's|^[ ]*#[ ]*@after (.*)$|\1|p;/^[ ]*#[ ]*@after /q' ${YENTESTS_TEST_FILE} )
		if [[ -n ${AFTERLINE} ]] ; then
			# search through "after"'s, finding if _all_ are in done file... otherwise bail.
			# from this perspective, it could be better to store the reverse: a "todo" file
			# with this code exiting if a line exists in that file for a prerequisite
			IFS=","
			for P in ${AFTERLINE} ; do
				if [[ -n $( grep ${P} ${YENTESTS_TESTS_TODO_FILE} ) ]] ; then
					[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
						&& log "deferring \"${YENTESTS_TEST_NAME}\":: prerequisite \"${P}\" not completed"
					deferTestScript
					return
				fi
			done
		fi

		# is this test to be run off-cycle or randomly executed/ignored? 
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
			unset YENTESTS_DEFAULT_TEST_TIMEOUT
		else 
			# if timeout given in script frontmatter (in seconds), replace timeout
			if [[ -n $( sed -En "s|^[ ]*#[ ]*@timeout [0-9]+|\0|p;/^[ ]*#[ ]*@timeout [0-9]+/q" ${YENTESTS_TEST_FILE} ) ]] ; then 
				YENTESTS_DEFAULT_TEST_TIMEOUT=$( sed -En "s|^[ ]*#[ ]*@timeout ([0-9]+)|\1|p;/^[ ]*#[ ]*@timeout [0-9]+/q" ${YENTESTS_TEST_FILE} )
			fi
		fi

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
		# 
		# READ OR CONSTRUCT THE TEST SCRIPT HASH
		# 
		# should this ignore frontmatter? 
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

					YENTESTS_TEST_HASH_VERSION=$( echo ${YENTESTS_TEST_HASH_LINE} | sed -En "s|^${PWD}/${YENTESTS_TEST_FILE},([^,]+),.*|\1|p" )
					if [[ ${YENTESTS_TEST_HASH_VERSION} -ne ${YENTESTS_TEST_VERSION} ]] ; then
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] && log "changing hash log file line..."
						YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
						sed -i.bak "s|^${PWD}/${YENTESTS_TEST_FILE},[^,]+,(.*)|${PWD}/${YENTESTS_TEST_FILE},${YENTESTS_TEST_VERSION},${YENTESTS_TEST_HASH}|" ${YENTESTS_HASH_LOG}
					else 
						[[ -n ${YENTESTS_VERBOSE_LOGS} ]] && log "using existing hash log file line..."
						YENTESTS_TEST_HASH=$( echo ${YENTESTS_TEST_HASH_LINE} | sed -E "s|^${PWD}/${YENTESTS_TEST_FILE},[^,]+,(.*)|\1|" )
					fi

				fi

			else  # create a hash log file here

				[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
					&& log "creating hash log file..."

				YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
				echo "${PWD}/${YENTESTS_TEST_FILE},${YENTESTS_TEST_VERSION},${YENTESTS_TEST_HASH}" > ${YENTESTS_HASH_LOG}

				# make sure we open permissions to this file to the group
				# (NOTE: this will likely be unecessary if derived from proper permission of the directory)
				chmod g+x ${YENTESTS_HASH_LOG}

			fi 

		else # no known hash file to log this value in, so just do the naive thing and create the hash every time
			YENTESTS_TEST_HASH=$( sha256sum ${YENTESTS_TEST_FILE} | awk '{ print $1 }' )
		fi

	# no more variable exports
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

	# encapsulated commands to "cleanly" exit a run of a particular test script
	exitTestScript

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

	# make sure (like really sure) we aren't using an old name
	unset ${YENTESTS_TEST_SUITE_NAME}

	# export the suite name as a "global" env var. default is just the folder name,
	# but if there is a .env file, we can define the name with a TEST_SUITE_NAME variable. 
	# this will thus be accessible in subroutines here if we want to use 
	# it to identify/tag, locate, or print anything. 
	[[ -f .env ]] \
		&& YENTESTS_TEST_SUITE_NAME=$( sed  -n 's/^TEST_SUITE_NAME=(.*)/\1/p' .env )

	# that might not have caught anything... 
	[[ -z ${YENTESTS_TEST_SUITE_NAME} ]] \
		&& export YENTESTS_TEST_SUITE_NAME=${1}
	
	# run test.sh file in target folder, if it exists... ALWAYS DONE FIRST
	[[ -f test.sh ]] \
		&& testScript test.sh

	# if there is a "tests" SUBFOLDER, run ANY scripts in that
	# (run ANY scripts so we don't have to mess with making a "manifest")
	# any such script should expect to run from the suite directory
	# 
	# here is where we can assert ordering... with multiple passes 
	# over the tests subfolder, a "done" list, and reading "after"
	# (and/or "before"?) front matter elements (if any)
	# 
	# There can be as many as #files passes, no more. (as in, totally sequential 
	# runs of each file in the folder: first, second, third, etc). We can maintain 
	# a done list with "filename,testname" rows and check the list
	# when checking frontmatter. If there is an "after" element, read
	# the done list checking for a matching filename or testname. 
	# 
	if [[ -d tests ]] ; then 

		# empty "done" and "todo" file(s), making sure they exist
		> ${YENTESTS_TESTS_DONE_FILE}
		> ${YENTESTS_TESTS_TODO_FILE}
		
		# setup "todo" file
		TMP_TEST_COUNT=0
		for T in tests/*.sh ; do
			TMP_TEST_NAME=$( sed -En 's|^[ ]*#[ ]*@name (.*)|\1|p;/^[ ]*#[ ]*@name /q' ${T} )
			if [[ -z ${TMP_TEST_NAME} ]] ; then 
				TMP_TEST_NAME=$( echo ${PWD/$YENTESTS_TEST_HOME/} | sed -E 's|^/+||' )/${T}
			fi
			echo "${T},${TMP_TEST_NAME}" | grep -oP '[^/]*$' >> ${YENTESTS_TESTS_TODO_FILE}
			TMP_TEST_COUNT=$(( TMP_TEST_COUNT + 1 ))
		done

		# loop through the count, break "early" if finished ("todo" file empty)
		for I in `seq 1 ${TMP_TEST_COUNT}` ; do 
			while read S ; do 
				[[ -f "tests/${S}" ]] && testScript "tests/${S}"
			done < <( cat ${YENTESTS_TESTS_TODO_FILE} | cut -d, -f1 )
			[[ $( wc -l < ${YENTESTS_TESTS_TODO_FILE} ) -eq 0 ]] && break
		done

		# clean up by deleting the todo and done files 
		rm ${YENTESTS_TESTS_TODO_FILE} ${YENTESTS_TESTS_DONE_FILE}

	fi
	
	# leave the test suite directory by returning to the working directory for all tests
	cd ${YENTESTS_TEST_HOME}
	
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# ACTUAL test.sh EXECUTIONS
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# The code above defines functions to be used, the code below is what "actually runs". This happens in three
# sections: Preprocessing, Running, and Postprocessing. 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# PREPROCESSING: 
# 
# setup environment and things for all test script runs
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# NOTE: in all the settings below we use export statements for variables that can't possibly change 
# across test suites. On the other hand, we don't export and package into a .defaults file for those that can. 

# tests home folder... how to customize? where do we read this from .env or from CLI? 
# we could use whatever is inn the CURRENT environment pretty easily... 
[[ -z ${YENTESTS_TEST_HOME} ]] \
	&& export YENTESTS_TEST_HOME=${PWD}
	|| REVERTABLE_YENTESTS_TEST_HOME=${YENTESTS_TEST_HOME}

# for this process, move to the tests home directory (trivial?)
cd ${YENTESTS_TEST_HOME}

# setup module system
source /etc/profile.d/lmod.sh

# setup environment variables from .env
[[ -f .env ]] && set -a && source .env && set +a

# set defaults for those vars that have defaults

# global defaults; test suites can't override these
[[ -z ${YENTESTS_TEST_HOST}    ]] && YENTESTS_TEST_HOST=${HOSTNAME}
[[ -z ${YENTESTS_TEST_LOGS}    ]] && YENTESTS_TEST_LOGS=${PWD}/logs/${YENTESTS_TEST_HOST}
[[ -z ${YENTESTS_TEST_RIDF}    ]] && YENTESTS_TEST_RIDF=${YENTESTS_TEST_LOGS}/${YENTESTS_TEST_HOST}/runid
[[ -z ${YENTESTS_TEST_RESULTS} ]] && YENTESTS_TEST_RESULTS=${PWD}/results/${YENTESTS_TEST_HOST}
[[ -z ${YENTESTS_HASH_LOG}     ]] && YENTESTS_HASH_LOG=/tmp/yentests/test-hashes.log

# local defaults; test suites can overwrite these
[[ -z ${YENTESTS_DEFAULT_TEST_TIMEOUT} ]] && YENTESTS_DEFAULT_TEST_TIMEOUT=60

# parse test.sh command line options AFTER reading .env, to effect overrides
while getopts "hrdvlsiwDLIWSt:e:R:" OPT ; do
	case "${OPT}" in
		h) echo "${YENTESTS_HELP_STRING}" && exit 0 ;;
		r) echo "" > ${YENTESTS_TEST_RIDF} ;;
		d) YENTESTS_DRY_RUN=1 ;;
		v) YENTESTS_VERBOSE_LOGS=1 ;;
		l) unsetEnvVarsMatchingPrefix "YENTESTS_(S3|INFLUXDB)" ;; 	# unsetting these variables will preclude use
		w) unsetEnvVarsMatchingPrefix "YENTESTS_SQLITE" ;;        	# unsetting these variables will preclude use
		D) YENTESTS_KEEP_DEFAULTS_FILE=1 ;;
		I) unsetEnvVarsMatchingPrefix "YENTESTS_INFLUXDB" ;; 		# unsetting these variables will preclude use
		W) unsetEnvVarsMatchingPrefix "YENTESTS_S3" ;;       		# unsetting these variables will preclude use
		S) unsetEnvVarsMatchingPrefix "YENTESTS_SQLITE" ;;   		# unsetting these variables will preclude use
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

# make sure log directory(s) exists, and is g+rw
makeOpenDirectory ${YENTESTS_TEST_LOGS}

# create location of temporary log dir and make sure it exists, and is g+rw
export YENTESTS_TMP_LOG_DIR="${YENTESTS_TEST_LOGS}/tmp" # why is this exported, and not just in .defaults? 
makeOpenDirectory ${YENTESTS_TMP_LOG_DIR}

# make sure results location exists, and is g+rw
makeOpenDirectory ${YENTESTS_TEST_RESULTS%/*}

# create and export the log function to make it accessible in children
if [[ -z ${YENTESTS_RUN_LOG} ]] ; then

	# create log function
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

	# make sure runlog location exists, and is g+rw
	makeOpenDirectory ${YENTESTS_RUN_LOG%/*}

	# create log function
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

# if S3 options are defined, set them up and check validity
if [[ -n ${YENTESTS_S3_ACCESS_KEY_ID} \
		&& -n ${YENTESTS_S3_SECRET_ACCESS_KEY} \
		&& -n ${YENTESTS_S3_BUCKET} ]] ; then 

	export AWS_ACCESS_KEY_ID=${YENTESTS_S3_ACCESS_KEY_ID}
	export AWS_SECRET_ACCESS_KEY=${YENTESTS_S3_SECRET_ACCESS_KEY}
	aws s3 ls s3://${YENTESTS_S3_BUCKET}/${YENTESTS_S3_PREFIX} > /dev/null 2&>1
	[[ $? -eq 0 ]] && YENTESTS_UPLOAD_TO_S3==1

fi

[[ -n ${YENTESTS_VERBOSE_LOGS} && -n ${YENTESTS_UPLOAD_TO_S3} ]] \
	&& log "looks like S3 connection is defined and ok"

# if InfluxDB options are defined, set them up and check validity
if [[ -n ${YENTESTS_INFLUXDB_HOST} \
		&& -n ${YENTESTS_INFLUXDB_DB} \
		&& -n ${YENTESTS_INFLUXDB_USER} \
		&& -n ${YENTESTS_INFLUXDB_PWD} ]] ; then 

	# construct a "usable" influxdb URL ("global" env var)
	export YENTESTS_INFLUXDB_URL="${YENTESTS_INFLUXDB_HOST}:${YENTESTS_INFLUXDB_PORT}/write?db=${YENTESTS_INFLUXDB_DB}&u=${YENTESTS_INFLUXDB_USER}&p=${YENTESTS_INFLUXDB_PWD}&precision=s"
	# check this URL for validity...
	
	[[ $? -eq 0 ]] && YENTESTS_UPLOAD_TO_INFLUXDB==1

fi

[[ -n ${YENTESTS_VERBOSE_LOGS} && -n ${YENTESTS_UPLOAD_TO_INFLUXDB} ]] \
	&& log "looks like InfluxDB connection is defined and ok"

# read TEST_ID from a file here, in the home directory. this will be 
# a sequential, unique index... convenient because we could compare
# test runs "chronologically" according to the partial order thus 
# constructed. 
if [[ -f ${YENTESTS_TEST_RIDF} ]] ; then 
	# get and increment the monotonic index
	YENTESTS_TEST_RUNID=$( cat ${YENTESTS_TEST_RIDF} )
	YENTESTS_TEST_RUNID=$(( YENTESTS_TEST_RUNID + 1 ))
else 
	# at least make sure the directory exists, and is g+rw
	makeOpenDirectory ${YENTESTS_TEST_RIDF%/*}
	# and, lacking a history, intialize the RUNID to 1
	YENTESTS_TEST_RUNID=1
fi 

# re-write the runid into the run id file (initialized or incremented)
echo "${YENTESTS_TEST_RUNID}" > ${YENTESTS_TEST_RIDF}
export YENTESTS_TEST_RUNID # again, export vs .defaults? 

# create TEST_ID as a date-like string? that would be globally unique, 
# but not _immediately_ comparable as easily as a monotonic index, nor would
# it be "resettable" should we want that

# hashes: if using, at least make sure the directory exists, and is g+rw
[[ -f ${YENTESTS_HASH_LOG} ]] \
	|| makeOpenDirectory ${YENTESTS_HASH_LOG%/*}

# define "todo" file, if not customized
[[ -z ${YENTESTS_TESTS_TODO_FILE} ]] \
	&& export YENTESTS_TESTS_TODO_FILE="${YENTESTS_TMP_LOG_DIR}/${YENTESTS_TEST_HOST}-todo"

# define "done" file, if not customized
[[ -z ${YENTESTS_TESTS_DONE_FILE} ]] \
	&& export YENTESTS_TESTS_DONE_FILE="${YENTESTS_TMP_LOG_DIR}/${YENTESTS_TEST_HOST}-done"

# if tests listed to exclude, make a test list with all those NOT matching 
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

# store relevant env vars for use in test suites... we will clean and reload this on each run
# quotes here make sure we can abstract away bash shell special character issues (like with $ or &)
env | grep '^YENTESTS_DEFAULT' | sed -E 's|^([^=]+=)(.*)$|\1"\2"|g' > .defaults

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# RUNNING
# 
# Basically just a loop over the test suites included in tests/, or specified with a list
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

log "starting yentests..."

# loop over test suites...
for d in tests/** ; do 

	# if passed a list, only run test suites in that list; otherwise, run ALL tests
	if [[ -n ${YENTESTS_TEST_LIST} ]] ; then 

		# this is a double loop, which isn't literally required. we could just scan the
		# list, and run over those directories. but that optimization probably won't matter. 
		TEST_SUITE_DIR=$( echo ${d} | grep -oP "[^/]*$" )
		while read LI ; do 
			if [[ ${TEST_SUITE_DIR} =~ ${LI} ]] ; then runTestSuite ${d} && break ; fi
		done < <( echo ${YENTESTS_TEST_LIST} | tr ',' '\n' )

	else # no list, run all tests

		runTestSuite ${d}

	fi 

done

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# POSTPROCESSING
# 
# "Batch" upload results to S3 and/or InfluxDB, if we are, now that tests were done. 
# And clean up after ourselves. 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# now that tests are done, upload to S3 IF we upload to S3
if [[ -n ${YENTESTS_UPLOAD_TO_S3} ]] ; then 
	if [[ -f ${YENTESTS_TMP_LOG_DIR}/sf3upload.csv ]] ; then 
		aws s3 cp ${YENTESTS_TMP_LOG_DIR}/s3upload.csv \
			"s3://${YENTESTS_S3_BUCKET}/${YENTESTS_S3_PREFIX}/${YENTESTS_TEST_HOST}-$( date +%s ).csv" \
			> ${YENTESTS_TMP_LOG_DIR}/s3upload.log 2>&1
		if [[ $? -ne 0 ]] ; then 
			log "post to S3 appears to have failed..."
			cat ${YENTESTS_TMP_LOG_DIR}/s3upload.log
		fi 
		rm ${YENTESTS_TMP_LOG_DIR}/s3upload.*
	else 
		echo "upload to S3, but \"${YENTESTS_TMP_LOG_DIR}/s3upload.csv\" is not defined"
	fi 
fi 

# now that tests are done, upload to InfluxDB IF we upload to InfluxDB
if [[ -n ${YENTESTS_UPLOAD_TO_INFLUXDB} ]] ; then
	CURL_STAT=$( curl -k -s -w "%{http_code}" -o ${YENTESTS_TMP_LOG_DIR}/curl.log \
					-X POST "${YENTESTS_INFLUXDB_URL}" --data-binary "@${YENTESTS_TMP_LOG_DIR}/influxdbupload.lpf" )
	if [[ ${CURL_STAT} -ne 204 ]] ; then 
		log "upload to InfluxDB appears to have failed (${CURL_STAT})"
		[[ -f ${YENTESTS_TMP_LOG_DIR}/curl.log ]] \
			&& cat ${YENTESTS_TMP_LOG_DIR}/curl.log
	else
		[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
			&& log "wrote test summary data to influxdb"
	fi
	rm ${YENTESTS_TMP_LOG_DIR}/curl.log > /dev/null 2>&1 
fi

# don't need .defaults anymore... delete if we don't explicitly say to keep
[[ -z ${YENTESTS_KEEP_DEFAULTS_FILE} ]] \
	&& rm .defaults > /dev/null 2>&1

# don't need the "global" environment variables (YENTESTS_*) anymore, EXCEPT any existing YENTESTS_TEST_HOME?
# that's a problem, which I hope we correct with a post-cleaning reset
unsetEnvVarsMatchingPrefix "YENTESTS_"

# replace stored YENTESTS_TEST_HOME value, if it exists
[[ -n ${REVERTABLE_YENTESTS_TEST_HOME} ]] \
	&& export YENTESTS_TEST_HOME=${REVERTABLE_YENTESTS_TEST_HOME}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# 
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 