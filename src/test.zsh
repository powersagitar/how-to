#!/usr/bin/env zsh
# Tests for how-to.zsh. Run: zsh src/test.zsh
here=${0:A:h}
source $here/how-to.zsh

integer failures=0
assert_eq() {
  if [[ $2 == $3 ]]; then
    print -r -- "ok   $1"
  else
    print -r -- "FAIL $1"
    print -r -- "  expected: ${(q+)2}"
    print -r -- "  actual:   ${(q+)3}"
    (( failures++ ))
  fi
}

# --- _how_to_clean
assert_eq "clean: fence"        'ls -la'        "$(print -r -- $'```\nls -la\n```' | _how_to_clean)"
assert_eq "clean: fence+lang"   'ls -la'        "$(print -r -- $'```bash\nls -la\n```' | _how_to_clean)"
assert_eq "clean: blank lines"  'ls'            "$(print -r -- $'\n\n  \nls\n\n' | _how_to_clean)"
assert_eq "clean: trailing ws"  'ls -a'         "$(print -r -- $'ls -a   \t' | _how_to_clean)"
assert_eq "clean: multi-line"   $'a \\\n  && b' "$(print -r -- $'a \\\n  && b' | _how_to_clean)"
assert_eq "clean: leading ws trimmed on first line" 'ls' "$(print -r -- '   ls' | _how_to_clean)"

# --- context assembly
assert_eq "ctx: order+skip" $'<context>\na: 1\nb: 2\n</context>' "$(
  _how_to_context_a() { print 'a: 1' }
  _how_to_context_b() { print 'b: 2' }
  _how_to_context_bad() { print -u2 boom; return 1 }
  HOW_TO_CONTEXT=(a missing bad b); _how_to_context 2>&1)"
assert_eq "ctx: preset kept" 'os' "$(HOW_TO_CONTEXT=(os); source $here/how-to.zsh; print $HOW_TO_CONTEXT)"
assert_eq "ctx: default list" 'os shell cwd git tools history' "${HOW_TO_CONTEXT[*]}"

# --- built-in context providers
tmp=$(mktemp -d); trap "rm -rf ${(q)tmp}" EXIT; mkdir "$tmp/a dir"; for i in {1..40}; touch "$tmp/a dir/f$i"
assert_eq "cwd: path with space" "cwd: $tmp/a dir" "$(cd "$tmp/a dir" && _how_to_context_cwd | head -1)"
assert_eq "cwd: files capped"   30 "$(cd "$tmp/a dir" && _how_to_context_cwd | sed -n 2p | sed 's/^files: //' | wc -w | tr -d ' ')"
assert_eq "git: silent outside repo" '' "$(cd "$tmp" && _how_to_context_git)"
assert_eq "git: root in repo" "git_root: ${here:h}" "$(cd $here && _how_to_context_git | head -1)"
assert_eq "tools: only installed" 'tools: zsh' "$(HOW_TO_TOOLS=(zsh definitely-not-a-tool-xyz); _how_to_context_tools)"
assert_eq "os" "os: $(uname -sr)" "$(_how_to_context_os)"
assert_eq "shell" "shell: zsh $ZSH_VERSION" "$(_how_to_context_shell)"

