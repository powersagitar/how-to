# how-to: turn a plain-English request into a shell command on your prompt.
# usage: source /path/to/how-to.bash   (from ~/.bashrc; needs bash >= 4.4)

if ! (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  printf '%s\n' "how-to: requires bash >= 4.4 (this is $BASH_VERSION)" >&2
  return 1
fi

_how_to_version=0.3.0

# Reduce a model response (stdin) to the command: if it has a fenced block,
# keep only the inside of the first one (dedented by the fence's own indent);
# strip surrounding blank lines and trailing whitespace. Inner indentation is
# otherwise kept.
_how_to_clean() {
  local -
  local opts; opts=$(shopt -p nocasematch nullglob dotglob failglob extglob) || :
  shopt -u nocasematch
  local lines=() body=() l indent i start=-1
  mapfile -t lines
  for i in "${!lines[@]}"; do
    if [[ ${lines[i]} =~ ^([[:space:]]*)\`\`\` ]]; then
      start=$i indent=${BASH_REMATCH[1]}
      break
    fi
  done
  if (( start >= 0 )); then
    for l in "${lines[@]:start+1}"; do
      [[ $l =~ ^[[:space:]]*\`\`\` ]] && break
      body+=("${l#"$indent"}")
    done
    lines=("${body[@]}")
  fi
  for i in "${!lines[@]}"; do                  # trailing whitespace
    l=${lines[i]}
    lines[i]=${l%"${l##*[![:space:]]}"}
  done
  while (( ${#lines[@]} )) && [[ -z ${lines[0]} ]]; do lines=("${lines[@]:1}"); done
  while (( ${#lines[@]} )) && [[ -z ${lines[-1]} ]]; do unset 'lines[-1]'; done
  if (( ${#lines[@]} )); then
    l=${lines[0]}
    lines[0]=${l#"${l%%[![:space:]]*}"}
    printf '%s\n' "${lines[@]}"
  fi
  eval "$opts"
  return 0
}

# --- context -----------------------------------------------------------------
# Each name in HOW_TO_CONTEXT maps to _how_to_context_<name>, which prints
# zero or more "key: value" lines. Add your own by defining the function and
# appending its name.
declare -p HOW_TO_CONTEXT &>/dev/null || HOW_TO_CONTEXT=(os shell cwd git tools history)
declare -p HOW_TO_TOOLS &>/dev/null   || HOW_TO_TOOLS=(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)
# How many recent commands the history provider sends; 0 turns it off.
declare -p HOW_TO_HISTORY &>/dev/null || HOW_TO_HISTORY=5
# 0 turns the "thinking" indicator off.
declare -p HOW_TO_SPINNER &>/dev/null || HOW_TO_SPINNER=1

_how_to_context_os()    { local -; printf '%s\n' "os: $(command uname -sr)"; }
_how_to_context_shell() { local -; printf '%s\n' "shell: bash $BASH_VERSION"; }

# find, not a glob: bash can't glob without sorting, and a big directory
# would be read and sorted in full just to keep 30 names.
_how_to_context_cwd() {
  local -
  local IFS=$' \t\n' f files=()
  while (( ${#files[@]} < 30 )) && IFS= read -rd '' f; do
    files+=("${f#./}")
  done < <(command find . -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  printf '%s\n' "cwd: $PWD"
  (( ${#files[@]} )) && printf '%s\n' "files: ${files[*]:0:30}"
  return 0
}

_how_to_context_git() {
  local -
  local root branch
  root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 0
  printf '%s\n' "git_root: $root"
  # symbolic-ref works before the first commit; prints nothing when detached
  branch=$(command git symbolic-ref --short -q HEAD 2>/dev/null) || :
  [[ -n $branch ]] && printf '%s\n' "git_branch: $branch"
  return 0
}

_how_to_context_tools() {
  local -
  local IFS=$' \t\n' t list found=()
  read -ra list <<< "${HOW_TO_TOOLS[*]-}"
  for t in "${list[@]}"; do
    type -P "$t" >/dev/null && found+=("$t")
  done
  (( ${#found[@]} )) && printf '%s\n' "tools: ${found[*]}"
  return 0
}

# Exit statuses are not kept by the shell, so a PROMPT_COMMAND hook records
# them in step with history event numbers. The command text is read back from
# history when how-to runs. The text stored here only checks that an event
# number still holds the same command (history can be renumbered or reloaded).
# Event numbers come from the history listing, not HISTCMD: bash < 5.1 gives
# HISTCMD=1 inside PROMPT_COMMAND and $(...).
declare -p _how_to_hist_num &>/dev/null || _how_to_hist_num=()
declare -p _how_to_hist_rc &>/dev/null  || _how_to_hist_rc=()
declare -p _how_to_hist_txt &>/dev/null || _how_to_hist_txt=()

# _how_to_hist_add <event> <rc> <text>: append, or replace the last entry when
# it is the same event. Keeps the newest 100. No `local -` (see _how_to_record).
_how_to_hist_add() {
  local n=${#_how_to_hist_num[@]}
  if (( n )) && (( _how_to_hist_num[n-1] == $1 )); then
    _how_to_hist_rc[n-1]=$2
    _how_to_hist_txt[n-1]=${3-}
  else
    _how_to_hist_num+=("$1")
    _how_to_hist_rc+=("$2")
    _how_to_hist_txt+=("${3-}")
  fi
  if (( ${#_how_to_hist_num[@]} > 100 )); then
    _how_to_hist_num=("${_how_to_hist_num[@]: -100}")
    _how_to_hist_rc=("${_how_to_hist_rc[@]: -100}")
    _how_to_hist_txt=("${_how_to_hist_txt[@]: -100}")
  fi
  return 0
}

# The newest history entry as "<event> <text>"; non-zero if there is none.
# A listing, because inside PROMPT_COMMAND fc and history -p take the newest
# entry for their own command line and skip it.
_how_to_hist_last() {
  local -
  local l n
  l=$(HISTTIMEFORMAT= history 1) || return 1
  l=${l#"${l%%[! ]*}"}                        # "%5d%c %s": number, ' ' or '*',
  n=${l%%[!0-9]*}                             # a space, the text
  [[ -n $n ]] || return 1
  l=${l#"$n"}
  printf '%s %s\n' "$n" "${l#[* ] }"
}

# Command text of a history event; non-zero if it is gone. Not fc: in bash
# 5.1+, `fc -l N N` lists from the first entry when N is the newest entry
# before the current command. history -p deletes the newest entry when it is
# the current command line, so it runs in a subshell; histchars is reset so
# that "!N" is always an event.
_how_to_hist_text() (
  local -
  local histchars='!^#'
  history -p "!$1" 2>/dev/null
)

# _how_to_hist_lines <current_event>: the last HOW_TO_HISTORY recorded events
# below the current one, oldest first, as "history: [exit N] text".
_how_to_hist_lines() {
  local -
  local opts i text idx=() k=0
  opts=$(shopt -p nocasematch nullglob dotglob failglob extglob) || :
  shopt -u nocasematch
  [[ ${HOW_TO_HISTORY-} =~ ^[0-9]+$ ]] && (( 10#$HOW_TO_HISTORY > 0 )) && k=$(( 10#$HOW_TO_HISTORY ))
  for i in "${!_how_to_hist_num[@]}"; do
    (( k && _how_to_hist_num[i] < $1 )) && idx+=("$i")
  done
  (( ${#idx[@]} > k )) && idx=("${idx[@]: -k}")
  for i in "${idx[@]}"; do
    text=$(_how_to_hist_text "${_how_to_hist_num[i]}") || continue
    [[ -n $text && $text == "${_how_to_hist_txt[i]-}" ]] || continue
    text=${text//$'\n'/\\n}
    (( ${#text} > 500 )) && text="${text:0:500}…"
    printf '%s\n' "history: [exit ${_how_to_hist_rc[i]}] $text"
  done
  eval "$opts"
  return 0
}

# Every recorded event is at or below the newest entry, and the how-to line
# itself is not recorded until the next prompt.
_how_to_context_history() {
  local -
  local last
  last=$(_how_to_hist_last) || return 0
  _how_to_hist_lines "$(( ${last%% *} + 1 ))"
}

# PROMPT_COMMAND hook; returns the $? it saw. No `local -`: in bash < 5.1,
# returning from a function with it turns history back on for the rest of
# PROMPT_COMMAND, whose later lines are then saved as commands. Nothing here
# changes an option.
_how_to_record() {
  local rc=$?
  local IFS=$' \t\n' last= ev= text= pc=() c all n=${#_how_to_hist_num[@]}
  last=$(_how_to_hist_last) && ev=${last%% *} text=${last#* }
  # Something put in front of the hook may have changed $?: record nothing,
  # and move back to the front once. (Case folding under nocasematch can't
  # change these matches.) Before bash 5.1 only element 0 of an array runs,
  # so only element 0 counts; $PROMPT_COMMAND is element 0.
  c=${PROMPT_COMMAND[0]-}; c=${c%%[$'\n';]*}
  if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 501 )); then
    all=${PROMPT_COMMAND[*]-}
  else
    all=${PROMPT_COMMAND-}
  fi
  if [[ $all == *_how_to_record* && $c != _how_to_record ]]; then
    _how_to_hist_ready=1 _how_to_hist_seen=$ev
    [[ -v _how_to_hist_moved ]] && return "$rc"
    _how_to_hist_moved=1
    if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 501 )) &&
       [[ $(declare -p PROMPT_COMMAND) == 'declare -a'* ]]; then
      for c in "${PROMPT_COMMAND[@]}"; do
        [[ $c == _how_to_record ]] || pc+=("${c//_how_to_record/:}")
      done
      PROMPT_COMMAND=(_how_to_record "${pc[@]}")
    else
      # A string, or element 0 of an array: assigning to the plain name sets
      # element 0 and keeps the rest.
      PROMPT_COMMAND=_how_to_record$'\n'${PROMPT_COMMAND//_how_to_record/:}
    fi
    return "$rc"
  fi
  # The first prompt after sourcing: the newest entry is from HISTFILE or
  # before, and $? is whatever the rc file left.
  if [[ ! -v _how_to_hist_ready ]]; then
    _how_to_hist_ready=1 _how_to_hist_seen=$ev
    return "$rc"
  fi
  if [[ -n $ev && $ev != "${_how_to_hist_seen-}" ]]; then
    _how_to_hist_add "$ev" "$rc" "$text"
  elif [[ -n $ev ]] && (( n && _how_to_hist_num[n-1] == ev )) &&
       [ "${_how_to_hist_txt[n-1]}" != "$text" ]; then
    # Same number, new command: erasedups renumbered it onto this event.
    # (test, not [[ ]], so nocasematch can't fold case.)
    _how_to_hist_add "$ev" "$rc" "$text"
  fi
  _how_to_hist_seen=$ev
  return "$rc"
}

# Print the <context> block built from HOW_TO_CONTEXT. Missing or failing
# providers contribute nothing. A space-separated string works as well as an
# array.
_how_to_context() {
  local -
  local IFS=$' \t\n' name out list
  read -ra list <<< "${HOW_TO_CONTEXT[*]-}"
  printf '%s\n' '<context>'
  for name in "${list[@]}"; do
    declare -F "_how_to_context_$name" >/dev/null || continue
    out=$("_how_to_context_$name" 2>/dev/null) || continue
    [[ -n $out ]] && printf '%s\n' "$out"
  done
  printf '%s\n' '</context>'
}

# --- providers ---------------------------------------------------------------
# A provider is _how_to_provider_<name>: $1 = system prompt, stdin = user
# message, stdout = raw reply, non-zero exit on failure. Select one with
# HOW_TO_PROVIDER=<name>.
declare -p HOW_TO_SYSTEM_PROMPT &>/dev/null || HOW_TO_SYSTEM_PROMPT='You convert a request into a single shell command for the user'"'"'s environment
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
  local -
  local IFS=$' \t\n' args
  read -ra args <<< "${HOW_TO_CLAUDE_ARGS[*]:---model haiku}"
  command claude --print --tools "" --no-session-persistence \
    --system-prompt "$1" "${args[@]}"
}

# --- entry point -------------------------------------------------------------
# The how-to alias below runs `_how_to_pre && _how_to_run <request>`.
# _how_to_pre runs first, so its `set -f` is in effect when the request words
# are expanded. Being one && list, `cond && how-to ...` short-circuits as a
# whole, and an assignment in front (`HOW_TO_PROVIDER=x how-to ...`) reaches
# only _how_to_pre, which snapshots HOW_TO_* for _how_to_main to apply.
# Neither has `local -`: changing the caller's options is the point.
_how_to_pre() {
  _how_to_f=$-
  set -f
  _how_to_env=
  local names=("${!HOW_TO_@}")
  (( ${#names[@]} )) && _how_to_env=$(declare -p "${names[@]}")
  return 0
}

# `cond || how-to ...` skips _how_to_pre when cond succeeds; then do nothing.
_how_to_run() {
  [[ -v _how_to_f ]] || return 0
  _how_to_main "$@"
}

# --- thinking indicator -----------------------------------------------------
# One frame: \r<c> thinking <n>s\e[K, <c> from | / - \ by tick.
_how_to_spin_frame() {
  local -
  local chars='|/-\'
  printf '\r%s thinking %ds\e[K' "${chars:$1%4:1}" "$2"
}

_how_to_spin_on() {
  local -
  [[ ${HOW_TO_SPINNER-1} != 0 && ${TERM-} != dumb && -t 2 ]]
}

# stdin is a pipe nobody writes to: draw on each 0.1 s timeout, and leave
# without writing at EOF. SIGINT keeps its default action.
_how_to_spin() {
  local -
  _how_to_spin_on || return 0
  # SECONDS only ticks on whole wall-clock seconds; EPOCHREALTIME (bash 5+,
  # digits only, so a decimal comma doesn't matter) counts microseconds.
  local start tick=0 r
  if [[ -n ${EPOCHREALTIME-} ]]; then start=${EPOCHREALTIME//[!0-9]/}; else start=$SECONDS; fi
  while :; do
    IFS= read -r -t 0.1 _ && r=0 || r=$?
    (( r > 128 )) || return 0
    if [[ -n ${EPOCHREALTIME-} ]]; then
      _how_to_spin_frame "$tick" "$(( (${EPOCHREALTIME//[!0-9]/} - start) / 1000000 ))" >&2
    else
      _how_to_spin_frame "$tick" "$(( SECONDS - start ))" >&2
    fi
    tick=$(( tick + 1 ))
  done
}

_how_to_main() {
  # Through the alias: restore globbing before `local -`, so every return path
  # keeps it restored. Called directly, leave it as it is.
  local env=
  if [[ -v _how_to_f ]]; then
    [[ $_how_to_f == *f* ]] || set +f
    env=${_how_to_env-}
    unset _how_to_f _how_to_env
  fi
  local -
  local IFS=$' \t\n'
  _how_to_pending=
  # declare -p output; inside a function it declares locals for this call.
  eval "$env" 2>/dev/null || :
  # Option words are leading only. Case-sensitive whatever the user's nocasematch.
  local ver= po; po=$(shopt -p nocasematch) || :
  shopt -u nocasematch
  while (( $# )); do
    case $1 in
      -v|--version) ver=1; shift ;;
      --) shift; break ;;
      -?*)
        eval "$po"
        printf '%s\n' "how-to: unknown option '$1'" 'usage: how-to [-v | --version] [--] <what you want to do>' >&2
        return 2 ;;
      *) break ;;
    esac
  done
  eval "$po"
  if [[ -n $ver ]]; then
    printf '%s\n' "how-to $_how_to_version"
    return 0
  fi
  if (( ! $# )); then
    printf '%s\n' 'usage: how-to [-v | --version] [--] <what you want to do>' >&2
    return 2
  fi
  local name=${HOW_TO_PROVIDER:-claude}
  local fn=_how_to_provider_$name
  if ! declare -F "$fn" >/dev/null; then
    printf '%s\n' "how-to: unknown provider '$name'" >&2
    return 1
  fi

  local msg raw cmd l fail found= rc bg
  msg="$(_how_to_context)"$'\n'"Request: $*"
  # Wait for the spinner only if the substitution set $! (else $! may be a
  # job of the user's, which could run for a long time). ${#!}, not ${!-}:
  # under set -u, bash 4.4 rejects every ${!...} default form while $! is unset.
  bg=; (( ${#!} )) && bg=$!
  { raw=$(printf '%s\n' "$msg" | "$fn" "$HOW_TO_SYSTEM_PROMPT" 3>&-) && rc=0 || rc=$?; } 3> >(_how_to_spin)
  (( ${#!} )) && [[ $! != "$bg" ]] && wait "$!" 2>/dev/null || :
  _how_to_spin_on && printf '\r\e[K' >&2
  if (( rc )); then
    printf '%s\n' 'how-to: provider failed' >&2
    return 1
  fi
  cmd=$(printf '%s\n' "$raw" | _how_to_clean)
  if [[ -z $cmd ]]; then
    printf '%s\n' 'how-to: no command returned' >&2
    return 1
  fi
  local opts; opts=$(shopt -p nocasematch nullglob dotglob failglob extglob) || :
  shopt -u nocasematch
  while IFS= read -r l; do
    if [[ $l == HOWTO_FAIL:* ]]; then
      fail=${l#HOWTO_FAIL:} found=1
      break
    fi
  done <<< "$cmd"
  eval "$opts"
  if [[ -n $found ]]; then
    printf '%s\n' "${fail# }" >&2
    return 1
  fi
  _how_to_push "$cmd"
}

# --- putting the command on the prompt ---------------------------------------
# bash has no `print -z`. Instead, ask the terminal for a Device Status Report
# (\e[5n). Its reply (\e[0n) waits in the tty's input until readline reads the
# next prompt, where it is bound to _how_to_insert. Echo is off while the reply
# arrives (else it shows as ^[[0n) and canonical mode is off so `read -t 0`
# can see it. No reply within 1 s, or no terminal: print the command instead.
# Input already waiting before the query is typeahead, not the reply, and
# reading it would take it from readline: skip the query and print.
# A terminal that stays silent for the whole wait probably doesn't answer;
# remember when (_how_to_no_dsr) and print without asking for the next 10
# minutes, so a key pressed during a later wait can't be mistaken for the
# reply. A slow terminal's reply still reaches _how_to_insert at the next
# prompt, which forgets the silence.
# The wait runs in a subshell whose EXIT trap restores the tty, so Ctrl-C
# can't leave it in -echo -icanon.
_how_to_pending=
_how_to_push() {
  local -
  local saved rc=0
  if [[ $- == *i* ]] &&
     { [[ -z ${_how_to_no_dsr-} ]] || (( SECONDS - _how_to_no_dsr >= 600 )); } &&
     saved=$(command stty -g </dev/tty 2>/dev/null); then
    _how_to_pending=$1
    (
      trap 'command stty "$saved" </dev/tty' EXIT
      trap 'exit 130' INT
      command stty -echo -icanon </dev/tty
      read -t 0 </dev/tty && exit 1
      printf '\e[5n' >/dev/tty
      for (( i = 0; i < 100; i++ )); do
        read -t 0 </dev/tty && exit 0
        command sleep 0.01
      done
      exit 2
    ) || rc=$?
    (( rc == 0 )) && return 0
    (( rc == 2 )) && _how_to_no_dsr=$SECONDS
    _how_to_pending=
    (( rc == 130 )) && return 130
  fi
  printf '%s\n' "$1"
}

# Called for every \e[0n, including a reply that came too late for its call:
# either way the terminal answers.
_how_to_insert() {
  local -
  unset _how_to_no_dsr
  [[ -n $_how_to_pending ]] || return 0
  READLINE_LINE=$_how_to_pending
  READLINE_POINT=${#READLINE_LINE}
  _how_to_pending=
}

# A request word that fails to expand (e.g. $1 under set -u) aborts the line
# after the alias's `set -f` but before _how_to_main can undo it. Undo it at
# the next prompt instead. No `local -`: changing the caller's options is the
# point.
_how_to_restore_glob() {
  local rc=$?
  if [[ -v _how_to_f ]]; then
    [[ $_how_to_f == *f* ]] || set +f
    unset _how_to_f _how_to_env
  fi
  return "$rc"
}

# _how_to_record goes first, to see the command's $? before other hooks change
# it; _how_to_restore_glob goes last. Before bash 5.1 only element 0 of an
# array PROMPT_COMMAND runs, so there it is treated as a string: assigning to
# the plain name sets element 0 and keeps the rest.
unset _how_to_hist_ready _how_to_hist_moved
if [[ $- == *i* ]]; then
  bind -m emacs -x '"\e[0n": _how_to_insert' 2>/dev/null
  bind -m vi-insert -x '"\e[0n": _how_to_insert' 2>/dev/null
  if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 501 )) &&
     [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
    [[ " ${PROMPT_COMMAND[*]} " == *' _how_to_record '* ]] ||
      PROMPT_COMMAND=(_how_to_record "${PROMPT_COMMAND[@]}")
    [[ " ${PROMPT_COMMAND[*]} " == *' _how_to_restore_glob '* ]] ||
      PROMPT_COMMAND+=(_how_to_restore_glob)
  else
    [[ ${PROMPT_COMMAND-} == *_how_to_record* ]] ||
      PROMPT_COMMAND=_how_to_record${PROMPT_COMMAND:+$'\n'$PROMPT_COMMAND}
    [[ $PROMPT_COMMAND == *_how_to_restore_glob* ]] ||
      PROMPT_COMMAND=$PROMPT_COMMAND$'\n'_how_to_restore_glob
  fi
fi

# Keep globs like *.log in the request from being expanded by the shell.
# Defined last, so no `how-to` above is alias-expanded.
alias how-to='_how_to_pre && _how_to_run'
