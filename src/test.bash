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

# --- how-to end to end (stub provider, captured push)
shopt -s expand_aliases
_how_to_push() { pushed=$1; }
_how_to_provider_stub() {
  printf '%s\n' "$1" > "$tmp/sys"; cat > "$tmp/in"
  printf '%s\n' "$stub_out"; return "${stub_rc:-0}"
}
HOW_TO_PROVIDER=stub
HOW_TO_CONTEXT=()
run() { pushed=; _how_to_main "$@" 2>"$tmp/err" >/dev/null; rc=$?; err=$(<"$tmp/err"); }
last_in() { local s; s=$(<"$tmp/in"); printf '%s\n' "${s##*$'\n'}"; }
globf() { printf '%s' "${-//[^f]/}"; }

stub_out='tokei .'; run lines of code
assert_eq "e2e: pushed"   'tokei .' "$pushed"
assert_eq "e2e: rc"       0 "$rc"
assert_eq "e2e: request"  'Request: lines of code' "$(last_in)"
assert_eq "e2e: sys"      "$HOW_TO_SYSTEM_PROMPT" "$(<"$tmp/sys")"
assert_eq "e2e: ctx block first" '<context>' "$(head -1 "$tmp/in")"

stub_out='x'; run 'replace "foo" with $bar'
assert_eq "literal request" 'Request: replace "foo" with $bar' "$(last_in)"
touch "$tmp/x.nomatch"; cd "$tmp"
stub_out=x; eval 'how-to find all *.nomatch files' 2>/dev/null
assert_eq "noglob request" 'Request: find all *.nomatch files' "$(last_in)"
assert_eq "glob restored" '' "$(globf)"
cd "$here"
set -f; eval 'how-to x' >/dev/null 2>&1; f=$(globf); set +f
assert_eq "glob kept off" f "$f"
eval 'how-to' 2>/dev/null; a=$(globf)
HOW_TO_PROVIDER=nope; eval 'how-to x' 2>/dev/null; b=$(globf); HOW_TO_PROVIDER=stub
stub_out='HOWTO_FAIL: x'; eval 'how-to x' 2>/dev/null; c=$(globf)
assert_eq "glob restored on error" '||' "$a|$b|$c"
assert_eq "re-source ok" '' "$(source "$here/how-to.bash" 2>&1)"

run;                          assert_eq "no args rc" 2 "$rc"; assert_eq "no args msg" 'usage: how-to <what you want to do>' "$err"
HOW_TO_PROVIDER=nope run x;   assert_eq "unknown rc" 1 "$rc"; assert_eq "unknown msg" "how-to: unknown provider 'nope'" "$err"
stub_out=''; stub_rc=1; run x; assert_eq "prov fail rc" 1 "$rc"; assert_eq "prov fail msg" 'how-to: provider failed' "$err"; stub_rc=0
stub_out=$'```\n```'; run x;  assert_eq "empty rc" 1 "$rc"; assert_eq "empty msg" 'how-to: no command returned' "$err"
stub_out='HOWTO_FAIL: not a shell task'; run x
assert_eq "fail rc" 1 "$rc"; assert_eq "fail msg" 'not a shell task' "$err"; assert_eq "fail not pushed" '' "$pushed"
stub_out=$'```\nHOWTO_FAIL: nope\n```'; run x
assert_eq "fenced fail msg" 'nope' "$err"; assert_eq "fenced fail not pushed" '' "$pushed"
stub_out=$'Sorry.\nHOWTO_FAIL: no'; run x
assert_eq "fail on later line msg" 'no' "$err"; assert_eq "fail on later line not pushed" '' "$pushed"
stub_out='ls'; ( set -euo pipefail; shopt -s failglob nocasematch; IFS=:; run x; printf '%s\n' "$pushed" > "$tmp/hostile" )
assert_eq "e2e: hostile opts" 'ls' "$(<"$tmp/hostile")"
stub_out='howto_fail: x'; ( shopt -s nocasematch; run x; printf '%s\n' "$pushed" > "$tmp/nocase" )
assert_eq "fail: case-sensitive under nocasematch" 'howto_fail: x' "$(<"$tmp/nocase")"

# --- claude provider argv (fake executable; `command` bypasses functions)
mkdir "$tmp/bin"; printf '%s\n' '#!/bin/sh' 'printf "%s|" "$@"; echo; cat' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
assert_eq "claude argv" $'--print|--tools||--no-session-persistence|--system-prompt|SYS|--model|haiku|\nIN' \
  "$(PATH=$tmp/bin:$PATH; echo IN | _how_to_provider_claude SYS)"
assert_eq "claude args override" $'--print|--tools||--no-session-persistence|--system-prompt|SYS|--model|sonnet|\nIN' \
  "$(PATH=$tmp/bin:$PATH; HOW_TO_CLAUDE_ARGS='--model sonnet'; echo IN | _how_to_provider_claude SYS)"

# --- push and readline insertion (fresh source: the real _how_to_push)
assert_eq "push: non-interactive prints" 'printf %s\n a\tb' \
  "$(source "$here/how-to.bash"; _how_to_push 'printf %s\n a\tb')"
