# Recent-Command Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send the last `HOW_TO_HISTORY` commands and their exit statuses to the model as `history: [exit <rc>] <command>` context lines, in zsh and bash.

**Architecture:** A prompt hook (`_how_to_record`) stores `(event number, $?)` pairs in two global arrays; a context provider (`_how_to_context_history`) reads command text for those events from shell history with `fc` at call time, so the shell's own history filters apply. Pure helpers (`_how_to_hist_add`, `_how_to_hist_lines`, `_how_to_hist_text`) hold the logic so unit tests can drive them without a real history.

**Tech Stack:** zsh, bash >= 4.4, expect for pty tests.

**Spec:** `docs/superpowers/specs/2026-10-23-history-context-design.md`

## Global Constraints

- Line format, exactly: `history: [exit <rc>] <command>`, oldest first.
- `HOW_TO_HISTORY` default `5`; `0`, empty or non-number prints nothing. Set only when unset.
- Default `HOW_TO_CONTEXT`: `(os shell cwd git tools history)`.
- Commands longer than 500 characters: first 500 characters + `…`. Newline in a command → the two characters `\n`.
- Arrays `_how_to_hist_num`, `_how_to_hist_rc` trimmed to the newest 100 entries.
- New system-prompt line, byte-identical in both files, inserted before `If the request cannot be done...`:
  `"history:" lines are the user's latest commands, oldest first; "that"/"it" usually means the last one.`
- Hooks installed only in interactive shells, once across re-sourcing. First hook call after sourcing records nothing.
- zsh functions start with `emulate -L zsh`; bash functions start with `local -`, use `local IFS=$' \t\n'` when splitting, and survive `set -euo pipefail`, `failglob`, `nocasematch`, odd `IFS`. External programs via `command` (`fc` is a builtin).

## Review Focus

