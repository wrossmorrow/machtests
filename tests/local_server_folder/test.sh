#!/bin/bash
# 
# @name Local Server Folder
# @description test local server file system
# @author Ferdi Evalle
# @created 
# @updated 
# @version
# 

ls -al /tmp

exit

# OLD VERSION BELOW HERE # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

script_home=$( dirname $(realpath 0$) )
source $script_home/../env.sh

software="Local Server Folder"

# Why doesn't this test just say the command, and let an external call wrap that
# with "testCommand ... && storeTestRecord"? 
# 
# That way, the test composer would only need to write what they wanted tested
# 
# 
# 
testCommand "ls -la /tmp"
storeTestRecord "$software" "$input_cmd" "$exit_code" "$cmd_output" "$time_real"
