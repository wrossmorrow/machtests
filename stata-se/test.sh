#!/bin/bash

# test stata-se software package

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="stata-se"
ml="module load statase"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "stata-se -b $script_home/test.do"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