- Prefix assignment `HOW_TO_HISTORY=0 how-to ...` must suppress history for that call in bash (goes through `_how_to_pre`'s snapshot) — e2e test in Task 2.
- History renumbered below recorded events (bash `history -c`, zsh `fc -p`): stale higher numbers must be ignored, not crash — unit test `hist: stale higher events skipped` in Tasks 1 and 2.
- Commands containing `%`, backslashes and quotes must print verbatim — unit test `hist: verbatim text` in Tasks 1 and 2.
- `HOW_TO_HISTORY` larger than what is recorded prints everything recorded — unit test `hist: N above count` in Tasks 1 and 2.
- `how-to` called from a non-interactive shell or script (no hook, empty arrays) prints no `history:` lines and no error — unit test `hist: nothing recorded` in Tasks 1 and 2.

---

### Task 1: zsh — recording hook, provider, prompt line

**Files:**
- Modify: `src/how-to.zsh` (context section; system prompt; end of file for hook install)
- Modify: `src/how-to.bash` (system prompt only, so the bash byte-identity test keeps passing)
- Test: `src/test.zsh`

**Interfaces:**
- Produces (zsh; Task 2 mirrors these names exactly in bash):
  - `_how_to_hist_add <event> <rc>` — append the pair; if `<event>` equals the last stored event, replace its rc instead; trim both arrays to the newest 100.
  - `_how_to_hist_text <event>` — print that event's command text (`fc -ln <event> <event>`), non-zero if missing. Tests override it.
  - `_how_to_hist_lines <current_event>` — print the `history:` lines for stored events `< current_event`, last `HOW_TO_HISTORY` of them in array order, skipping events whose text fails or is empty; escape newlines, truncate.
  - `_how_to_context_history` — `_how_to_hist_lines $HISTCMD`.
  - `_how_to_record` — precmd hook: if `_how_to_hist_ready` is unset, set it and return; else `_how_to_hist_add $(( HISTCMD - 1 )) <saved $?>`.
  - Globals `_how_to_hist_num`, `_how_to_hist_rc` (arrays, created only if unset), `_how_to_hist_ready` (unset on every source).

- [ ] **Step 1: Write the failing unit tests** in a new `# --- history` section of `src/test.zsh` (after built-in context providers). Each test runs in `$(...)` with arrays set directly and `_how_to_hist_text() { print -r -- "cmd$1" }` unless stated:

```zsh
assert_eq "hist: default count" 5 "$HOW_TO_HISTORY"
assert_eq "ctx: default list" 'os shell cwd git tools history' "${HOW_TO_CONTEXT[*]}"
assert_eq "hist: order and limit" $'history: [exit 0] cmd3\nhistory: [exit 1] cmd4' "$(
  _how_to_hist_text() { print -r -- "cmd$1" }
  _how_to_hist_num=(1 2 3 4) _how_to_hist_rc=(0 0 0 1) HOW_TO_HISTORY=2; _how_to_hist_lines 5)"
assert_eq "hist: current event skipped" 'history: [exit 0] cmd4' "$(… nums=(4 5) rc=(0 0); _how_to_hist_lines 5)"
assert_eq "hist: off at 0"           '' "$(… HOW_TO_HISTORY=0; _how_to_hist_lines 9)"
assert_eq "hist: off when empty"     '' "$(… HOW_TO_HISTORY=; _how_to_hist_lines 9)"
assert_eq "hist: off for non-number" '' "$(… HOW_TO_HISTORY=abc; _how_to_hist_lines 9)"
assert_eq "hist: nothing recorded"   '' "$(_how_to_hist_num=() _how_to_hist_rc=(); _how_to_hist_lines 9 2>&1)"
assert_eq "hist: N above count" 'history: [exit 0] cmd1' "$(… nums=(1) rc=(0) HOW_TO_HISTORY=50; _how_to_hist_lines 9)"
assert_eq "hist: stale higher events skipped" $'history: [exit 0] cmd3\nhistory: [exit 0] cmd4' \
  "$(… nums=(90 91 3 4) rc=(0 0 0 0); _how_to_hist_lines 5)"
assert_eq "hist: unreadable skipped" 'history: [exit 0] cmd2' \
  "$(_how_to_hist_text() { [[ $1 == 2 ]] && print cmd2 }; nums=(1 2) rc=(0 0); _how_to_hist_lines 5)"
assert_eq "hist: newline escaped" 'history: [exit 0] a\nb' "$(_how_to_hist_text() { print -r -- $'a\nb' }; …)"
assert_eq "hist: truncated" "history: [exit 0] ${(l:500::x:)}…" "$(_how_to_hist_text() { print -r -- ${(l:501::x:)} }; …)"
assert_eq "hist: verbatim text" "history: [exit 0] printf '%s\\n' \"\$x\" \\t" "$(_how_to_hist_text() { print -r -- "printf '%s\\n' \"\$x\" \\t" }; …)"
assert_eq "hist: add appends"       '1 2|0 1' "$(_how_to_hist_num=() _how_to_hist_rc=(); _how_to_hist_add 1 0; _how_to_hist_add 2 1; print -r -- "$_how_to_hist_num|$_how_to_hist_rc")"
assert_eq "hist: add replaces last" '1 2|0 7' "$(…; _how_to_hist_add 1 0; _how_to_hist_add 2 1; _how_to_hist_add 2 7; …)"
assert_eq "hist: add trims to 100"  '100 6 105' "$(…; for i in {1..105}; _how_to_hist_add $i 0; print ${#_how_to_hist_num} ${_how_to_hist_num[1]} ${_how_to_hist_num[-1]})"
assert_eq "hist: first record skipped" '' "$(unset _how_to_hist_ready; _how_to_hist_num=() _how_to_hist_rc=(); _how_to_record; print -r -- "$_how_to_hist_num")"
assert_eq "hist: ksharrays" $'history: [exit 0] cmd3\nhistory: [exit 1] cmd4' "$(setopt ksharrays; … same as order and limit)"
assert_eq "hist: hook installed once" 1 "$(zsh -fic 'source '$here'/how-to.zsh; source '$here'/how-to.zsh; print ${#${(M)precmd_functions:#_how_to_record}}')"
assert_eq "prompt: history line" 1 "$([[ $HOW_TO_SYSTEM_PROMPT == *'"history:" lines are the user'"'"'s latest commands, oldest first; "that"/"it" usually means the last one.'* ]] && print 1)"
```

(`…` = the default `_how_to_hist_text` stub and arrays shown in "order and limit"; write each out in full.)

- [ ] **Step 2: Run** `zsh src/test.zsh | grep -v '^ok'` — Expected: the `hist:`, `ctx: default list` and `prompt: history line` tests FAIL (functions undefined / old defaults).

- [ ] **Step 3: Implement in `src/how-to.zsh`:** `HOW_TO_HISTORY` default and `history` in the `HOW_TO_CONTEXT` default (context section); the helper functions and globals from Interfaces, after `_how_to_context_tools`; the prompt line in `HOW_TO_SYSTEM_PROMPT`; at end of file, before the alias: `unset _how_to_hist_ready`, and if `[[ -o interactive ]]`, `autoload -Uz add-zsh-hook && add-zsh-hook precmd _how_to_record`. `_how_to_record` is the one function whose first statement is `local rc=$?`, before `emulate -L zsh`, because `emulate` sets `$?` to 0; add a comment saying so. Validate `HOW_TO_HISTORY` with `[[ $HOW_TO_HISTORY == <1-> ]]`. Truncate with `${text[1,500]}…` when `${#text} > 500`; escape with `${text//$'\n'/\\n}`.

- [ ] **Step 4: Add the same prompt line to `HOW_TO_SYSTEM_PROMPT` in `src/how-to.bash`** (bash default context and provider come in Task 2).

- [ ] **Step 5: Run** `zsh src/test.zsh | grep -v '^ok'` and `/opt/homebrew/bin/bash src/test.bash | grep -v '^ok'` — Expected: no FAIL in either suite (bash still has the old defaults and its own `ctx: default list`; `prompt: matches zsh` passes).

- [ ] **Step 6: Add the pty test.** In `src/test.zsh`'s `zpty.exp`, add mode `hist`:

```tcl
} elseif {$mode eq "hist"} {
  foreach c {"true" "false" " echo SECRET" ""} {
    send "$c\r"
    want "P> "
  }
  send "how-to x\r"
  landed
}
```

In `$tmp/zd/.zshrc` (before `source`): write `$tmp/zhist` containing `old1\nold2` and set `HISTFILE=$tmp/zhist` instead of `HISTFILE=` for this mode only — simplest: a second ZDOTDIR `$tmp/zdh` whose `.zshrc` is the existing one plus `setopt histignorespace`, `precmd_functions=(_clobber); _clobber() { true }` before `source`, `HISTFILE=$tmp/zhist`, `HOW_TO_CONTEXT=(history)`, and a stub that saves stdin: `_how_to_provider_stub() { cat > '$tmp/zhist_in'; cat '$tmp/pty_cmd' }`. Then:

```zsh
assert_eq "pty: history recorded" PTY-OK "$(print -r -- 0 > $tmp/pty_sleep; print -r -- 'echo ZH-$((6*7))' > $tmp/pty_cmd; expect $tmp/zpty.exp $tmp/zdh hist ZH-42)"
assert_eq "pty: history context" $'history: [exit 0] true\nhistory: [exit 1] false' "$(grep '^history:' $tmp/zhist_in)"
```

- [ ] **Step 7: Run** `zsh src/test.zsh | grep -v '^ok'` — Expected: no FAIL. If `pty: history context` shows `[exit 0] false`, the `_clobber` hook reset `$?`: install with `precmd_functions=(_how_to_record ${precmd_functions:#_how_to_record})` instead of `add-zsh-hook`, keep the "installed once" test, rerun.

- [ ] **Step 8: Commit**

```bash
git add src/how-to.zsh src/how-to.bash src/test.zsh
git commit -m "zsh: recent commands and exit statuses as context"
```

---

### Task 2: bash — recording hook and provider

**Files:**
- Modify: `src/how-to.bash` (context section; install block at the end next to `_how_to_restore_glob`)
- Test: `src/test.bash`

**Interfaces:**
- Consumes: Task 1's function and global names and behavior; the prompt line already in `src/how-to.bash`.
- Produces: same functions as Task 1, plus global `_how_to_hist_seen` (last `HISTCMD - 1` seen by the hook). `_how_to_record` must `return` the `$?` it saw.
  - `_how_to_record`: `rc=$?`, `ev=$(( HISTCMD - 1 ))`; if `_how_to_hist_ready` unset → set it, `_how_to_hist_seen=$ev`, return rc; if `ev != _how_to_hist_seen` → `_how_to_hist_add "$ev" "$rc"`, `_how_to_hist_seen=$ev`; return rc.
  - `_how_to_hist_text`: `fc -ln "$1" "$1"`, strip leading whitespace.

- [ ] **Step 1: Write the failing unit tests** in a new `# --- history` section of `src/test.bash`: every `hist:` test from Task 1 Step 1 translated to bash (`ksharrays` → `hist: hostile opts`, run under `set -euo pipefail; shopt -s failglob nocasematch nullglob; IFS=:`; truncation expectation built with `printf -v`), change `ctx: default list` to `'os shell cwd git tools history'`, plus:

```bash
assert_eq "hist: unchanged event not recorded" '5|1' "$(
  _how_to_hist_ready=1 _how_to_hist_seen=5 _how_to_hist_num=(5) _how_to_hist_rc=(1)
  HISTCMD=6; false; _how_to_record; printf '%s' "${_how_to_hist_num[*]}|${_how_to_hist_rc[*]}")"
assert_eq "hist: record keeps status" 3 "$(_how_to_hist_ready=1; (exit 3); _how_to_record; echo $?)"
assert_eq "hist: hook installed once (string)" 1 "$(bash --norc -ic "PROMPT_COMMAND='echo hi'; source '$here/how-to.bash'; source '$here/how-to.bash'; grep -c _how_to_record <<< \"\$PROMPT_COMMAND\"" 2>/dev/null)"
assert_eq "hist: hook first (string)" '_how_to_record' "$(bash --norc -ic "PROMPT_COMMAND='echo hi'; source '$here/how-to.bash'; head -1 <<< \"\$PROMPT_COMMAND\"" 2>/dev/null)"
assert_eq "hist: prefix HOW_TO_HISTORY=0" '' "$(… e2e run with HOW_TO_CONTEXT=(history), arrays preset, stub _how_to_hist_text, called as HOW_TO_HISTORY=0 through the alias path used by existing e2e tests; grep '^history:' "$tmp/in")"
```

(Assigning `HISTCMD` in a subshell drops its special meaning there, which is what lets the unchanged-event test drive it. If bash rejects that, factor the event read into `_how_to_record` calling `_how_to_hist_event` — `echo $(( HISTCMD - 1 ))` — and stub that instead.) Add an array-`PROMPT_COMMAND` variant of both install tests, guarded by `(( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) ))`, expecting element 0 to be `_how_to_record`.

- [ ] **Step 2: Run** `/opt/homebrew/bin/bash src/test.bash | grep -v '^ok'` — Expected: the new tests FAIL.

- [ ] **Step 3: Implement in `src/how-to.bash`:** defaults, helpers and globals as in Task 1 (validate with `[[ $HOW_TO_HISTORY =~ ^[0-9]+$ ]] && (( 10#$HOW_TO_HISTORY > 0 ))` after saving/restoring `shopt` like `_how_to_clean`; `${text:0:500}…`; `${text//$'\n'/\\n}`). Unset `_how_to_hist_ready` on source. In the existing `if [[ $- == *i* ]]` block, prepend `_how_to_record` to `PROMPT_COMMAND` once — array form: `PROMPT_COMMAND=(_how_to_record "${PROMPT_COMMAND[@]}")` unless present; string form: `_how_to_record${PROMPT_COMMAND:+$'\n'$PROMPT_COMMAND}` unless present. Keep `_how_to_restore_glob` appended as now.

- [ ] **Step 4: Run** `/opt/homebrew/bin/bash src/test.bash | grep -v '^ok'` — Expected: no FAIL. Also `zsh src/test.zsh | grep -v '^ok'` — no FAIL.

- [ ] **Step 5: Add the pty test.** In `pty.exp`, add mode `hist` before the `spin` block:

```tcl
if {$mode eq "hist"} {
  foreach c {"true" "false" " echo SECRET" ""} {
    send "$c\r"
    want "P> "
  }
  send "how-to x\r"
  want "\033\[5n"
  send "\033\[0n"
  want "P> "
  send "\r"
  want $marker
  done PTY-OK
}
```

Write a separate rc `$tmp/pty_hrc`: `PS1='P> '; HISTFILE='$tmp/bhist'; HISTCONTROL=ignorespace; PROMPT_COMMAND=true`, then `source`, `HOW_TO_CONTEXT=(history) HOW_TO_PROVIDER=stub`, stub `cat > '$tmp/bhist_in'; cat '$tmp/pty_cmd'`; pre-fill `$tmp/bhist` with `old1` and `old2`. Then:

```bash
assert_eq "pty: history recorded" PTY-OK "$(printf '%s\n' 'echo BH-$((6*7))' > "$tmp/pty_cmd"; expect "$tmp/pty.exp" "$BASH" "$tmp/pty_hrc" hist BH-42 1)"
assert_eq "pty: history context" $'history: [exit 0] true\nhistory: [exit 1] false' "$(grep '^history:' "$tmp/bhist_in")"
```

- [ ] **Step 6: Run** `/opt/homebrew/bin/bash src/test.bash | grep -v '^ok'` — Expected: no FAIL. If `old2` appears or texts are off by one, `fc` numbering differs from `HISTCMD` after loading `HISTFILE`: compute the offset in `_how_to_hist_text` from `history 1` vs `HISTCMD`, rerun.

- [ ] **Step 7: Commit**

```bash
git add src/how-to.bash src/test.bash
git commit -m "bash: recent commands and exit statuses as context"
```

---

### Task 3: Docs

**Files:**
- Modify: `docs/usage.md`, `CLAUDE.md`

- [ ] **Step 1: `docs/usage.md`:** in the configuration table, change the `HOW_TO_CONTEXT` default to `(os shell cwd git tools history)` and add `| HOW_TO_HISTORY | 5 | recent commands sent with their exit status; 0 turns it off |`. Add a `## Recent commands` section before `## Progress indicator`: the `history:` example from the spec; only commands from this shell since sourcing; a command started with a space is never sent when `HIST_IGNORE_SPACE` (zsh) / `HISTCONTROL=ignorespace` (bash) is set; `HOW_TO_HISTORY=0` to turn off; bash prepends `_how_to_record` to `PROMPT_COMMAND` (keep it if you reassign `PROMPT_COMMAND`), and with `ignoredups` an immediate repeat keeps the first run's status.

- [ ] **Step 2: `CLAUDE.md`:** under Architecture, a paragraph on `_how_to_record` (prompt hook storing `(HISTCMD-1, $?)` in `_how_to_hist_num`/`_how_to_hist_rc`, first call after sourcing skipped) and `_how_to_context_history` (reads text with `fc` at call time, events `< HISTCMD`). Under bash conventions, one bullet: `_how_to_record` is prepended to `PROMPT_COMMAND` and returns the `$?` it saw.

- [ ] **Step 3: Run** both suites — Expected: no FAIL.

- [ ] **Step 4: Commit**

```bash
git add docs/usage.md CLAUDE.md
git commit -m "docs: recent-command context"
```
