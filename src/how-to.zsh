# how-to: turn a plain-English request into a shell command on your prompt.
# usage: source /path/to/how-to.zsh   (from ~/.zshrc)

# Strip code fences, surrounding blank lines and trailing whitespace from a
# model response (stdin). Inner indentation is kept.
_how_to_clean() {
  setopt localoptions extendedglob
  local -a lines
  lines=("${(@f)$(<&0)}")
  lines=("${(@)lines:#\`\`\`*}")              # drop fence lines
  lines=("${(@)lines%%[[:space:]]##}")         # trailing whitespace
  while (( $#lines )) && [[ -z ${lines[1]} ]]; do shift lines; done
  while (( $#lines )) && [[ -z ${lines[-1]} ]]; do lines[-1]=(); done
  (( $#lines )) || return 0
  lines[1]=${lines[1]##[[:space:]]##}
  print -r -- ${(F)lines}
}

# --- context -----------------------------------------------------------------
# Each name in HOW_TO_CONTEXT maps to _how_to_context_<name>, which prints
# zero or more "key: value" lines. Add your own by defining the function and
# appending its name.
(( ${+HOW_TO_CONTEXT} )) || typeset -ga HOW_TO_CONTEXT=(os shell cwd git tools)
(( ${+HOW_TO_TOOLS} ))   || typeset -ga HOW_TO_TOOLS=(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)

_how_to_context_os()    { print -r -- "os: $(uname -sr)" }
_how_to_context_shell() { print -r -- "shell: zsh $ZSH_VERSION" }

_how_to_context_cwd() {
  local -a files=(*(DN[1,30]:t))
  print -r -- "cwd: $PWD"
  (( $#files )) && print -r -- "files: ${files[*]}"
  return 0
}

_how_to_context_git() {
  local -a info=("${(@f)$(git rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null)}")
  [[ -n ${info[1]} ]] || return 0
  print -r -- "git_root: ${info[1]}"
  [[ -n ${info[2]} ]] && print -r -- "git_branch: ${info[2]}"
  return 0
}

_how_to_context_tools() {
  local t; local -a found
  for t in $HOW_TO_TOOLS; (( $+commands[$t] )) && found+=($t)
  (( $#found )) && print -r -- "tools: ${found[*]}"
  return 0
}

# Print the <context> block built from HOW_TO_CONTEXT. Missing or failing
# providers contribute nothing.
_how_to_context() {
  local name out
  print -r -- '<context>'
  for name in $HOW_TO_CONTEXT; do
    (( $+functions[_how_to_context_$name] )) || continue
    out=$(_how_to_context_$name 2>/dev/null) || continue
    [[ -n $out ]] && print -r -- "$out"
  done
  print -r -- '</context>'
}