# --- history
assert_eq "hist: default count" 5 "$HOW_TO_HISTORY"
assert_eq "hist: order and limit" $'history: [exit 0] cmd3\nhistory: [exit 1] cmd4' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1 2 3 4) _how_to_hist_rc=(0 0 0 1) _how_to_hist_txt=(cmd1 cmd2 cmd3 cmd4) HOW_TO_HISTORY=2; _how_to_hist_lines 5)"
assert_eq "hist: current event skipped" 'history: [exit 0] cmd4' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(4 5) _how_to_hist_rc=(0 0) _how_to_hist_txt=(cmd4 cmd5) HOW_TO_HISTORY=2; _how_to_hist_lines 5)"
assert_eq "hist: off at 0" '' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1 2 3 4) _how_to_hist_rc=(0 0 0 1) _how_to_hist_txt=(cmd1 cmd2 cmd3 cmd4) HOW_TO_HISTORY=0; _how_to_hist_lines 9)"
assert_eq "hist: off when empty" '' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1 2 3 4) _how_to_hist_rc=(0 0 0 1) _how_to_hist_txt=(cmd1 cmd2 cmd3 cmd4) HOW_TO_HISTORY=; _how_to_hist_lines 9)"
assert_eq "hist: off for non-number" '' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1 2 3 4) _how_to_hist_rc=(0 0 0 1) _how_to_hist_txt=(cmd1 cmd2 cmd3 cmd4) HOW_TO_HISTORY=abc; _how_to_hist_lines 9)"
assert_eq "hist: nothing recorded" '' "$(_how_to_hist_num=() _how_to_hist_rc=(); _how_to_hist_lines 9 2>&1)"
assert_eq "hist: N above count" 'history: [exit 0] cmd1' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1) _how_to_hist_rc=(0) _how_to_hist_txt=(cmd1) HOW_TO_HISTORY=50; _how_to_hist_lines 9)"
assert_eq "hist: stale higher events skipped" $'history: [exit 0] cmd3\nhistory: [exit 0] cmd4' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(90 91 3 4) _how_to_hist_rc=(0 0 0 0) _how_to_hist_txt=(cmd90 cmd91 cmd3 cmd4) HOW_TO_HISTORY=5; _how_to_hist_lines 5)"
assert_eq "hist: unreadable skipped" 'history: [exit 0] cmd2' "$(
  _how_to_hist_text() { [[ $1 == 2 ]] && print cmd2 }
  _how_to_hist_num=(1 2) _how_to_hist_rc=(0 0) _how_to_hist_txt=(cmd1 cmd2) HOW_TO_HISTORY=5; _how_to_hist_lines 5)"
assert_eq "hist: newline escaped" 'history: [exit 0] a\nb' "$(
  _how_to_hist_text() { print -r -- $'a\nb' }
  _how_to_hist_num=(1) _how_to_hist_rc=(0) _how_to_hist_txt=($'a\nb') HOW_TO_HISTORY=5; _how_to_hist_lines 5)"
assert_eq "hist: truncated" "history: [exit 0] ${(l:500::x:)}…" "$(
  _how_to_hist_text() { print -r -- ${(l:501::x:)} }
  _how_to_hist_num=(1) _how_to_hist_rc=(0) _how_to_hist_txt=(${(l:501::x:)}) HOW_TO_HISTORY=5; _how_to_hist_lines 5)"
assert_eq "hist: verbatim text" "history: [exit 0] printf '%s\\n' \"\$x\" \\t" "$(
  _how_to_hist_text() { print -r -- "printf '%s\\n' \"\$x\" \\t" }
  _how_to_hist_num=(1) _how_to_hist_rc=(0) _how_to_hist_txt=("printf '%s\\n' \"\$x\" \\t") HOW_TO_HISTORY=5; _how_to_hist_lines 5)"
assert_eq "hist: add appends" '1 2|0 1|a b c' "$(
  _how_to_hist_num=() _how_to_hist_rc=() _how_to_hist_txt=()
  _how_to_hist_add 1 0 a; _how_to_hist_add 2 1 'b c'; print -r -- "$_how_to_hist_num|$_how_to_hist_rc|${_how_to_hist_txt[1]} ${_how_to_hist_txt[2]}")"
assert_eq "hist: add replaces last" '1 2|0 7|2|b2' "$(
  _how_to_hist_num=() _how_to_hist_rc=() _how_to_hist_txt=()
  _how_to_hist_add 1 0 a; _how_to_hist_add 2 1 b; _how_to_hist_add 2 7 b2; print -r -- "$_how_to_hist_num|$_how_to_hist_rc|${#_how_to_hist_txt}|${_how_to_hist_txt[2]}")"
assert_eq "hist: add trims to 100" '100 6 105 100 100 t6 t105' "$(
  _how_to_hist_num=() _how_to_hist_rc=() _how_to_hist_txt=()
  for i in {1..105}; _how_to_hist_add $i 0 t$i
  print ${#_how_to_hist_num} ${_how_to_hist_num[1]} ${_how_to_hist_num[-1]} ${#_how_to_hist_rc} ${#_how_to_hist_txt} ${_how_to_hist_txt[1]} ${_how_to_hist_txt[-1]})"
assert_eq "hist: add returns 0" 0 "$(_how_to_hist_num=() _how_to_hist_rc=() _how_to_hist_txt=(); _how_to_hist_add 1 0 a; print $?)"
assert_eq "hist: renumbered event skipped" 'history: [exit 0] cmd3' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(3 4) _how_to_hist_rc=(0 1) _how_to_hist_txt=(cmd3 other) HOW_TO_HISTORY=5; _how_to_hist_lines 5)"
assert_eq "hist: first record skipped" '' "$(
  unset _how_to_hist_ready; _how_to_hist_num=() _how_to_hist_rc=()
  _how_to_record; print -r -- "$_how_to_hist_num")"
