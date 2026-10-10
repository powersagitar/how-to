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
