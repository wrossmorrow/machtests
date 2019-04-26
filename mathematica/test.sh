#!/bin/bash

# test mathematica software package

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="mathematica"
ml="module load $software"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "wolframscript -script $script_home/test.m"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
