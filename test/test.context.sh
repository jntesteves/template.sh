# SPDX-License-Identifier: Unlicense
# shellcheck shell=sh disable=SC2034
# $0 in a context file sourced with the -s option is the command template.sh itself.
# Changed from $0 to hardcoding the value here to improve test reproducibility
COMMAND=../dist/template.sh
VERSION=0.1.0-pre
TAG='tag'
TWO_NEW_LINES='

'
A() { printf '#a'; }
B() { printf '#b'; }
C() { printf '#c'; }
D() { printf '#d'; }
E() { printf '#e'; }