assert_eq "hist: no command, no record" '1 2|0 1' "$(
  _how_to_hist_ready=1; unset _how_to_hist_flag; _how_to_hist_num=(1 2) _how_to_hist_rc=(0 1) _how_to_hist_txt=(cmd1 cmd2)
  (exit 130); _how_to_record; print -r -- "$_how_to_hist_num|$_how_to_hist_rc")"
assert_eq "hist: command ran, record and clear" "1 2 $(( HISTCMD - 1 ))|0 1 130|" "$(
  _how_to_hist_ready=1; _how_to_hist_ran; _how_to_hist_num=(1 2) _how_to_hist_rc=(0 1) _how_to_hist_txt=(cmd1 cmd2)
  (exit 130); _how_to_record; print -r -- "$_how_to_hist_num|$_how_to_hist_rc|${_how_to_hist_flag-}")"
assert_eq "hist: ksharrays" $'history: [exit 0] cmd3\nhistory: [exit 1] cmd4' "$(
  setopt ksharrays
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1 2 3 4) _how_to_hist_rc=(0 0 0 1) _how_to_hist_txt=(cmd1 cmd2 cmd3 cmd4) HOW_TO_HISTORY=2; _how_to_hist_lines 5)"
assert_eq "hist: hooks installed once" '1 1' "$(zsh -fic 'source '$here'/how-to.zsh; source '$here'/how-to.zsh; print ${#${(M)precmd_functions:#_how_to_record}} ${#${(M)preexec_functions:#_how_to_hist_ran}}' 2>/dev/null | tail -1)"
assert_eq "prompt: history line" 1 "$([[ $HOW_TO_SYSTEM_PROMPT == *'"history:" lines are the user'"'"'s latest commands, oldest first; "that"/"it" usually means the last one.'* ]] && print 1)"

# --- how-to end to end (stub provider, captured push)
_how_to_push() { pushed=$1 }
_how_to_provider_stub() {
  print -r -- "$1" > $tmp/sys; cat > $tmp/in
  [[ -e /dev/fd/3 ]] && print open >$tmp/fd3 || print closed >$tmp/fd3
  print -r -- "$stub_out"; return ${stub_rc:-0}
}
HOW_TO_PROVIDER=stub HOW_TO_CONTEXT=()
run() { pushed=; how-to "$@" 2>$tmp/err >/dev/null; rc=$?; err=$(<$tmp/err) }
last_in() { local s=$(<$tmp/in); print -r -- "${s##*$'\n'}" }

stub_out='tokei .'; run lines of code
assert_eq "e2e: pushed"   'tokei .' "$pushed"
assert_eq "e2e: rc"       0 $rc
assert_eq "e2e: request"  'Request: lines of code' "$(last_in)"
assert_eq "e2e: sys"      "$HOW_TO_SYSTEM_PROMPT" "$(<$tmp/sys)"
assert_eq "e2e: ctx block first" '<context>' "$(head -1 $tmp/in)"

stub_out='x'; run 'replace "foo" with $bar'
assert_eq "literal request" 'Request: replace "foo" with $bar' "$(last_in)"
stub_out=x; how-to find all *.nomatch-xyz files 2>/dev/null
assert_eq "noglob request" 'Request: find all *.nomatch-xyz files' "$(last_in)"
assert_eq "noglob alias" 'noglob how-to' "${aliases[how-to]}"
assert_eq "re-source ok" '' "$(source $here/how-to.zsh 2>&1)"

