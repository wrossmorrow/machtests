#!/bin/bash

# test R software package

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="R"
ml="module load $software"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "Rscript $script_home/test.r"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
