#!/bin/bash

#query the yentests records

script_home=$( dirname $(realpath 0$) )
test_db=yentests.db
db_folder=$script_home/db_scripts
test_db_file="$db_folder/$test_db"
sqlite3 $test_db_file ".read $db_folder/checktests.sql"