run;                          assert_eq "no args rc" 2 $rc; assert_eq "no args msg" 'usage: how-to <what you want to do>' "$err"
HOW_TO_PROVIDER=nope run x;   assert_eq "unknown rc" 1 $rc; assert_eq "unknown msg" "how-to: unknown provider 'nope'" "$err"
stub_out=''; stub_rc=1; run x; assert_eq "prov fail rc" 1 $rc; assert_eq "prov fail msg" 'how-to: provider failed' "$err"; stub_rc=0
stub_out=$'```\n```'; run x;  assert_eq "empty rc" 1 $rc; assert_eq "empty msg" 'how-to: no command returned' "$err"
stub_out='HOWTO_FAIL: not a shell task'; run x
assert_eq "fail rc" 1 $rc; assert_eq "fail msg" 'not a shell task' "$err"; assert_eq "fail not pushed" '' "$pushed"
stub_out=$'```\nHOWTO_FAIL: nope\n```'; run x
assert_eq "fenced fail msg" 'nope' "$err"; assert_eq "fenced fail not pushed" '' "$pushed"

# --- claude provider argv (fake executable; `command` bypasses functions)
mkdir $tmp/bin; print -r -- $'#!/bin/sh\nprintf "%s|" "$@"; echo; cat' > $tmp/bin/claude; chmod +x $tmp/bin/claude
assert_eq "claude argv" $'--print|--tools||--no-session-persistence|--system-prompt|SYS|--model|haiku|\nIN' \
  "$(PATH=$tmp/bin:$PATH; print IN | _how_to_provider_claude SYS)"
assert_eq "claude args override" $'--print|--tools||--no-session-persistence|--system-prompt|SYS|--model|sonnet|\nIN' \
  "$(PATH=$tmp/bin:$PATH; HOW_TO_CLAUDE_ARGS='--model sonnet'; print IN | _how_to_provider_claude SYS)"

# --- review fixes
assert_eq "push: backslashes kept" 'printf %s\n a\tb' "$(
  source $here/how-to.zsh; _how_to_push 'printf %s\n a\tb'; read -rz x; print -r -- "$x")"
assert_eq "ksharrays: clean" 'ls' "$(setopt ksharrays; print -r -- $'```\nls\n```' | _how_to_clean)"
assert_eq "ksharrays: ctx" $'<context>\na: 1\nb: 2\n</context>' "$(setopt ksharrays
  _how_to_context_a() { print 'a: 1' }; _how_to_context_b() { print 'b: 2' }
  HOW_TO_CONTEXT=(a b); _how_to_context 2>&1)"
stub_out='ls'; ( setopt ksharrays; run x; print -r -- "$pushed" > $tmp/ksh )
assert_eq "ksharrays: e2e" 'ls' "$(<$tmp/ksh)"
assert_eq "clean: prose around fence" 'fd -e log' \
  "$(print -r -- $'Here is the command:\n```bash\nfd -e log\n```\nThis finds logs.' | _how_to_clean)"
stub_out=$'Sorry.\nHOWTO_FAIL: no'; run x
assert_eq "fail on later line msg" 'no' "$err"; assert_eq "fail on later line not pushed" '' "$pushed"

# --- deferred fixes
assert_eq "clean: indented fence" 'ls -la' "$(print -r -- $'  ```bash\n  ls -la\n  ```' | _how_to_clean)"
assert_eq "clean: indented fence dedents" $'a \\\n  && b' \
  "$(print -r -- $'Run:\n   ```\n   a \\\n     && b\n   ```' | _how_to_clean)"
assert_eq "ctx: scalar list split" $'<context>\na: 1\nb: 2\n</context>' "$(
  _how_to_context_a() { print 'a: 1' }; _how_to_context_b() { print 'b: 2' }
  HOW_TO_CONTEXT='a b'; _how_to_context 2>&1)"
assert_eq "tools: scalar list split" 'tools: zsh sh' "$(HOW_TO_TOOLS='zsh sh'; _how_to_context_tools)"
assert_eq "os: ignores uname function" "os: $(command uname -sr)" "$(uname() { print FAKE }; _how_to_context_os)"
assert_eq "git: ignores git function" "git_root: ${here:h}" "$(cd $here; git() { print FAKE }; _how_to_context_git | head -1)"
git init -q -b trunk $tmp/repo
assert_eq "git: branch with no commits" 'git_branch: trunk' "$(cd $tmp/repo && _how_to_context_git | sed -n 2p)"
git -C $tmp/repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
git -C $tmp/repo checkout -q --detach
assert_eq "git: no branch when detached" "git_root: ${tmp:A}/repo" "$(cd $tmp/repo && _how_to_context_git)"

