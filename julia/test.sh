#!/bin/bash

# test julia software package

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="julia"
ml="module load $software"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "julia -e \"exit()\""
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
