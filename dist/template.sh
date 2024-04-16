#!/bin/sh
# SPDX-License-Identifier: Unlicense
# shellcheck disable=1090
__tpl__usage() {
	fd=${1:+2}
	cat <<'EOF' >&"${fd:-1}"
template.sh 0.1.0-pre
Render templates and print result to stdout. Expressions within {{{ and }}} delimiters will be evaluated as shell script and substituted by their stdout in the rendered output. Context variables can be printed directly as {{{$VAR_NAME}}} or {{{'$VAR_NAME'}}} to escape the result for inclusion in single-quoted shell strings

Usage: template.sh [-C PATH]... [-s FILE]... [-e NAME=VALUE]... [-] [FILE...]

Options:
 -C PATH               Directory to operate in
 -e, --env NAME=VALUE  Set variable NAME=VALUE in render context
 -s, --source FILE     Source FILE to import its functions/variables in render context
 -h, --help            Print this help text and exit

Examples:
 template.sh -s program.sh.context program.sh.template >program.sh
 template.sh -e VERSION=1.0 -e TAG=latest program.sh.template >program.sh
EOF
	exit ${1:+"$1"}
}

echo() (IFS=' ' && printf '%s\n' "$*")
log_error() (IFS=' ' && printf 'ERROR [template.sh] %s\n' "$*" >&2)
log_debug() { :; } && [ "$TEMPLATE_SH_DEBUG" ] && log_debug() (IFS=' ' && printf 'DEBUG [template.sh] %s\n' "$*" >&2)
log_trace() { :; } && case "$TEMPLATE_SH_DEBUG" in *trace*) log_trace() (IFS=' ' && printf 'TRACE [template.sh] %s\n' "$*" >&2) ;; esac
abort() {
	log_error "$1"
	exit "${2:-1}"
}

# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cat.html
# Simple POSIX-compatible cat utility in pure shell script
# shellcheck disable=2120
cat() (
	for filename in "$@"; do # Recursively print each file in arguments
		case "$filename" in
		-u) ;;    # Ignore unused flag
		-) cat ;; # Print stdin
		*) cat <"$filename" ;;
		esac
	done
	[ "$#" -eq 0 ] || return 0 # Only print from stdin when no arguments
	while IFS= read -r line || [ "$line" ]; do printf '%s\n' "$line"; done
)

# Substitute every instance of character in text with replacement string
# This function uses only shell builtins and has no external dependencies (f.e. on sed)
# This is slower than using sed on a big input, but faster on many invocations with small inputs
substitute_character_builtin() (
	set -f # Disable Pathname Expansion (aka globbing)
	IFS="$1"
	trailing_match=
	case "$3" in *"$1") [ "$ZSH_VERSION" ] || trailing_match="$2" ;; esac
	last_field=
	first=1
	for field in $3; do
		[ "$first" ] || printf '%s%s' "$last_field" "$2"
		last_field="$field"
		first=
	done
	printf '%s%s' "$last_field" "$trailing_match"
)

