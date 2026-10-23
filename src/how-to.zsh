# how-to: turn a plain-English request into a shell command on your prompt.
# usage: source /path/to/how-to.zsh   (from ~/.zshrc)

# Reduce a model response (stdin) to the command: if it has a fenced block,
# keep only the inside of the first one (dedented by the fence's own indent);
# strip surrounding blank lines and trailing whitespace. Inner indentation is
# otherwise kept.
_how_to_clean() {
  emulate -L zsh -o extendedglob
  local -a lines
  lines=("${(@f)$(<&0)}")
  integer i=${lines[(i)[[:space:]]#\`\`\`*]}
  if (( i <= $#lines )); then
    local indent=${(M)lines[i]##[[:space:]]#}
    lines=("${(@)lines[i+1,-1]}")
    i=${lines[(i)[[:space:]]#\`\`\`*]}
    lines=("${(@)${(@)lines[1,i-1]}#$indent}")
  fi
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
(( ${+HOW_TO_CONTEXT} )) || typeset -ga HOW_TO_CONTEXT=(os shell cwd git tools history)
(( ${+HOW_TO_TOOLS} ))   || typeset -ga HOW_TO_TOOLS=(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)
# How many recent commands the history provider sends; 0 turns it off.
(( ${+HOW_TO_HISTORY} )) || typeset -g HOW_TO_HISTORY=5
# 0 turns the "thinking" indicator off.
(( ${+HOW_TO_SPINNER} )) || typeset -g HOW_TO_SPINNER=1

_how_to_context_os()    { emulate -L zsh; print -r -- "os: $(command uname -sr)" }
_how_to_context_shell() { emulate -L zsh; print -r -- "shell: zsh $ZSH_VERSION" }

_how_to_context_cwd() {
  emulate -L zsh
  local -a files=(*(DNoN[1,30]:t))   # oN: skip sorting big dirs
  print -r -- "cwd: $PWD"
  (( $#files )) && print -r -- "files: ${files[*]}"
  return 0
}

_how_to_context_git() {
  emulate -L zsh
  local root branch
  root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 0
  print -r -- "git_root: $root"
  # symbolic-ref works before the first commit; prints nothing when detached
  branch=$(command git symbolic-ref --short -q HEAD 2>/dev/null)
  [[ -n $branch ]] && print -r -- "git_branch: $branch"
  return 0
}

_how_to_context_tools() {
  emulate -L zsh
  local t; local -a found
  for t in ${=HOW_TO_TOOLS}; (( $+commands[$t] )) && found+=($t)
  (( $#found )) && print -r -- "tools: ${found[*]}"
  return 0
}

# Exit statuses are not kept by the shell, so a precmd hook records them in
# step with history event numbers. The command text is read back from history
# when how-to runs. The text stored here only checks that an event number
# still holds the same command (history can be renumbered or reloaded).
(( ${+_how_to_hist_num} )) || typeset -ga _how_to_hist_num=()
(( ${+_how_to_hist_rc} ))  || typeset -ga _how_to_hist_rc=()
(( ${+_how_to_hist_txt} )) || typeset -ga _how_to_hist_txt=()

# _how_to_hist_add <event> <rc> <text>: append, or replace the last entry when
# it is the same event. Keeps the newest 100.
_how_to_hist_add() {
  emulate -L zsh
  if (( $#_how_to_hist_num && _how_to_hist_num[-1] == $1 )); then
    _how_to_hist_rc[-1]=$2
    _how_to_hist_txt[-1]=$3
  else
    _how_to_hist_num+=($1)
    _how_to_hist_rc+=($2)
    _how_to_hist_txt+=("$3")
  fi
  if (( $#_how_to_hist_num > 100 )); then
    _how_to_hist_num=(${_how_to_hist_num[-100,-1]})
    _how_to_hist_rc=(${_how_to_hist_rc[-100,-1]})
    _how_to_hist_txt=("${(@)_how_to_hist_txt[-100,-1]}")
  fi
  return 0
}

# Command text of a history event; non-zero if it is gone.
_how_to_hist_text() { emulate -L zsh; fc -ln $1 $1 2>/dev/null }

# _how_to_hist_lines <current_event>: the last HOW_TO_HISTORY recorded events
# below the current one, oldest first, as "history: [exit N] text".
_how_to_hist_lines() {
  emulate -L zsh
  [[ $HOW_TO_HISTORY == <1-> ]] || return 0
  local -a idx
  local i text
  for (( i = 1; i <= $#_how_to_hist_num; i++ )); do
    (( _how_to_hist_num[i] < $1 )) && idx+=($i)
  done
  (( $#idx > HOW_TO_HISTORY )) && idx=(${idx[-$HOW_TO_HISTORY,-1]})
  for i in $idx; do
    text=$(_how_to_hist_text ${_how_to_hist_num[i]}) || continue
    [[ -n $text && $text == ${_how_to_hist_txt[i]} ]] || continue
    text=${text//$'\n'/\\n}
    (( ${#text} > 500 )) && text="${text[1,500]}…"
    print -r -- "history: [exit ${_how_to_hist_rc[i]}] $text"
  done
}

_how_to_context_history() { emulate -L zsh; _how_to_hist_lines $HISTCMD }

# preexec hook: a command ran, so the next prompt has a status to record.
# (Ctrl-C or an empty Enter at a prompt runs precmd without a command.)
_how_to_hist_ran() { emulate -L zsh; typeset -g _how_to_hist_flag=1 }

# precmd hook. $? must be read first: emulate would reset it to 0.
_how_to_record() {
  local rc=$?
  emulate -L zsh
  if (( ! ${+_how_to_hist_ready} )); then
    typeset -g _how_to_hist_ready=1
    unset _how_to_hist_flag
    return 0
  fi
  (( ${+_how_to_hist_flag} )) || return 0
  unset _how_to_hist_flag
  local ev=$(( HISTCMD - 1 ))
  _how_to_hist_add $ev $rc "$(_how_to_hist_text $ev)"
}

# Print the <context> block built from HOW_TO_CONTEXT. Missing or failing
# providers contribute nothing. A space-separated string works as well as an
# array.
_how_to_context() {
  emulate -L zsh
  local name out
  print -r -- '<context>'
  for name in ${=HOW_TO_CONTEXT}; do
    (( $+functions[_how_to_context_$name] )) || continue
    out=$(_how_to_context_$name 2>/dev/null) || continue
    [[ -n $out ]] && print -r -- "$out"
  done
  print -r -- '</context>'
}

# --- providers ---------------------------------------------------------------
# A provider is _how_to_provider_<name>: $1 = system prompt, stdin = user
# message, stdout = raw reply, non-zero exit on failure. Select one with
# HOW_TO_PROVIDER=<name>.
(( ${+HOW_TO_SYSTEM_PROMPT} )) || HOW_TO_SYSTEM_PROMPT='You convert a request into a single shell command for the user'"'"'s environment
described in <context>.
Output ONLY the command: no explanation, no markdown, no code fences.
Prefer tools listed in "tools:" when they fit; otherwise use standard POSIX/
OS-native utilities.
"history:" lines are the user'"'"'s latest commands, oldest first; "that"/"it" usually means the last one.
Use a single line; chain with && or | when needed.
Do not refuse destructive commands; the user reviews before running.
If the request cannot be done with a shell command, output exactly:
HOWTO_FAIL: <short reason>'

_how_to_provider_claude() {
  command claude --print --tools "" --no-session-persistence \
    --system-prompt "$1" ${=HOW_TO_CLAUDE_ARGS:---model haiku}
}

# --- entry point -------------------------------------------------------------
_how_to_push() { print -rz -- "$1" }

# --- thinking indicator -----------------------------------------------------
# One frame: \r<c> thinking <n>s\e[K, <c> from | / - \ by tick, <n> truncated.
_how_to_spin_frame() {
  emulate -L zsh
  integer s=$2
  local chars='|/-\'
  printf '\r%s thinking %ds\e[K' ${chars[$1 % 4 + 1]} $s
}

_how_to_spin_on() {
  emulate -L zsh
  [[ ${HOW_TO_SPINNER-1} != 0 && ${TERM-} != dumb && -t 2 ]]
}

# stdin is a pipe nobody writes to: draw on each 0.1 s timeout, and leave
# without writing at EOF. SIGINT keeps its default action.
_how_to_spin() {
  emulate -L zsh
  _how_to_spin_on || return 0
  zmodload zsh/system || return 0
  # Count from 0 here: the shell's SECONDS ticks a whole second after it
  # started, not after this call did. integer undoes a user's typeset -F.
  integer SECONDS=0 tick=0
  local buf
  while :; do
    sysread -t 0.1 buf
    (( $? == 4 )) || return 0
    _how_to_spin_frame $tick $SECONDS >&2
    (( tick++ ))
  done
}

function how-to {
  emulate -L zsh
  if (( ! $# )); then
    print -u2 'usage: how-to <what you want to do>'
    return 2
  fi
  local name=${HOW_TO_PROVIDER:-claude}
  local fn=_how_to_provider_$name
  if (( ! $+functions[$fn] )); then
    print -u2 -r -- "how-to: unknown provider '$name'"
    return 1
  fi

  local msg raw cmd rc
  msg="$(_how_to_context)"$'\n'"Request: $*"
  { raw=$(print -r -- "$msg" | $fn "$HOW_TO_SYSTEM_PROMPT" 3>&-); rc=$? } 3> >(_how_to_spin)
  _how_to_spin_on && print -rnu2 -- $'\r\e[K'
  if (( rc )); then
    print -u2 'how-to: provider failed'
    return 1
  fi
  cmd=$(print -r -- "$raw" | _how_to_clean)
  if [[ -z $cmd ]]; then
    print -u2 'how-to: no command returned'
    return 1
  fi
  local -a fail=(${(M)${(f)cmd}:#HOWTO_FAIL:*})
  if (( $#fail )); then
    print -u2 -r -- "${${fail[1]#HOWTO_FAIL:}# }"
    return 1
  fi
  _how_to_push "$cmd"
}

# Record exit statuses for the history context (interactive shells only).
unset _how_to_hist_ready _how_to_hist_flag
if [[ -o interactive ]]; then
  autoload -Uz add-zsh-hook && add-zsh-hook precmd _how_to_record
  add-zsh-hook preexec _how_to_hist_ran
fi

# Keep globs like *.log in the request from being expanded by the shell.
alias how-to='noglob how-to'
