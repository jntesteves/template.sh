#!/bin/sh
# SPDX-License-Identifier: Unlicense
script_dir=$(realpath "$(dirname "$0")")
[ -d "$script_dir" ] && cd "$script_dir" && :

template=../dist/template.sh

$template -s test.context.sh -e ARG_VERSION=0.99.1-pre level_0.template >|level_0.out
diff level_0.expected level_0.out

$template preproc_test.template >preproc_test.out
diff preproc_test.expected preproc_test.out
