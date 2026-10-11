# how-to: turn a plain-English request into a shell command on your prompt.
# usage: source /path/to/how-to.bash   (from ~/.bashrc; needs bash >= 4.4)

if ! (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  printf '%s\n' "how-to: requires bash >= 4.4 (this is $BASH_VERSION)" >&2
  return 1
fi

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
declare -p HOW_TO_CONTEXT &>/dev/null || HOW_TO_CONTEXT=(os shell cwd git tools)
declare -p HOW_TO_TOOLS &>/dev/null   || HOW_TO_TOOLS=(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)
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
  if (( ! $# )); then
    printf '%s\n' 'usage: how-to <what you want to do>' >&2
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

if [[ $- == *i* ]]; then
  bind -m emacs -x '"\e[0n": _how_to_insert' 2>/dev/null
  bind -m vi-insert -x '"\e[0n": _how_to_insert' 2>/dev/null
  if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
    [[ " ${PROMPT_COMMAND[*]} " == *' _how_to_restore_glob '* ]] ||
      PROMPT_COMMAND+=(_how_to_restore_glob)
  elif [[ ${PROMPT_COMMAND-} != *_how_to_restore_glob* ]]; then
    PROMPT_COMMAND=${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}_how_to_restore_glob
  fi
fi

# Keep globs like *.log in the request from being expanded by the shell.
# Defined last, so no `how-to` above is alias-expanded.
alias how-to='_how_to_pre && _how_to_run'
