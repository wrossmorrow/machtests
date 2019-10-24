#!/bin/bash
# 
# @name ml_gurobi
# @description test gurobi software package
# @version 1
# 

module load gurobi

exit

# OLD VERSION BELOW HERE # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="gurobi"
ml="module load $software"

testCommand "$ml"
storeTestRecord "$ml" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"

testCommand "$GUROBI_HOME/bin/gurobi.sh $script_home/test.py"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
