# SPDX-License-Identifier: Unlicense
# v0.1.0-pre
# shellcheck shell=sh
#
# This file is part of dot-slash-make https://codeberg.org/jntesteves/dot-slash-make
# Do NOT make changes to this file, your commands go in the ./make file
#
echo() (IFS=' ' && printf '%s\n' "$*")
log_error() (IFS=' ' && printf 'ERROR %s\n' "$*" >&2)
log_warn() (IFS=' ' && printf 'WARN %s\n' "$*" >&2)
log_info() (IFS=' ' && printf '%s\n' "$*")
log_debug() { :; } && [ "$MAKE_DEBUG" ] && log_debug() (IFS=' ' && printf 'DEBUG %s\n' "$*")
log_trace() { :; } && case "$MAKE_DEBUG" in *trace*) log_trace() (IFS=' ' && printf 'TRACE %s\n' "$*") ;; esac
abort() {
	__abort__status=${2:-$?}
	log_error "$1" || :
	exit "$__abort__status"
}

# Substitute every instance of character in text with replacement string
# This function uses only shell builtins and has no external dependencies (f.e. on sed)
# This is slower than using sed on a big input, but faster on many invocations with small inputs
substitute_character() (
	set -f # Disable Pathname Expansion (aka globbing)
	IFS="$1"
	case "$1" in :) pad=^ ;; *) pad=: ;; esac
	last_field=
	first=1
	for field in ${3}${pad}; do
		[ "$first" ] || printf '%s%s' "$last_field" "$2"
		last_field="$field"
		first=
	done
	printf '%s' "${last_field%?}"
)

# Escape text for use in a shell script single-quoted string (shell builtin version)
escape_single_quotes() { substitute_character \' "'\\''" "$1"; }

# Run command in a sub-shell, abort on error
run() {
	log_info "$@"
	("$@") || abort "${0}: [target: ${__target}] Error ${?}"
}

# Run command in a sub-shell, ignore returned status code
run_() {
	log_info "$@"
	("$@") || log_warn "${0}: [target: ${__target}] Error ${?} (ignored)"
}

# Use indirection to dynamically assign a variable from argument NAME=VALUE
assign_variable() {
	case "${1%%=*}" in *[!_a-zA-Z0-9]* | [!_a-zA-Z]*) return 2 ;; esac
	eval "${1%%=*}='$(escape_single_quotes "${1#*=}")'"
}

# Check if the given name was provided as an argument in the CLI
__dsm__is_in_cli_parameters_list() (
	log_trace "dot-slash-make: [__dsm__is_in_cli_parameters_list] var_name='${1}' __dsm__cli_parameters_list='${__dsm__cli_parameters_list}'"
	for arg in $(list_from "$__dsm__cli_parameters_list"); do
		[ "$1" = "$arg" ] && return 0
	done
	return 1
)

__dsm__set_variable_cli_override() {
	__dsm__var_name="${2%%=*}"
	if [ "$1" ] && __dsm__is_in_cli_parameters_list "$__dsm__var_name"; then
		log_debug "dot-slash-make: [${1}] '${__dsm__var_name}' overridden by command line argument"
		return 0
	fi
	assign_variable "$2" || abort "${0}:${1:+" [$1]"} Invalid parameter name '${__dsm__var_name}'"
	[ "$1" ] || __dsm__cli_parameters_list="${__dsm__cli_parameters_list}${__dsm__var_name} "
	eval "log_debug \"dot-slash-make: [${1:-__dsm__set_variable_cli_override}] ${__dsm__var_name}=\$${__dsm__var_name}\""
}

# Set variable from argument NAME=VALUE, only if it was not overridden by an argument on the CLI
param() { __dsm__set_variable_cli_override param "$@"; }

# Test if any of the arguments is itself a list according to the current value of IFS
is_list() (
	for item in "$@"; do
		case "$item" in *["$IFS"]*) return 0 ;; esac
	done
	return 1
)

list_length() { printf '%s' "$#"; }

# Test if lists should have a trailing field separator in the current shell (most do, zsh differs)
# shellcheck disable=SC2086
__list__is_terminated() { __l=x${IFS%"${IFS#?}"} && [ "$(list_length $__l)" -eq 1 ]; }

# Turn arguments into a list of items separated by IFS
list() (
	if is_list "$@"; then
		printf 'list error: list items cannot be lists\n' >&2
		return 1
	fi
	lt=
	__list__is_terminated && lt=${IFS%"${IFS#?}"}
	[ "$#" -eq 0 ] || printf '%s' "${*}${lt}"
)

# $(list_from text [separator]): Turn text into a list splitting at each occurrence of separator
# If separator isn't provided the default value of IFS is used (space|tab|line-feed)
list_from() (
	set -f # Disable globbing
	str=$1
	__list__is_terminated || case "$1" in *["$2"]) str="${1%?}" ;; esac
	outer_ifs=$IFS
	IFS=${2:-' 	''
'}
	# shellcheck disable=SC2086
	IFS=$outer_ifs list $str
)

# Use pattern to format each subsequent argument, return a list separated by IFS
fmt() {
	__pattern=$1
	shift || {
		printf 'fmt error: a format pattern must be provided\n' >&2
		return 1
	}
	# shellcheck disable=SC2059
	if [ "$#" -gt 0 ]; then list_from "$(printf "${__pattern}${IFS%"${IFS#?}"}" "$@")" "${IFS%"${IFS#?}"}"; fi
}

# Perform tilde- and pathname-expansion (globbing) on arguments
# Similar behavior as the wildcard function in GNU Make
wildcard() (
	outer_ifs=$IFS
	IFS=
	buffer=
	for pattern in "$@"; do
		case "$pattern" in
		'~') pattern=$HOME ;;
		'~'/*) pattern="${HOME}${pattern#'~'}" ;;
		esac
		set +f # Enable globbing
		for file in $pattern; do
			set -f
			# shellcheck disable=SC2086
			[ -e "$file" ] && { buffer=$(IFS=$outer_ifs && list $buffer "$file") || return; }
		done
	done
	printf '%s' "$buffer"
)

list_targets() { list_from "$__dsm__targets"; }

set -f               # Disable globbing (aka pathname expansion)
IFS=$(printf '\037') # Use ASCII 0x1F as field separator for "quasi-lossless" lists
__dsm__cli_parameters_list=
__dsm__targets=
__target=
for __dsm__arg in "$@"; do
	case "$__dsm__arg" in
	[_a-zA-Z]*=*) [ "$DSM_SKIP_CLI_VARIABLES" ] || __dsm__set_variable_cli_override '' "$__dsm__arg" ;;
	-*) [ "$DSM_SKIP_CLI_OPTIONS" ] || abort "${0}: invalid option '${__dsm__arg}'" ;;
	*) __dsm__targets="${__dsm__targets}${__dsm__arg} " ;;
	esac
done
[ "$__dsm__targets" ] || __dsm__targets=-
log_debug "dot-slash-make: targets list: '${__dsm__targets}'"
