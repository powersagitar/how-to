#!/usr/bin/env bash
# Tests for how-to.bash. Run: bash src/test.bash   (bash >= 4.4)
if ! (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  echo 'test.bash: requires bash >= 4.4' >&2
  exit 2
fi
here=$(cd "${BASH_SOURCE%/*}" && pwd)
source "$here/how-to.bash"

failures=0
assert_eq() {
  if [[ $2 == "$3" ]]; then
    printf '%s\n' "ok   $1"
  else
    printf '%s\n' "FAIL $1" "  expected: ${2@Q}" "  actual:   ${3@Q}"
    (( failures++ ))
  fi
}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# --- _how_to_clean
assert_eq "clean: fence"        'ls -la'        "$(printf '%s\n' $'```\nls -la\n```' | _how_to_clean)"
assert_eq "clean: fence+lang"   'ls -la'        "$(printf '%s\n' $'```bash\nls -la\n```' | _how_to_clean)"
assert_eq "clean: blank lines"  'ls'            "$(printf '%s\n' $'\n\n  \nls\n\n' | _how_to_clean)"
assert_eq "clean: trailing ws"  'ls -a'         "$(printf '%s\n' $'ls -a   \t' | _how_to_clean)"
assert_eq "clean: multi-line"   $'a \\\n  && b' "$(printf '%s\n' $'a \\\n  && b' | _how_to_clean)"
assert_eq "clean: leading ws trimmed on first line" 'ls' "$(printf '%s\n' '   ls' | _how_to_clean)"
assert_eq "clean: prose around fence" 'fd -e log' \
  "$(printf '%s\n' $'Here is the command:\n```bash\nfd -e log\n```\nThis finds logs.' | _how_to_clean)"
assert_eq "clean: indented fence" 'ls -la' "$(printf '%s\n' $'  ```bash\n  ls -la\n  ```' | _how_to_clean)"
assert_eq "clean: indented fence dedents" $'a \\\n  && b' \
  "$(printf '%s\n' $'Run:\n   ```\n   a \\\n     && b\n   ```' | _how_to_clean)"

# --- config
assert_eq "ctx: default list" 'os shell cwd git tools' "${HOW_TO_CONTEXT[*]}"
assert_eq "ctx: preset kept" 'os' "$(HOW_TO_CONTEXT=(os); source "$here/how-to.bash"; echo "${HOW_TO_CONTEXT[*]}")"
assert_eq "ctx: empty preset kept" 0 "$(HOW_TO_CONTEXT=(); source "$here/how-to.bash"; echo "${#HOW_TO_CONTEXT[@]}")"
if type -P zsh >/dev/null; then
  assert_eq "prompt: matches zsh" "$(zsh -c 'source '"$here"'/how-to.zsh; print -rn -- $HOW_TO_SYSTEM_PROMPT')" \
    "$HOW_TO_SYSTEM_PROMPT"
else
  echo 'skip prompt: matches zsh (no zsh)'
fi
if [[ -x /bin/bash ]] && (( $(/bin/bash -c 'echo ${BASH_VERSINFO[0]}') < 4 )); then
  assert_eq "old bash refused" "how-to: requires bash >= 4.4 (this is $(/bin/bash -c 'echo $BASH_VERSION'))" \
    "$(/bin/bash -c "source '$here/how-to.bash' 2>&1 >/dev/null; type _how_to_clean >/dev/null 2>&1 && echo DEFINED")"
else
  echo 'skip old bash refused (/bin/bash is not < 4)'
fi

# --- context assembly
ctx_defs() {
  _how_to_context_a() { echo 'a: 1'; }
  _how_to_context_b() { echo 'b: 2'; }
  _how_to_context_bad() { echo boom >&2; return 1; }
}
assert_eq "ctx: order+skip" $'<context>\na: 1\nb: 2\n</context>' "$(
  ctx_defs; HOW_TO_CONTEXT=(a missing bad b); _how_to_context 2>&1)"
assert_eq "ctx: scalar list split" $'<context>\na: 1\nb: 2\n</context>' "$(
  ctx_defs; unset HOW_TO_CONTEXT; HOW_TO_CONTEXT='a b'; _how_to_context 2>&1)"
assert_eq "ctx: hostile opts" $'<context>\na: 1\nb: 2\n</context>' "$(
  set -euo pipefail; shopt -s failglob nocasematch nullglob; IFS=:
  ctx_defs; HOW_TO_CONTEXT=(a missing bad b); _how_to_context 2>&1)"

# --- built-in context providers
mkdir "$tmp/a dir"; for i in {1..40}; do touch "$tmp/a dir/f$i"; done
assert_eq "cwd: path with space" "cwd: $tmp/a dir" "$(cd "$tmp/a dir" && _how_to_context_cwd | head -1)"
assert_eq "cwd: files capped"   30 "$(cd "$tmp/a dir" && _how_to_context_cwd | sed -n 2p | sed 's/^files: //' | wc -w | tr -d ' ')"
mkdir "$tmp/dots" "$tmp/empty"; touch "$tmp/dots/.hidden"
assert_eq "cwd: dotfiles included" 'files: .hidden' "$(cd "$tmp/dots" && _how_to_context_cwd | sed -n 2p)"
assert_eq "cwd: empty dir" "cwd: $tmp/empty" "$(cd "$tmp/empty" && _how_to_context_cwd)"
assert_eq "cwd: hostile opts" "cwd: $tmp/empty" "$(
  cd "$tmp/empty"; set -euo pipefail; shopt -s failglob nocasematch nullglob; IFS=:; _how_to_context_cwd)"
assert_eq "git: silent outside repo" '' "$(cd "$tmp" && _how_to_context_git)"
assert_eq "git: root in repo" "git_root: ${here%/*}" "$(cd "$here" && _how_to_context_git | head -1)"
assert_eq "tools: only installed" 'tools: bash' "$(HOW_TO_TOOLS=(bash definitely-not-a-tool-xyz); _how_to_context_tools)"
assert_eq "tools: scalar list split" 'tools: bash sh' "$(unset HOW_TO_TOOLS; HOW_TO_TOOLS='bash sh'; _how_to_context_tools)"
assert_eq "os" "os: $(uname -sr)" "$(_how_to_context_os)"
assert_eq "os: ignores uname function" "os: $(command uname -sr)" "$(uname() { echo FAKE; }; _how_to_context_os)"
assert_eq "shell" "shell: bash $BASH_VERSION" "$(_how_to_context_shell)"
assert_eq "git: ignores git function" "git_root: ${here%/*}" "$(cd "$here"; git() { echo FAKE; }; _how_to_context_git | head -1)"
git init -q -b trunk "$tmp/repo"
assert_eq "git: branch with no commits" 'git_branch: trunk' "$(cd "$tmp/repo" && _how_to_context_git | sed -n 2p)"
git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
git -C "$tmp/repo" checkout -q --detach
assert_eq "git: no branch when detached" "git_root: $(cd "$tmp" && pwd -P)/repo" "$(cd "$tmp/repo" && _how_to_context_git)"

exit $(( failures > 0 ))
