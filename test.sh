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

	TMP_LOG_DIR="${YENTESTS_TEST_LOGS}/tmp" && mkdir -p ${TMP_LOG_DIR}
    
	# remove any existing log files set log files
	rm -f "${TMP_LOG_DIR}/tmp/time.log" > /dev/null
	YENTESTS_TEST_TIMELOG="${TMP_LOG_DIR}/time.log"
	YENTESTS_TEST_OUTLOG="${TMP_LOG_DIR}/output.log"
	
	if [[ -n ${YENTESTS_DRY_RUN} ]] ; then 

		log "DRYRUN: here we would actually run a test..."
		YENTESTS_TEST_EXITCODE=0

	else 

		log "DEBUGGING: here we would actually run a test..."

		# use env var to signal whether to use a timeout
		#if [[ -z ${YENTESTS_TIME_TIMEOUT} ]] ; then
		#	{ time -p ${1} > ${YENTESTS_TEST_OUTLOG} 2>&1 ; } > ${YENTESTS_TEST_TIMELOG} 2>&1
		#else # test command with timeout
		#	{ timeout --preserve-status ${YENTESTS_TEST_TIMEOUT} \
		#		/usr/bin/time -p -o ${YENTESTS_TEST_TIMELOG} ${1} > ${YENTESTS_TEST_OUTLOG} 2>&1 ; }
		#fi
		YENTESTS_TEST_EXITCODE=${?}

	fi
	
	# check output log and set variable
	if [[ -f ${YENTESTS_TEST_OUTLOG} ]] ; then
		YENTESTS_TEST_OUTPUT=$( cat ${YENTESTS_TEST_OUTLOG} )
		[[ -z "$YENTESTS_TEST_OUTPUT" ]] && YENTESTS_TEST_OUTPUT="OUTPUT BLANK"
	else 
		YENTESTS_TEST_OUTPUT="OUTPUT BLANK"
	fi

	# check time log is not empty and set duration from time log
	if [[ -f ${YENTESTS_TEST_TIMELOG} && -s ${YENTESTS_TEST_TIMELOG} ]]; then
		YENTESTS_TEST_DURATION=$( egrep -i '^real' ${YENTESTS_TEST_TIMELOG} | awk '{ print $2 }' )
	else # time log empty; means the command timed out
		YENTESTS_TEST_DURATION=${YENTESTS_TEST_TIMEOUT}
	fi
	# set a min value for time so the record can be caught by the kapacitor alert
	[[ ${YENTESTS_TEST_DURATION} == '0.00' ]] && YENTESTS_TEST_DURATION=0.01

	# check exit code and set debug message
	[[ ${YENTESTS_TEST_EXITCODE} -eq 0 ]] \
		&& YENTESTS_TEST_STATUS="SUCCESS | ${YENTESTS_TEST_EXITCODE} | ${YENTESTS_TEST_DURATION} sec " \
		|| YENTESTS_TEST_STATUS="FAILURE | ${YENTESTS_TEST_EXITCODE} | ${YENTESTS_TEST_DURATION} sec | ${YENTESTS_TEST_OUTPUT}"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# FINISHED TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	log "${YENTESTS_TEST_NAME}: ${YENTESTS_TEST_STATUS}"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE RESULTS TO INFLUXDB
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	#replace spaces in names (and host?) with _ to prevent invalid field format error return from influxdb

	# string we'll want to write to influxdb
	YENTESTS_INFLUXDB_DATA_TMP="${YENTESTS_INFLUXDB_DB},
