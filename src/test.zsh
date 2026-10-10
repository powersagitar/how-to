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

exit $(( failures > 0 ))
