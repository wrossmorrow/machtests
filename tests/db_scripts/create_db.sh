#!/bin/bash

# create sqlite database and tables if does not exist

script_home=$( dirname $(realpath 0$) )
db=yentestsv0.db
dbfile="$script_home/$db"

#check database file
if [ ! -f "$dbfile" ] ; then
   echo "Creating sqlite database $dbfile and tables"
   sqlite3 $dbfile ".databases ; .exit ;"
   sqlite3 $dbfile ".read $script_home/create_tables.sql"
fi