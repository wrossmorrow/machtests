#!/bin/bash

# test command and setup result variables
# $1 = command to test
testCommand() {
	export test_dt_influx=$( date +%s )
	
	input_cmd="$1"
	timeout=60
    
	# set log files
	time_log="$script_home/time.log"
	output_log="$script_home/output.log"

	# remove previous log files
	rm -f "$script_home/*.log"
	
	if [[ $input_cmd == *"module"* || $input_cmd == *"matlab"* ]]; then
		# exception for module and matlab. find one command to handle all cases
		# test command with no timeout
		{ time -p $input_cmd 1>$output_log 2>$output_log ; } 1>$time_log 2>$time_log
	else
		# test command with timeout
		{ timeout --preserve-status $timeout /usr/bin/time -p -o $time_log $input_cmd 1>$output_log 2>$output_log ; }
	fi
	exit_code=$?
	
	# check output log and set variable
	cmd_output=$(cat ${output_log})
	[[ -z "$cmd_output" ]] && cmd_output="OUTPUT BLANK"

	# check time log is not empty
	if [[ -f $time_log && -s $time_log ]]; then
		# set time variable from time log
		time_real=$(egrep -i '^real' $time_log | awk '{print $2}')

		# set min value for time so the record can be caught by the kapacitor alert
		[[ $time_real = '0.00' ]] && time_real=0.10
	else
		# time log empty; the command timed out
		time_real=$timeout
	fi

	# check exit code and set debug message
	[[ $exit_code -eq 0 ]] && status="SUCCESS | $exit_code | $time_real sec " || status="FAILURE | $exit_code | $time_real sec | $cmd_output"
	echo "Testing: $input_cmd ==> $status"
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
	test_time=$test_dt_influx

	influx_url="'https://monitor.gsbrss.com:8086/write?db=yentests&u=influx&p=influx&precision=s'"
	influx_data="'yentests,host=$host_name,test=$name,code=$exit_code extime=$execution_time,jobid=$job_id,seqid=$seq_id $test_time'"

	# post data to the yentests database in InfluxDB
	command="curl -k -X POST $influx_url --data-binary $influx_data"
	
	eval $command
}

# store test results to different databases
storeTestRecord() {
	echo "storeTestRecord"
	storeTestRecordInSqlite "$1" "$2" "$3" "$4" "$5"
	storeTestRecordInInfluxDB "$1" "$3" "$5"
}

# generate random key
generateRandomKey() {
	testIdKey=$( openssl rand -hex 16 )
}