#!/bin/sh
# SPDX-License-Identifier: Unlicense
# shellcheck disable=SC2015
cd "${0%/*}" || exit
template=../dist/template.sh
succeeded=0
skipped=0
failed=0

failure() { failed=$((failed + 1)) && printf '%s - Failure\n' "$shell" || :; }

for shell in ash dash bash mksh './sh'; do
	printf '%s - Starting test…\n' "$shell"
	if ! command -v "$shell" >/dev/null; then
		skipped=$((skipped + 1))
		printf '%s - Could not find shell interpreter, skipping\n' "$shell"
		continue
	fi
	case "$shell" in bash | mksh) cmd="${shell} -o posix" ;; *) cmd=$shell ;; esac
	$cmd ${template} -s ./test.context.sh -e ARG_VERSION=0.99.1-pre level_1.template >|level_1.out &&
		diff level_1.expected level_1.out || { failure && continue; }

	$cmd ${template} preproc_test.template >|preproc_test.out &&
		diff preproc_test.expected preproc_test.out || { failure && continue; }

	succeeded=$((succeeded + 1))
	printf '%s - Success\n' "$shell"
done

printf '\n%s Succeeded\n%s Skipped\n%s Failed\n\n' "$succeeded" "$skipped" "$failed"
exit "$failed"
