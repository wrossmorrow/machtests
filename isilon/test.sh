#!/bin/bash

# Test Isilon Network File Server
# Create sample files
# touch testfile{0001..1000}.txt

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="Isilon File System"

testCommand "ls -l $PWD"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
