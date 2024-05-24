# template.sh

Process template from files or stdin and print the rendered text to stdout.

## Usage

```
template.sh 0.1.0-pre
Render templates and print result to stdout. Expressions within {{{ and }}} delimiters will be evaluated as shell script and substituted by their stdout in the rendered output. Context variables can be printed directly as {{{$VAR_NAME}}} or {{{'$VAR_NAME'}}} to escape the result for inclusion in single-quoted shell strings

Usage: template.sh [-C PATH]... [-s FILE]... [-e NAME=VALUE]... [-] [FILE...]

Options:
 -C PATH               Directory to operate in
 -e, --env NAME=VALUE  Set variable NAME=VALUE in render context
 -s, --source FILE     Source FILE to import its functions/variables in render context
 -h, --help            Print this help text and exit

Examples:
 template.sh -s ./program.context.sh program.template.sh >program.sh
 template.sh -e VERSION=1.0 -e TAG=latest program.template.sh >program.sh
```

### Example template file

```shell
# With the apostrophes, {{{'$VERSION'}}} will be escaped and can be safely included in single-quoted shell strings
VERSION='{{{'$VERSION'}}}'

# Any command can be executed, the expression will be substituted by the command's standard output
GIT_VERSION='{{{' git describe --tags --long --abbrev=40 '}}}'

# Both Parameter Expansion and Arithmetic Expansion have short forms, you don't need to printf the expansion to stdout
ANSWER={{{$((363636 / 13 / 666))}}}

# Another template file can be rendered and embedded anywhere in the result
{{{ render ./functions.template.sh }}}

# A "#" symbol preceding the expression delimiters will be removed from the result, allowing templates to be valid shell script as the delimiters will be commented out, for better integration with tools such as shellcheck and IDEs
#{{{
cat ./some/file
#}}}
```

### Functions available in render context

* `abort`, `log_error`, `log_debug`, `log_trace`: Logging functions (they print to stderr) (set `TEMPLATE_SH_DEBUG` to `1` or `trace` to see debug and trace messages)
* `cat [-] [file…]`: Simple POSIX-compatible cat utility in pure shell script
* `echo [args…]`: Portable echo that takes no options for consistent behavior across platforms
* `render [-] [file…]`: Render templates expanding all expressions recursively, print result to stdout. Accepts input from stdin and/or arguments, same UI as the cat utility

### Extra functions

Used internally by template.sh, but exposed publicly because they can be useful.

* `assign_variable NAME=VALUE`: Use indirection to dynamically assign a variable from argument NAME=VALUE
* `escape_single_quotes text`: Escape text for use in a shell script single-quoted string
* `substitute_characters text pattern [replacement] [pad=^]`: Substitute every instance of the pattern characters in text with replacement string. This function uses only shell builtins and has no external dependencies (f.e. on `sed`). This is slower than using `sed` on large inputs, but faster on many invocations with small inputs

## Dependencies

template.sh only needs a POSIX-compatible shell, there are no external dependencies for basic functioning, not even Unix core utilities.

## Contributing

Development of template.sh depends on shellcheck and shfmt. Every change must pass lint and formatting validation with `./make lint`. As an option, formatting can be automatically applied with `./make format`. Optionally, there's a development container image with all the tools required for development pre-installed, it can easily be used with [contr](https://codeberg.org/contr/contr):

```shell
# Build the development image
./make dev-image

# Enter the development container
contr template-sh-dev

# Analyze your changes for correctness
./make lint
```

It is a goal of this project to remain small, in the single-digit kilobytes range. While the code must be terse, it must also be readable and maintainable. Every ambiguous decision and potentially unexpected behavior must have its reasoning documented in accompanying code comments, preferably, and/or in this document, when appropriate.

## Similar projects

* [preproc](https://pagure.io/rpkg-util/blob/master/f/preproc) – Part of rpkg (unmaintained), works very similarly to template.sh, so much so that the option flags in template.sh were copied directly from its man page.

## License

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

See [UNLICENSE](UNLICENSE) file or http://unlicense.org/ for details.
