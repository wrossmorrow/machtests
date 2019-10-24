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
function _testCommand() {

	[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
		&& log "testing command \"${1}\""

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# START TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	YENTESTS_TEST_START=$( date +%s )
	YENTESTS_TEST_DATETIME=$( date +"%FT%T.%N" )
    
	# set log files
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
		TMP_TEST_TIMEDOUT=0
	else # time log doesn't exist or is empty; means the command timed out
		YENTESTS_TEST_DURATION=${YENTESTS_TEST_TIMEOUT}
		TMP_TEST_TIMEDOUT=1
	fi
	# set a min value for time so the record can be caught by the kapacitor alert
	[[ ${YENTESTS_TEST_DURATION} == '0.00' ]] && YENTESTS_TEST_DURATION=0.01

	# check exit code and set success flag
	[[ ${YENTESTS_TEST_EXITCODE} -eq 0 ]] && TMP_SUCCESS="S" || TMP_SUCCESS="F"

	YENTESTS_TEST_STATUS="${YENTESTS_TEST_RUNID},${YENTESTS_TEST_NAME},${TMP_SUCCESS},${TMP_TEST_TIMEDOUT},${YENTESTS_TEST_EXITCODE},${YENTESTS_TEST_DURATION},${YENTESTS_TEST_ERROR}"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# FINISHED TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	echo "${YENTESTS_TEST_DATETIME},${YENTESTS_TEST_STATUS}" >> ${YENTESTS_TEST_RESULTS}

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE RESULTS TO INFLUXDB
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	#replace spaces in names (and host?) with _ to prevent invalid field format error return from influxdb

	# string we'll want to write to influxdb... 
	# 
	# 	tags: each of these things we might want to search/groupby over and should be indexed
	# 
	# 		host - the host the test was run on
	# 		test - the name of the test
	# 		hash - the hash of the test run, like a test version number
	# 		code - the exit code from the test
	# 
	# 	fields: these things we might want to plot/aggregate
	# 
	#		runid - the runid of the test run (? should this be a tag?)
	# 		xtime - execution time of the test
	#		cpu   - (FUTURE) the cpu utilization of the test
	#		mem   - (FUTURE) the memory utilization of the test
	#		procs - (FUTURE) the number of processes spun up by the test
	# 
	TMP_INFLUXDB_TAGS="host=${YENTESTS_TEST_HOST},test=${YENTESTS_TEST_NAME//[ ]/_},tver=${YENTESTS_TEST_VERSION},hash=${YENTESTS_TEST_HASH},code=${YENTESTS_TEST_EXITCODE}"
	TMP_INFLUXDB_FIELDS="runid=${YENTESTS_TEST_RUNID},xtime=${YENTESTS_TEST_DURATION}"
	TMP_INFLUXDB_DATA="${YENTESTS_INFLUXDB_DB},${TMP_INFLUXDB_TAGS} ${TMP_INFLUXDB_FIELDS} ${YENTESTS_TEST_START}"

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

		log "starting ${YENTESTS_TEST_NAME}" 

		# run the test
		_testCommand "bash ${YENTESTS_TEST_FILE}"

		log "finished ${YENTESTS_TEST_NAME}"

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

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# ARGUMENT PARSING
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# -r: reset run ids
# -d: dryrun tests
# -v: use verbose prints to the logs

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# PREPROCESSING: SETUP ENVIRONMENT AND THINGS FOR TEST RUNS
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

echo "starting yentests..."

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
# 	YENTESTS_TEST_{HOME,LOGS,HOST,RIDF,TIMEOUT} (HOME defined above though...)
# 	YENTESTS_HASH_LOG
# 	YENTESTS_RUN_LOG
# 	YENTESTS_SQLITE_{DB,FILE}
# 	YENTESTS_INFLUXDB_{HOST,PORT,DB,USER,PWD}
# 
[[ -f .env ]] && set -a && source .env && set +a

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
	echo "$( date +"%FT%T" ): $1"
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

if [[ ! -f ${YENTESTS_HASH_LOG} ]] ; then 
	# at least make sure the directory exists
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

# store relevant env vars for use in test suites... we will clean and reload this on each run
# quotes here make sure we can abstract away bash shell special character issues (like with $ or &)
env | grep '^YENTESTS_' | sed -E 's|^([^=]+=)(.*)$|\1"\2"|g' > .defaults

# loop over test suites
for d in tests/*/ ; do 

	# enter this test suite directory
	cd ${d}
	
	# run test.sh file in target folder, if it exists
	[[ -f test.sh ]] && testScript test.sh

	# if there is a "tests" __subfolder__, run ANY scripts in that
	# (run ANY scripts so we don't have to mess with making a "manifest")
	# any such script should expect to run from the directory "$d", not tests
	if [[ -d tests ]] ; then 
		for t in tests/*.sh ; do testScript ${t} ; done
	fi
	
	# leave the test suite directory by returning to the working directory for all tests
	cd ${_YENTESTS_TEST_HOME}

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