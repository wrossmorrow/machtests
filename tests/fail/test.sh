#!/bin/bash
# 
# @name fail
# @description fail on purpose, to make sure we see failures
# @version 1
# @notimeout
# @created 10/24/19
# @author W. Ross Morrow
# 
echo "this is an error message" 1>&2
exit 1