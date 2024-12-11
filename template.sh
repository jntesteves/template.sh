#!/bin/sh
# SPDX-License-Identifier: Unlicense
# shellcheck disable=1090
__tpl__usage() {
	fd=${1:+2}
	if [ "$2" ]; then log_error "$2"; fi
	cat <<'EOF' >&"${fd:-1}"
template.sh {{{$VERSION}}}
Render templates and print result to stdout. Expressions within {{{$TLB}}} and {{{$TRB}}} delimiters will be evaluated as shell script and substituted by their stdout in the rendered output. Context variables can be printed directly as {{{$TLB}}}$VAR_NAME{{{$TRB}}} or {{{$TLB}}}'$VAR_NAME'{{{$TRB}}} to escape the result for inclusion in single-quoted shell strings

Usage: template.sh [-C PATH] [-s FILE]... [-e NAME=VALUE]... [--] [- | FILE...]

Options:
 -C PATH               Directory to operate in
 -e, --env NAME=VALUE  Set variable NAME=VALUE in render context
 -s, --source FILE     Source FILE to import its functions/variables in render context
 --help                Print this help text and exit

Environment variables:
 TEMPLATE_SH_DEBUG  Log verbosity, set to 1 or 'trace' to see debug and trace messages

Examples:
 template.sh -s ./program.context.sh program.template.sh >program.sh
 template.sh -e VERSION=1.0 -e TAG=latest program.template.sh >program.sh
EOF
	exit ${1:+"$1"}
}

echo() (IFS=' ' && printf '%s\n' "$*")
log_error() { (IFS=' ' && printf 'ERROR %s\n' "$*" >&2) || :; }
log_debug() { :; } && [ "$TEMPLATE_SH_DEBUG" ] && log_debug() { (IFS=' ' && printf 'DEBUG %s\n' "$*" >&2) || :; }
log_trace() { :; } && case "$TEMPLATE_SH_DEBUG" in *trace*) log_trace() { (IFS=' ' && printf 'TRACE %s\n' "$*" >&2) || :; } ;; esac
abort() {
	__abort__status=${2:-$?}
	[ "$__abort__status" -gt 0 ] || [ "$2" ] || __abort__status=1
	log_error "$1"
	exit "$__abort__status"
}

# Pipeline Error Propagation Protocol
__pepp__hash2() { printf '9OMuo2px''t1duEMvE''pXKp4Us6''T5tAPdHl''\037'; }
__pepp__hash1() { printf '\037''lFCpRISk''bXHRLzR1''PH1YBNcn''QgkFWnJ2'; }
__pepp__status() (
	payload=${1#*"$(__pepp__hash1)"}
	payload=${payload%%"$(__pepp__hash2)"*}
	payload=${payload##*"$(__pepp__hash1)"}
	# If a PEPP message was received, no matter the contents, pipe_check must fail, so coerce status to an error code
	status=$(printf '%.f' "$payload") && [ "$status" -ge 1 ] && [ "$status" -le 255 ] || status=32
	printf '%s' "$status"
)
# shellcheck disable=SC2120
throw() {
	__throw__status=${1:-$?}
	[ "$__throw__status" -gt 0 ] || [ "$1" ] || __throw__status=32
	printf '%s\n' "_$(__pepp__hash1)${__throw__status}$(__pepp__hash2)_" || :
	log_error "[throw] Pipeline aborted with status ${__throw__status}"
	exit "$__throw__status"
}
try() { ("$@") || throw; }
catch() {
	[ "$#" -gt 0 ] || set -- printf '%s'
	__catch__trailing_lf='
'
	while IFS= read -r __catch__line || { __catch__trailing_lf= && [ "$__catch__line" ]; }; do
		case "$__catch__line" in
		*"$(__pepp__hash1)"*"$(__pepp__hash2)"*) exit "$(__pepp__status "$__catch__line")" ;;
		*) "$@" "${__catch__line}${__catch__trailing_lf}" || exit ;;
		esac
	done
}

# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cat.html
# Simple POSIX-compatible cat utility in pure shell script
# shellcheck disable=2120
cat() (
	while :; do
		case "$1" in
		-u) shift ;; # Ignore unused option flag
		--) shift && break ;;
		*) break ;;
		esac
	done
	for filename in "$@"; do # Recursively print each file in arguments
		case "$filename" in
		-) cat || return ;; # Print stdin
		*) cat <"$filename" || return ;;
		esac
	done
	[ "$#" -eq 0 ] || return 0 # Only print from stdin when no arguments
	trailing_lf='
'
	while IFS= read -r line || { trailing_lf= && [ "$line" ]; }; do printf '%s' "${line}${trailing_lf}" || return; done
)

# substitute_characters text pattern [replacement]
# Substitute every instance of the pattern characters in text with replacement string
# This function uses only shell builtins and has no external dependencies (f.e. on sed)
# This is slower than using sed on large inputs, but faster on many invocations with small inputs
substitute_characters() (
	set -f # Disable Pathname Expansion (aka globbing)
	IFS=$2
	unset last_field
	for field in ${1}P; do
		printf '%s' ${last_field+"${last_field}${3}"}
		last_field=$field
	done
	printf '%s' "${last_field%?}"
)