_how_to_pending='printf %s\n a\tb'; READLINE_LINE=; READLINE_POINT=0; _how_to_insert
assert_eq "insert: verbatim" 'printf %s\n a\tb' "$READLINE_LINE"
assert_eq "insert: point at end" 16 "$READLINE_POINT"
assert_eq "insert: pending cleared" '' "$_how_to_pending"
READLINE_LINE=keep; _how_to_insert
assert_eq "insert: no-op when empty" keep "$READLINE_LINE"
assert_eq "source: silent non-interactive" '' "$("$BASH" -c "source '$here/how-to.bash'" 2>&1)"
for map in emacs vi-insert; do
  assert_eq "bind: $map" yes "$("$BASH" --norc -ic "source '$here/how-to.bash'; bind -m $map -X" 2>/dev/null |
    grep -qE '^"\\e\[0n":? "_how_to_insert"$' && echo yes)"
done

assert_eq "prompt_command: string appended once" $'echo hi\n_how_to_restore_glob' "$("$BASH" --norc -ic \
  "PROMPT_COMMAND='echo hi'; source '$here/how-to.bash'; source '$here/how-to.bash'; printf %s \"\$PROMPT_COMMAND\"" 2>/dev/null)"
assert_eq "prompt_command: array appended once" 'a _how_to_restore_glob' "$("$BASH" --norc -ic \
  "PROMPT_COMMAND=(a); source '$here/how-to.bash'; source '$here/how-to.bash'; printf %s \"\${PROMPT_COMMAND[*]}\"" 2>/dev/null)"
assert_eq "restore_glob: keeps \$?" 3 "$(_how_to_f=hB; set -f; (exit 3); _how_to_restore_glob; echo "$?${-//[^f]/}")"

# --- pty: interactive bash with expect playing the terminal
if type -P expect >/dev/null; then
  cat > "$tmp/pty.exp" <<'EOF'
lassign $argv bash rc mode marker
set timeout 5
log_user 0
set all ""
proc done {s} { puts $s; exit }
proc want {pat} {
  global all
  expect -ex $pat { append all $expect_out(buffer) } timeout { done PTY-FAIL } eof { done PTY-FAIL }
}
spawn -noecho env TERM=xterm $bash --noprofile --rcfile $rc -i
want "P> "
if {$mode eq "nounset"} {
  # The request fails to expand after the alias's `set -f`: globbing must
  # still be back on at the next command.
  send "set -u; how-to x \$nosuch\r"
  want "P> "
  send "echo GLOB-\$(\[\[ \$- == *f* \]\] && echo OFF || echo ON)\r"
  want $marker
  done PTY-OK
}
send "how-to x\r"
want "\033\[5n"
if {$mode eq "ctrlc"} {
  # Interrupt the wait for a reply that never comes: the tty is restored.
  after 300
  send "\003"
  want "P> "
  send "head -1\r"
  after 300
  send "zzz\r"
  want "zzz\r\nzzz"
} elseif {$mode eq "none"} {
  # Never answer: the command is printed, and the tty is cooked with echo again.
  want "$marker\r\n"
  want "P> "
  send "head -1\r"
  after 300
  send "zzz\r"
  want "zzz\r\nzzz"
} else {
  if {$mode ne "0"} { sleep $mode }
  send "\033\[0n"
  want "P> "
  send "\r"
  want $marker
  want "P> "
}
if {[string first "\[0n" $all] >= 0} { done PTY-ECHOED }
done PTY-OK
EOF
  pty() {  # pty <mode: 0|seconds|none> <marker> <stub output>
    printf '%s\n' "$3" > "$tmp/pty_cmd"
    cat > "$tmp/pty_rc" <<EOF
PS1='P> '; HISTFILE=; unset PROMPT_COMMAND
source '$here/how-to.bash'
HOW_TO_CONTEXT=() HOW_TO_PROVIDER=stub
_how_to_provider_stub() { cat >/dev/null; cat '$tmp/pty_cmd'; }
EOF
    expect "$tmp/pty.exp" "$BASH" "$tmp/pty_rc" "$1" "$2"
  }
  assert_eq "pty: inserted"   PTY-OK "$(pty 0   INSERTED-42 'echo INSERTED-$((6*7))')"
  assert_eq "pty: slow reply" PTY-OK "$(pty 0.3 INSERTED-42 'echo INSERTED-$((6*7))')"
  assert_eq "pty: multi-line" PTY-OK "$(pty 0   B-2 $'echo A \\\n  && echo B-$((1+1))')"
  assert_eq "pty: no reply"   PTY-OK "$(pty none 'echo NOREPLY-$((1+1))' 'echo NOREPLY-$((1+1))')"
  assert_eq "pty: ctrl-c restores tty" PTY-OK "$(pty ctrlc x 'echo NOREPLY')"
  assert_eq "pty: glob back after expansion error" PTY-OK "$(pty nounset GLOB-ON 'echo x')"
else
  echo 'skip pty (no expect)'
fi

exit $(( failures > 0 ))
