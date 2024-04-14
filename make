#!/bin/sh
# shellcheck disable=SC2046,SC2086
DSM_SKIP_CLI_OPTIONS='' DSM_SKIP_CLI_VARIABLES='' . ./dot-slash-make.sh

param BUILD_DIR=./dist
param PREFIX="${HOME}/.local"
version=0.1.0-pre
app_name=template.sh
shell_scripts=$(wildcard ./*.sh ./make ./test/*.sh)
selinux_flag=-Z
# Detect if the SELinux flag (-Z) is supported by the install command on the target platform
case $(install -Z 2>&1) in *'unrecognized option'*) selinux_flag= ;; esac
lint() {
	run shellcheck "$@"
	run shfmt -d "$@"
}
test() { run ./test/test.sh; }

for __target in $(list_targets); do
	case "${__target}" in
	dist | -)
		run mkdir -p ${BUILD_DIR}
		lint ${shell_scripts}
		run cp ${app_name} "${BUILD_DIR}/${app_name}"
		lint "${BUILD_DIR}/${app_name}"
		test
		;;
	build-skip-checks)
		printf 'Unimplemented\n'
		run return 1
		./template.sh -e VERSION=${version} ${app_name} >"${BUILD_DIR}/${app_name}"
		;;
	install)
		run install -D ${selinux_flag} -m 755 -t "${PREFIX}/bin" "${BUILD_DIR}/${app_name}"
		;;
	uninstall)
		run rm -f "${PREFIX}/bin/${app_name}"
		;;
	clean)
		run_ rm -r ${BUILD_DIR}
		;;
	test)
		test
		;;
	lint)
		lint ${shell_scripts} "${BUILD_DIR}/${app_name}"
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
