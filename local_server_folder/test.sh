#!/bin/bash

# test local server file system

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="Local Server Folder"

testCommand "ls -la /tmp"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
