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

exit $(( failures > 0 ))
