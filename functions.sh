#!/bin/bash

# test command and setup result variables
# $1 = command to test
testCommand() {

	log "testing command \"$1\""

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# START TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	TEST_TIME=$( date +%s )
	
	timeout=60 # define ONCE... in global test suite environment
    
	# set log files
	time_log="$script_home/time.log"
	output_log="$script_home/output.log"

	# remove previous log files
	rm -f "$script_home/*.log"
	
	# how to execute this conditional on script?
	if [[ $1 == *"module"* || $1 == *"matlab"* ]]; then
		# exception for module and matlab. find one command to handle all cases
		# test command with no timeout
		{ time -p $1 > $output_log 2>&1 ; } > $time_log 2>&1
	else
		# test command with timeout
		{ timeout --preserve-status $timeout /usr/bin/time -p -o $time_log $1 > $output_log 2>&1 ; }
	fi
	exit_code=$?
	
	# check output log and set variable
	cmd_output=$( cat ${output_log} )
	[[ -z "$cmd_output" ]] && cmd_output="OUTPUT BLANK"

	# check time log is not empty
	# set time variable from time log, with a min value for time so the record can be caught by the kapacitor alert
	if [[ -f $time_log && -s $time_log ]]; then
		time_real=$( egrep -i '^real' $time_log | awk '{ print $2 }' )
		[[ $time_real == '0.00' ]] && time_real=0.10
	else # time log empty; the command timed out
		time_real=$timeout
	fi

	# check exit code and set debug message
	[[ $exit_code -eq 0 ]] \
		&& status="SUCCESS | $exit_code | $time_real sec " \
		|| status="FAILURE | $exit_code | $time_real sec | $cmd_output"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# FINISHED TEST
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	log "Tested: $input_cmd ==> $status"

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# WRITE RESULTS TO INFLUXDB
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

	#replace space with _ prevent invalid field format error return from influx db
	name=${TEST_NAME//[ ]/_}
	host_name=${host//[ ]/_}

	# string we'll want to write to influxdb
	influx_data="'yentests,host=$host_name,test=$name,code=$exit_code extime=$time_real,testid=${TEST_TESTID},runid=${TEST_RUNID} ${TEST_TIME}'"

	# post data to the yentests database in InfluxDB
	curl -s -k -X POST $influx_url --data-binary $influx_data

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
	# 
	# DONE
	# 
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

}

# test a script and setup result variables
# $1 = path to script to test
# 
# Expects "TEST_HASH_LOG" to be defined
# 
testScript() {

	# don't do anything unless passed a real file
	if [[ -f ${1} ]] ; then

		# strip PWD from filename, if it was passed
		FILE=$( echo ${1/$PWD/} | sed -E 's|^/+||' )

		# define the test's name
		TEST_NAME=$( sed -En "/^[ ]*#[ ]*@name (.*)/{p;q}" ${FILE} | sed -E "s/^[ ]*#[ ]*@name (.*)/\1/" )
		if [[ -z ${TEST_NAME} ]] ; then 
			TEST_NAME="${PWD}/${1}"
		fi

		# if we have a hash log file to store hashes in, use that
		if [[ -z ${TEST_HASH_LOG} ]] ; then 

			if [[ -f ${TEST_HASH_LOG} ]] ; then 

				# define test version (with a default)
				TEST_VERS=$( sed -En "/^[ ]*#[ ]*@version (.*)/{p;q}" ${FILE} | sed -E "s/^[ ]*#[ ]*@version (.*)/\1/" )
				if [[ -z ${TEST_VERS} ]] ; then TEST_VERS=0 ; fi

				# find the hash of this test-version to use as a test id across runs, or create/update it
				TEST_HASH_LINE=$( sed -En "|^${PWD}/${FILE},[^,]+,(.*)|{p;q}" ${TEST_HASH_LOG} )
				if [[ -z ${TEST_HASH_LINE} ]] ; then 
					TEST_HASH=$( sha256sum ${FILE} )
					echo "${PWD}/${FILE},${TEST_VERS},${TEST_HASH}" >> ${TEST_HASH_LOG}
				else 
					TEST_VASH=$( echo ${TEST_HASH_LINE} | sed -E "s|^${PWD}/${FILE},([^,]+),.*|\1|" )
					TEST_HASH=$( echo ${TEST_HASH_LINE} | sed -E "s|^${PWD}/${FILE},[^,]+,(.*)|\1|" )
					if [[ ${TEST_VASH} -ne ${TEST_VERS} ]] ; then
						TEST_HASH=$( sha256sum ${FILE} )
						sed -i.bak "s|^${PWD}/${FILE},[^,]+,(.*)|${PWD}/${FILE},${TEST_VERS},${TEST_HASH}|" ${TEST_HASH_LOG}
					fi
				fi

			else 
				TEST_HASH=$( sha256sum ${FILE} )
				echo "${PWD}/${FILE},${TEST_VERS},${TEST_HASH}" >> ${TEST_HASH_LOG}
			fi 

		else # no known file to log this value in, so just do the naive thing and create it
			TEST_HASH=$( sha256sum ${FILE} ) 
		fi

		# export a test id to store ** NOT PARALLEL SAFE **
		export TEST_NAME=${TEST_NAME}
		export TEST_TESTID=${TEST_HASH}

		# create an id from a hash of the script provided, creating that if it doesn't exist
		testCommand "bash ${FILE}"

	fi
}

# store database record in sqlite3
# $1 = test name
# $2 = test command
# $3 = exit code
# $4 = command output
# $5 = command execution time in sec
# $test_db_file = location of sqlite database
storeTestRecordInSqlite() {

	# generate a random key and attach to test record.
	# key will be used to located test record to get the rowid
	generateRandomKey
	key_id=\"$testIdKey\"

	name=\"$1\"
	command=\"${2//\"/\"\"}\"
	exit_code=$3
	command_output=\"$4\"
	execution_time_sec=$5
	
	if [ $exit_code -ne 0 ]; then
		# error; capture the error return from the command
		sqlite3 $test_db_file "insert into test_results \
				(test_id, key_id, name, command, exit_code, execution_time_sec, command_output) \
				values \
				($test_id, $key_id, $name, $command, $exit_code, $execution_time_sec, $command_output);"
	else
		# NO error
		sqlite3 $test_db_file "insert into test_results \
				(test_id, key_id, name, command, exit_code, execution_time_sec) \
				values \
				($test_id, $key_id, $name, $command, $exit_code, $execution_time_sec);"
	fi
	
	# rowid of inserted test_results record for influxdb
	export seq_id=$(sqlite3 $test_db_file "select rowid from test_results where key_id=$key_id;")

}

# store test results in InfluxDB
# $1 = test name
# $2 = exit code
# $3 = command execution time
# $host = server host name
# $job_id = parent job_id for the entire run from $app_home/test.sh
# $seq_id = specific id for the current test generated in storeTestRecordInSqlite()
storeTestRecordInInfluxDB() {

	#replace space with _ prevent invalid field format error return from influx db
	name=${1//[ ]/_}
	host_name=${host//[ ]/_}

	exit_code=$2
	execution_time=$3
	job_id=$test_id
	seq_id=$seq_id
	test_time=$test_dt_influx # needs to be pegged to the test START time... and it is as above

	# define this ONCE... AND FOR GODS SAKE DON'T INCLUDE THE PASSWORD
	# influx_url="'https://monitor.gsbrss.com:8086/write?db=yentests&u=influx&p=influx&precision=s'"

	# string we'll want to write to influxdb
	influx_data="'yentests,host=$host_name,test=$name,code=$exit_code extime=$execution_time,jobid=$job_id,seqid=$seq_id $test_time'"

	# post data to the yentests database in InfluxDB
	curl -s -k -X POST $influx_url --data-binary $influx_data

}

# store test results to different databases
storeTestRecord() {
	log "storing test record"
	storeTestRecordInSqlite "$1" "$2" "$3" "$4" "$5"
	storeTestRecordInInfluxDB "$1" "$3" "$5"
}

# generate random key
generateRandomKey() {
	testIdKey=$( openssl rand -hex 16 )
}