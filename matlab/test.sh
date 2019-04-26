#!/bin/bash

# test matlab software package

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="matlab"
ml="module load $software"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "matlab -nodisplay -nosplash -nodesktop -batch \"exit\""
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