host=${YENTESTS_TEST_HOST},
test=${YENTESTS_TEST_NAME//[ ]/_},
code=${YENTESTS_TEST_EXITCODE} 
xtime=${YENTESTS_TEST_DURATION},
thash=${YENTESTS_TEST_HASH},
runid=${YENTESTS_TEST_RUNID} 
${YENTESTS_TEST_START}"
	YENTESTS_INFLUXDB_DATA=$( echo ${YENTESTS_INFLUXDB_DATA_TMP} | tr -d '\n' )

	# post data to the yentests database in InfluxDB
	if [[ -n ${YENTESTS_DRY_RUN} ]] ; then 
		log "influxdb: ${YENTESTS_INFLUXDB_DATA}"
	else 
		echo "DEBUGGING: ${YENTESTS_INFLUXDB_DATA}"
		# curl -s -k -X POST "'"${YENTESTS_INFLUXDB_URL}"'" --data-binary ${YENTESTS_INFLUXDB_DATA}
	fi

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
			source ${_YENTESTS_TEST_HOME}/.defaults \
				&& [[ -f .env ]] && source .env

			# strip PWD (not FULL path, just PWD) from filename, if it was passed
			YENTESTS_TEST_FILE=$( echo ${1/$PWD/} | sed -E 's|^/+||' )

			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
			# 
			# EXAMINE FRONTMATTER
			# 
			# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

			[[ -n ${YENTESTS_VERBOSE_LOGS} ]] \
				&& log "parsing frontmatter..."

			# define (and export) the test's name, as extracted from the script's frontmatter
			# or... provided in the environment? environment might not guarantee uniqueness. 
			if [[ -z ${YENTESTS_TEST_NAME} ]] ; then 
				YENTESTS_TEST_NAME=$( sed -En "/^[ ]*#[ ]*@name (.*)/{p;q}" ${YENTESTS_TEST_FILE} | sed -E "s/^[ ]*#[ ]*@name (.*)/\1/" )
				if [[ -z ${YENTESTS_TEST_NAME} ]] ; then 
					YENTESTS_TEST_NAME=$( echo ${PWD/$_YENTESTS_TEST_HOME/} | sed -E 's|^/+||' )/${1}
				fi
			fi

			# define test version (with a default)
			YENTESTS_TEST_VERSION=$( sed -En "/^[ ]*#[ ]*@version (.*)/{p;q}" ${YENTESTS_TEST_FILE} | sed -E "s/^[ ]*#[ ]*@version (.*)/\1/" )
			[[ -z ${YENTESTS_TEST_VERSION} ]] && YENTESTS_TEST_VERSION=0

			# unset the timeout if "notimeout" declared in the test script frontmatter
			# if "notimeout" declared, ignore any specified timeout
			if [[ -z $( sed -En "/^[ ]*#[ ]*@notimeout/{p;q}" ${YENTESTS_TEST_FILE} ) ]] ; then 
				unset YENTESTS_TIME_TIMEOUT
			else 
				# if timeout given in frontmatter (in seconds), replace timeout
				if [[ -n $( sed -En "/^[ ]*#[ ]*@timeout [0-9]+/{p;q}" ${YENTESTS_TEST_FILE} ) ]] ; then 
					YENTESTS_TIME_TIMEOUT=$( sed -En "/^[ ]*#[ ]*@timeout [0-9]+/{p;q}" ${YENTESTS_TEST_FILE} | sed -E "/^[ ]*#[ ]*@timeout ([0-9]+)/\1/" )
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

		# log the call to the run the test
		log "${YENTESTS_TEST_RUNID},${YENTESTS_TEST_NAME},${YENTESTS_TEST_HASH}"

		_testCommand "bash ${YENTESTS_TEST_FILE}"

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

		[[ $( env | grep '^YENTESTS' | wc -l ) -ge 1 ]] && log "WARNING: looks like environment wasn't cleaned"

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

# create and export the log function to make it accessible in children
if [[ -z ${YENTESTS_RUN_LOG} ]] ; then
function log() {
	echo "$( date +"%FT%T" ): $1"
}
else 
function log() {
	echo "$( date +"%FT%T" ): $1" >> ${YENTESTS_RUN_LOG}
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
env | grep '^YENTESTS_' > .defaults

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