#!/bin/bash

# test stata-mp software package

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="stata-mp"
ml="module load statamp"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "stata-mp -b $script_home/test.do"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
