#!/bin/sh
# SPDX-License-Identifier: Unlicense
script_dir=$(realpath "$(dirname "$0")")
[ -d "$script_dir" ] && cd "$script_dir" && :

template=../dist/template.sh

$template -s test.context.sh -e ARG_VERSION=0.99.1-pre level_1.template >|level_1.out &&
	diff level_1.expected level_1.out || return 1

$template preproc_test.template >preproc_test.out &&
	diff preproc_test.expected preproc_test.out || return 1