# --- spinner
assert_eq "spin: frame 0"     $'\r| thinking 0s\e[K'  "$(_how_to_spin_frame 0 0)"
assert_eq "spin: frame 1"     $'\r/ thinking 0s\e[K'  "$(_how_to_spin_frame 1 0)"
assert_eq "spin: frame 3"     $'\r\\ thinking 12s\e[K' "$(_how_to_spin_frame 3 12)"
assert_eq "spin: frame wraps" $'\r| thinking 1s\e[K'  "$(_how_to_spin_frame 4 1)"
assert_eq "spin: float secs"  $'\r- thinking 2s\e[K'  "$(_how_to_spin_frame 2 2.71)"
assert_eq "ksharrays: spin frame" $'\r/ thinking 0s\e[K' "$(setopt ksharrays; _how_to_spin_frame 1 0)"
assert_eq "spin: default on"  1 "$HOW_TO_SPINNER"
assert_eq "spin: preset kept" 0 "$(HOW_TO_SPINNER=0; source $here/how-to.zsh; print $HOW_TO_SPINNER)"
assert_eq "spin: off when not a tty" 1 "$(_how_to_spin_on 2>/dev/null; print $?)"
stub_out=ls; run x; assert_eq "spin: provider without fd 3" closed "$(<$tmp/fd3)"

# --- pty: interactive zsh with expect playing the terminal
if (( $+commands[expect] )); then
  cat > $tmp/zpty.exp <<'EOF'
lassign $argv zd mode marker
set timeout 5
log_user 0
set all ""
proc done {s} { puts $s; exit }
# On failure, also show the end of what the terminal printed.
proc fail {} {
  global all
  expect -timeout 0 -re {.+} { append all $expect_out(buffer) } timeout {} eof {}
  set t [string map {"\033" "\\e" "\r" "\\r" "\n" "\\n"} [string range $all end-299 end]]
  done "PTY-FAIL ...$t"
}
proc want {pat} {
  global all
  expect -ex $pat { append all $expect_out(buffer) } timeout fail eof fail
}
proc landed {} {
  # The pushed command is on the next prompt; running it shows the marker.
  global marker
  want "P> "
  send "\r"
  want $marker
}
# -d: skip global rc files (e.g. Debian's compinit, which can stop to ask).
spawn -noecho env TERM=xterm ZDOTDIR=$zd zsh -d -i
want "P> "
set all ""
if {$mode eq "spin"} {
  # Shift the shell's age to ~0.8 s past a whole second: elapsed time must
  # count from the call, not from the shell's start.
  send "command sleep 0.8\r"
  want "P> "
  set all ""
  send "how-to x\r"
  want "| thinking 0s"
  want "thinking 1s"
  want "\033\[K\r\033\[K"
  if {[string first "thinking 1s\033\[K\r\033\[K" $all] < 0} { done PTY-NOERASE }
  landed
} elseif {$mode eq "off" || $mode eq "dumb" || $mode eq "fast"} {
  if {$mode eq "dumb"} {
    send "TERM=dumb\r"
    want "P> "
  }
  if {$mode eq "off"} { send "HOW_TO_SPINNER=0 how-to x\r" } else { send "how-to x\r" }
  landed
  if {[string first "thinking" $all] >= 0} { done PTY-DREW }
} elseif {$mode eq "ctrlc"} {
  send "how-to x\r"
  want "thinking 0s"
  send "\003"
  want "P> "
  set timeout 1
  expect -ex "thinking" { done PTY-REDRAWN } timeout {}
  set timeout 5
  send "echo FOLLOW-\$((1+1))\r"
  want "FOLLOW-2"
} elseif {$mode eq "hist"} {
  foreach c {"true" "false" " echo SECRET" ""} {
    send "$c\r"
    want "P> "
  }
  send "\003"
  want "P> "
  send "how-to x\r"
  landed
} elseif {$mode eq "fail"} {
  send "how-to x\r"
  want "nope"
  if {[string first "\r\033\[Knope" $all] < 0} { done PTY-NOERASE }
}
done PTY-OK
EOF
  mkdir $tmp/zd
  cat > $tmp/zd/.zshrc <<EOF