# Escape text for use in a shell script single-quoted string
escape_single_quotes() { substitute_characters "$1" \' "'\\''"; }

# Use indirection to dynamically assign a variable from argument NAME=VALUE
assign_variable() {
	case "${1%%=*}" in '' | *[!_a-zA-Z0-9]* | [!_a-zA-Z]*) return 2 ;; esac
	eval "${1%%=*}"='${1#*=}'
}

__tpl__expand_leftmost_expression() {
	__tpl__match=${1#*"$TLB"}
	__tpl__match=${__tpl__match%%"$TRB"*}
	__tpl__match=${__tpl__match##*"$TLB"}
	__tpl__match=${__tpl__match#"${__tpl__match%%[!{]*}"}
	__tpl__is_quoted=
	__tpl__is_double_quoted=
	__tpl__is_expansion=
	case "$__tpl__match" in
	\'\$[_a-zA-Z]*\' | \'\$\(\(*\)\)\')
		__tpl__is_quoted=1
		__tpl__is_expansion=1
		;;
	\'*\') __tpl__is_quoted=1 ;;
	\$[_a-zA-Z]* | \$\(\(*\)\)) __tpl__is_expansion=1 ;;
	\"*\") __tpl__is_double_quoted=1 ;;
	esac
	__tpl__command=$__tpl__match
	if [ "$__tpl__is_quoted" ] || [ "$__tpl__is_double_quoted" ]; then
		__tpl__command=${__tpl__command#?}
		__tpl__command=${__tpl__command%?}
	fi
	if [ "$__tpl__is_expansion" ]; then
		case "${__tpl__command#"$"}" in
		\(\(*\)\)) __tpl__command="printf '%s' \"${__tpl__command}\"" ;; # Arithmetic Expansion
		*[!_a-zA-Z0-9]* | [!_a-zA-Z]*) __tpl__is_expansion= ;;           # Not a valid variable name
		*) __tpl__command="printf '%s' \"${__tpl__command}\"" ;;
		esac
	fi
	__tpl__tail=${1#*"$TLB"}
	__tpl__tail=${__tpl__tail#*"$TRB"}
	__tpl__head=${1%"${TLB}${__tpl__match}${TRB}${__tpl__tail}"}
	__tpl__head=${__tpl__head%\#}
	set --
	log_trace "[render] __tpl__head='${__tpl__head}' __tpl__match='${__tpl__match}' __tpl__tail='${__tpl__tail}'"
	printf '%s' "$__tpl__head" || return
	if [ "$__tpl__is_quoted" ]; then
		try eval "$__tpl__command" </dev/null | catch escape_single_quotes || return
	else
		(eval "$__tpl__command" </dev/null) || return
	fi
	__tpl__render_buffer="$__tpl__tail"
}

# Render templates expanding all expressions recursively, print result to stdout
# Accepts input from stdin and/or arguments, same UI as the cat utility
render() (
	for __tpl__filename in "$@"; do # Recursively render each file in arguments
		case "$__tpl__filename" in
		-) render || return ;; # Render stdin
		*) render <"$__tpl__filename" || return ;;
		esac
	done
	[ "$#" -eq 0 ] || return 0 # Only render from stdin when no arguments
	TLB=\{\{\{
	TRB=\}\}\}
	__tpl__render_buffer=
	__tpl__open_tags=
	__tpl__render_trailing_lf='
'
	while IFS= read -r __tpl__input_line || { __tpl__render_trailing_lf= && [ "$__tpl__input_line" ]; }; do
		__tpl__render_buffer="${__tpl__render_buffer}${__tpl__input_line}${__tpl__render_trailing_lf}" # Buffer one more line
		while :; do
			case "$__tpl__render_buffer" in
			*"$TLB"*"$TRB"*)
				log_debug "[render] buffered expression=$__tpl__render_buffer"
				__tpl__expand_leftmost_expression "$__tpl__render_buffer" || abort "[render] (error $?) Failed to render line: $__tpl__render_buffer"
				;;
			*"$TLB"*)
				log_trace "[render]   buffered open tag=$__tpl__render_buffer"
				__tpl__open_tags=1
				break
				;;
			*)
				log_trace "[render]      buffered flush=$__tpl__render_buffer"
				__tpl__open_tags=
				break
				;;
			esac
		done
		# log_trace "[render] __tpl__open_tags=${__tpl__open_tags}"
		if [ ! "$__tpl__open_tags" ]; then # Flush buffer only when all opened tags are closed
			printf '%s' "$__tpl__render_buffer" || abort "[render] (error $?) Failed to write output file"
			__tpl__render_buffer=
		fi
	done
	[ ! "$__tpl__open_tags" ] || printf '%s' "$__tpl__render_buffer" # Flush data left in the buffer if a tag was left open
)

while [ "$#" -gt 0 ]; do
	case "$1" in
	-C) { shift && cd "$1"; } || abort "Failed to cd into directory '-C $1'" ;;
	-e | --env) { shift && assign_variable "$1"; } || abort "Failed to assign context variable '--env $1'" ;;
	-s | --source) { shift && command . "$1"; } || abort "Failed to source file '--source $1'" ;;
	--help) __tpl__usage ;;
	--) shift && break ;;
	-?*) __tpl__usage 2 "Unknown option '$1'" ;;
	*) break ;;
	esac
	shift || __tpl__usage 2
done

render "$@"
