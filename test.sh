#!/bin/bash

# script process id when run
PID=$$

# application home folder
export app_home=/ifs/yentools/yentests

cd $app_home

# setup environmentals
source $app_home/env.sh

# create parent test record for entire run.  get the rowid of the parent record and assign to test_id
sqlite3 $test_db_file "insert into tests (server, test_date) values (\"$host\", \"$test_dt\");"
export test_id=$(sqlite3 $test_db_file "select rowid from tests where server=\"$host\" and test_date=\"$test_dt\";")
echo "Test Record ID = $test_id"

for d in */ ;
do 
	echo -e "\n$d"
	
	# check for test.sh file in target folder
	if [[ -f ${d}/test.sh ]] ; then
		RUNDIR=${PWD}
		cd ${d}
		bash test.sh -h
		cd ${RUNDIR}
		
		# gather process info; !!! needs rework !!!
		pid_info=$( ps -p ${PID} -o uname,pid,nlwp,pcpu,pmem,psr --no-headers )
	fi 
done

# update process info on parent. !!! need rework !!! 
sqlite3 $test_db_file "UPDATE tests \
	SET ps_info =  \"${pid_info}\"
	WHERE rowid = ${test_id};"
