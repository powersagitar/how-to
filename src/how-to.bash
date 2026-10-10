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