# Escape text for use in a shell script single-quoted string (shell builtin version)
escape_single_quotes_builtin() { substitute_character_builtin \' "'\\''" "$1"; }

# Use indirection to dynamically assign a variable from argument NAME=VALUE
assign_variable() {
	case "${1%%=*}" in *[!_a-zA-Z0-9]* | [!_a-zA-Z]*) return 1 ;; esac
	eval "${1%%=*}='$(escape_single_quotes_builtin "${1#*=}")'"
}

__tpl__expand_leftmost_expression() {
	__tpl__match=${1#*'{{{'}
	__tpl__match=${__tpl__match%%'}}}'*}
	__tpl__match=${__tpl__match##*'{{{'}
	while :; do
		case "$__tpl__match" in
		\{*) __tpl__match=${__tpl__match#'{'} ;;
		*) break ;;
		esac
	done
	__tpl__is_quoted=
	__tpl__is_expansion=
	__tpl__is_parameter_expansion=
	case "$__tpl__match" in
	\'\$[_a-zA-Z]*\' | \'\$\(\(*\)\)\')
		__tpl__is_quoted=1
		__tpl__is_expansion=1
		;;
	\'*\') __tpl__is_quoted=1 ;;
	\$[_a-zA-Z]* | \$\(\(*\)\)) __tpl__is_expansion=1 ;;
	esac
	__tpl__command=$__tpl__match
	if [ "$__tpl__is_quoted" ]; then
		__tpl__command=${__tpl__command#?}
		__tpl__command=${__tpl__command%?}
	fi
	__tpl__parameter_expansion=
	if [ "$__tpl__is_expansion" ]; then
		case "${__tpl__command#"$"}" in
		\(\(*\)\)) __tpl__command="printf '%s' \"${__tpl__command}\"" ;; # Arithmetic Expansion
		*[!_a-zA-Z0-9]* | [!_a-zA-Z]*) __tpl__is_expansion= ;;           # Not a valid variable name
		*)
			__tpl__is_parameter_expansion=1
			eval "__tpl__parameter_expansion=$__tpl__command"
			__tpl__command="printf '%s' \"${__tpl__command}\""
			;;
		esac
	fi
	__tpl__tail=${1#*'{{{'}
	__tpl__tail=${__tpl__tail#*'}}}'}
	__tpl__head=${1%"{{{${__tpl__match}}}}${__tpl__tail}"}
	set --
	log_trace "__tpl__head='${__tpl__head}' __tpl__match='${__tpl__match}' __tpl__tail='${__tpl__tail}'"
	printf '%s' "$__tpl__head" || return 1
	if [ "$__tpl__is_quoted" ]; then
		if [ "$__tpl__is_parameter_expansion" ]; then
			escape_single_quotes_builtin "$__tpl__parameter_expansion" || return 1
		else
			# FIXME: Command Substitution truncates trailing whitespace
			# It is hard to avoid Command Substitution in this case. It might require using a temporary file, which
			# introduces risk of races and loss of data because this function is called recursively
			__tpl__parameter_expansion=$(eval "$__tpl__command" </dev/null) || return 1
			escape_single_quotes_builtin "$__tpl__parameter_expansion" || return 1
		fi
	else
		(eval "$__tpl__command" </dev/null) || return 1
	fi
	__tpl__render_buffer="$__tpl__tail"
}

# Render templates expanding all expressions recursively, print result to stdout
# Accepts input from stdin and/or arguments, same UI as the cat utility
render() (
	for __tpl__filename in "$@"; do # Recursively render each file in arguments
		case "$__tpl__filename" in
		-) render ;; # Render stdin
		*) render <"$__tpl__filename" ;;
		esac
	done
	[ "$#" -eq 0 ] || return 0 # Only render from stdin when no arguments
	unset __tpl__render_buffer
	__tpl__open_tags=
	while IFS= read -r __tpl__input_line || [ "$__tpl__input_line" ]; do
		__tpl__render_buffer="${__tpl__render_buffer+"${__tpl__render_buffer}
"}${__tpl__input_line}" # Buffer one more line
		while :; do
			case "$__tpl__render_buffer" in
			*'{{{'*'}}}'*)
				log_debug "buffered expression=$__tpl__render_buffer"
				__tpl__expand_leftmost_expression "$__tpl__render_buffer" || abort "Failed to render line='$__tpl__render_buffer'"
				log_debug " buffered remainder=$__tpl__render_buffer"
				;;
			*'{{{'*)
				log_trace "  buffered open tag=$__tpl__render_buffer"
				__tpl__open_tags=1
				break
				;;
			*)
				log_trace "     buffered flush=$__tpl__render_buffer"
				__tpl__open_tags=
				break
				;;
			esac
		done
		log_trace "__tpl__open_tags=${__tpl__open_tags}"
		if [ ! "$__tpl__open_tags" ]; then # Flush buffer only when all opened tags are closed
			printf '%s\n' "$__tpl__render_buffer"
			unset __tpl__render_buffer
		fi
	done
	[ ! "$__tpl__open_tags" ] || printf '%s\n' "$__tpl__render_buffer" # Flush data left in the buffer if a tag was left open
)

set -f # Disable Pathname Expansion (aka globbing)
IFS=
while [ "$#" -gt 0 ]; do
	case "$1" in
	-C) { shift && cd "$1"; } || abort "Failed to cd into directory '$1'" ;;
	-e | --env) { shift && assign_variable "$1"; } || abort "Failed to assign context variable '$1'" ;;
	-s | --source) { shift && . "$1" && set -f && IFS=; } || abort "Failed to source file '$1'" ;;
	-h | --help) __tpl__usage ;;
	--) shift && break ;;
	*) break ;;
	esac
	shift || __tpl__usage 1
done

render "$@"