PS1='P> '; PROMPT_EOL_MARK=''; HISTFILE=
source '$here/how-to.zsh'
HOW_TO_CONTEXT=() HOW_TO_PROVIDER=stub
_how_to_provider_stub() { cat >/dev/null; command sleep \$(<'$tmp/pty_sleep'); cat '$tmp/pty_cmd' }
EOF
  mkdir $tmp/zdh
  printf 'old1\nold2\n' > $tmp/zhist
  cat > $tmp/zdh/.zshrc <<EOF
PS1='P> '; PROMPT_EOL_MARK=''; HISTFILE='$tmp/zhist'
setopt histignorespace
_clobber() { true }
precmd_functions=(_clobber)
source '$here/how-to.zsh'
HOW_TO_CONTEXT=(history) HOW_TO_PROVIDER=stub
_how_to_provider_stub() { cat > '$tmp/zhist_in'; cat '$tmp/pty_cmd' }
EOF
  zpty_run() {  # zpty_run <mode> <sleep> <marker> <stub output>
    print -r -- $2 > $tmp/pty_sleep; print -r -- $4 > $tmp/pty_cmd
    expect $tmp/zpty.exp $tmp/zd $1 $3
  }
  assert_eq "pty: spinner draws and clears"     PTY-OK "$(zpty_run spin 1.3 ZS-42 'echo ZS-$((6*7))')"
  assert_eq "pty: spinner off"                  PTY-OK "$(zpty_run off 0.4 ZS-42 'echo ZS-$((6*7))')"
  assert_eq "pty: spinner off for dumb TERM"    PTY-OK "$(zpty_run dumb 0.4 ZS-42 'echo ZS-$((6*7))')"
  assert_eq "pty: spinner ctrl-c"               PTY-OK "$(zpty_run ctrlc 3 x 'echo x')"
  assert_eq "pty: spinner erased before error"  PTY-OK "$(zpty_run fail 0.4 x 'HOWTO_FAIL: nope')"
  assert_eq "pty: no spinner for fast provider" PTY-OK "$(zpty_run fast 0 ZS-42 'echo ZS-$((6*7))')"
  assert_eq "pty: history recorded" PTY-OK "$(print -r -- 0 > $tmp/pty_sleep; print -r -- 'echo ZH-$((6*7))' > $tmp/pty_cmd; expect $tmp/zpty.exp $tmp/zdh hist ZH-42)"
  assert_eq "pty: history context" $'history: [exit 0] true\nhistory: [exit 1] false' "$(grep '^history:' $tmp/zhist_in)"
  # zshaddhistory returning 1 keeps a line out of history like HIST_IGNORE_SPACE.
  mkdir $tmp/zdha
  printf 'old1\nold2\n' > $tmp/zhist; : > $tmp/zhist_in
  cat > $tmp/zdha/.zshrc <<EOF
PS1='P> '; PROMPT_EOL_MARK=''; HISTFILE='$tmp/zhist'
zshaddhistory() { [[ \$1 != *SECRET* ]] }
source '$here/how-to.zsh'
HOW_TO_CONTEXT=(history) HOW_TO_PROVIDER=stub
_how_to_provider_stub() { cat > '$tmp/zhist_in'; cat '$tmp/pty_cmd' }
EOF
  assert_eq "pty: history recorded (zshaddhistory)" PTY-OK "$(expect $tmp/zpty.exp $tmp/zdha hist ZH-42)"
  assert_eq "pty: history context (zshaddhistory)" $'history: [exit 0] true\nhistory: [exit 1] false' "$(grep '^history:' $tmp/zhist_in)"
  # Returning 2 only keeps the line out of HISTFILE: it stays in the
  # session's history, so it is sent (documented).
  mkdir $tmp/zdh2
  printf 'old1\nold2\n' > $tmp/zhist; : > $tmp/zhist_in
  sed 's/!= \*SECRET\* \]\] }$/!= *SECRET* ]] || return 2 }/' $tmp/zdha/.zshrc > $tmp/zdh2/.zshrc
  assert_eq "pty: history recorded (zshaddhistory 2)" PTY-OK "$(expect $tmp/zpty.exp $tmp/zdh2 hist ZH-42)"
  assert_eq "pty: history context (zshaddhistory 2)" $'history: [exit 0] true\nhistory: [exit 1] false\nhistory: [exit 0]  echo SECRET' "$(grep '^history:' $tmp/zhist_in)"
else
  print 'skip pty (no expect)'
fi

exit $(( failures > 0 ))
