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
assert_eq "ctx: default list" 'os shell cwd git tools' "$HOW_TO_CONTEXT"

# --- built-in context providers
tmp=$(mktemp -d); trap "rm -rf ${(q)tmp}" EXIT; mkdir "$tmp/a dir"; for i in {1..40}; touch "$tmp/a dir/f$i"
assert_eq "cwd: path with space" "cwd: $tmp/a dir" "$(cd "$tmp/a dir" && _how_to_context_cwd | head -1)"
assert_eq "cwd: files capped"   30 "$(cd "$tmp/a dir" && _how_to_context_cwd | sed -n 2p | sed 's/^files: //' | wc -w | tr -d ' ')"
assert_eq "git: silent outside repo" '' "$(cd "$tmp" && _how_to_context_git)"
assert_eq "git: root in repo" "git_root: ${here:h}" "$(cd $here && _how_to_context_git | head -1)"
assert_eq "tools: only installed" 'tools: zsh' "$(HOW_TO_TOOLS=(zsh definitely-not-a-tool-xyz); _how_to_context_tools)"
assert_eq "os" "os: $(uname -sr)" "$(_how_to_context_os)"
assert_eq "shell" "shell: zsh $ZSH_VERSION" "$(_how_to_context_shell)"

# --- how-to end to end (stub provider, captured push)
_how_to_push() { pushed=$1 }
_how_to_provider_stub() {
  print -r -- "$1" > $tmp/sys; cat > $tmp/in
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

exit $(( failures > 0 ))
