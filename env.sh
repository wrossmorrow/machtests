#!/bin/bash

# setup application home variable
[[ -z "$app_home" ]] && app_home=/ifs/yentools/yentests

# setup database variables
test_db=yentests.db
test_db_file="$app_home/db_scripts/$test_db"

test_dt=$( date +%F-%T )

export host=$HOSTNAME

# NO PASSWORDS IN TRACKED FILES

influx_url="'https://monitor.gsbrss.com:8086/write?db=yentests&u=influx&p=influx&precision=s'"

# setup module system
source /etc/profile.d/lmod.sh

source $app_home/functions.sh
