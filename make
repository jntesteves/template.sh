#!/bin/sh
# shellcheck disable=SC2046,SC2086
DSM_SKIP_CLI_OPTIONS='' DSM_SKIP_CLI_VARIABLES='' . ./dot-slash-make.sh

param BUILD_DIR=./dist
param PREFIX="${HOME}/.local"
version=0.1.0-pre
app_name=template.sh
dist_bin=${BUILD_DIR}/${app_name}
shell_scripts=$(wildcard ./*.sh ./make ./test/*.sh)
selinux_flag=-Z
# Detect if the SELinux flag (-Z) is supported by the install command on the target platform
case $(install -Z 2>&1) in *'unrecognized option'*) selinux_flag= ;; esac
lint() {
	run shellcheck "$@"
	run shfmt -d "$@"
}
build() {
	case $version in *[!.0-9]*) version_is_pre_release=1 ;; *) version_is_pre_release= ;; esac
	git_status=$(git --no-optional-locks status --porcelain) || abort "Failed to read git status"
	git_last_commit_info=$(git --no-optional-locks log -1 --pretty='format:(%h %cs)') || abort "Failed to read git log"
	git_tree_is_dirty=${git_status:+1}
	version_git="${version}${git_tree_is_dirty:+"+dirty"}${version_is_pre_release:+ $git_last_commit_info}"
	./template.sh -e VERSION=${version_git} ${app_name} >${dist_bin} || abort "Failed to write file ${dist_bin}"
	chmod +x ${dist_bin} || abort "Failed to chmod file ${dist_bin}"
}
test() { run ./test/test.sh; }

for __target in $(list_targets); do
	case "${__target}" in
	dist | -)
		run mkdir -p ${BUILD_DIR}
		lint ${shell_scripts}
		run build
		lint ${dist_bin}
		test
		;;
	install)
		run install -D ${selinux_flag} -m 755 -t "${PREFIX}/bin" ${dist_bin}
		;;
	uninstall)
		run rm -f "${PREFIX}/bin/${app_name}"
		;;
	clean)
		test_output_files=$(wildcard ./test/*.out)
		[ ! "$test_output_files" ] || run_ rm -r ${test_output_files}
		;;
	test)
		test
		;;
	lint)
		lint ${shell_scripts} ${dist_bin}
		;;
	format)
		run shfmt -w ${shell_scripts}
		;;
	dev-image)
		run podman build -f Containerfile.dev -t template-sh-dev
		;;
	# dot-slash-make: This * case must be last and should not be changed
	*) abort "No rule to make target '${__target}'" ;;
	esac
done
