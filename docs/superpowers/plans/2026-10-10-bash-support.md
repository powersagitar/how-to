# how-to for bash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sourced bash file `src/how-to.bash` giving `how-to <request>` the same behavior as the zsh version, with the command placed on the next readline prompt via a DSR reply bound with `bind -x`.

**Architecture:** One file, `src/how-to.bash`, ports `src/how-to.zsh` section by section: clean, context, providers, entry point, push. `_how_to_push` stores the command, turns tty echo off, writes `\e[5n`, waits for the reply to be buffered, and then restores the tty. The terminal's `\e[0n` reply is bound to `_how_to_insert`, which sets `READLINE_LINE`. `src/test.bash` mirrors `src/test.zsh` and adds option-leak and pty tests.

**Tech Stack:** bash ≥ 4.4, `expect` (optional, pty test only). No other dependencies.

**Spec:** `docs/superpowers/specs/2026-10-10-bash-support-design.md`

## Global Constraints

- bash ≥ 4.4. On older bash, sourcing prints `how-to: requires bash >= 4.4 (this is $BASH_VERSION)` to stderr and `return`s without defining anything.
- `src/how-to.zsh` and `src/test.zsh` are not modified.
- Same messages and statuses as zsh: `usage: how-to <what you want to do>` → 2; `how-to: unknown provider '<name>'`, `how-to: provider failed`, `how-to: no command returned`, `<HOWTO_FAIL reason>` → 1. All on stderr.
- Same defaults: `HOW_TO_CONTEXT=(os shell cwd git tools)`, `HOW_TO_TOOLS=(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)`, `HOW_TO_CLAUDE_ARGS` default `--model haiku`, `HOW_TO_SYSTEM_PROMPT` byte-identical to zsh's. Each is set only if unset (`[[ -v VAR ]] ||`).
- Claude provider: `command claude --print --tools "" --no-session-persistence --system-prompt "$1"` + split `HOW_TO_CLAUDE_ARGS`. Never `--bare`.
- Every function starts with `local -`. Splitting uses a local `IFS=$' \t\n'`. Any function that pattern-matches or globs saves `shopt -p nocasematch nullglob dotglob failglob extglob` into a local, sets what it needs, and `eval`s the saved value before every return.
- External programs go through `command`. Tool detection uses `type -P`.
- List variables (`HOW_TO_CONTEXT`, `HOW_TO_TOOLS`, `HOW_TO_CLAUDE_ARGS`) are split with `read -ra list <<< "${VAR[*]}"`, so arrays and space-separated strings both work.
- Run tests with a bash ≥ 4.4. On this Mac, `bash` on `PATH` is 3.2: use `/opt/homebrew/bin/bash src/test.bash`. `src/test.bash` exits 2 with `test.bash: requires bash >= 4.4` on older bash.

## Review Focus

1. **Backslashes, `%` and quotes in the returned command** (`printf %s\n a\tb`): expect the prompt to show it byte for byte. Neither `_how_to_push` nor `_how_to_insert` may interpret escapes (Task 4 test).
2. **Sourcing from a non-interactive shell** (`bash -c 'source how-to.bash'`, e.g. scp/rsync reading `.bashrc`): expect no output and no `bind` warnings (Task 4 test).
3. **Multi-line command** (`a \` newline `  && b`): expect both lines on the prompt, with Enter running them (Task 4 pty test).
4. **Error paths with the glob alias** (`how-to` with no args, an unknown provider, `HOWTO_FAIL`): expect globbing still on afterward, because restore happens before any early return (Task 3 test).
5. **vi mode** (`set -o vi`): expect insertion to work, i.e. a `\e[0n` binding in the `vi-insert` keymap (Task 4 test).

---

### Task 1: Harness, version guard, config, and `_how_to_clean`

**Files:**
- Create: `src/how-to.bash`
- Create: `src/test.bash`

**Interfaces:**
- Produces: `assert_eq <name> <expected> <actual>` (prints `ok   <name>`, or `FAIL <name>` with `expected:`/`actual:` shown via `${x@Q}`, and increments `failures`); `here` (dir of test.bash); `tmp` (temp dir removed on EXIT); `_how_to_clean` (stdin → cleaned stdout, status 0); config variables as in Global Constraints.

- [ ] **Step 1: Write the failing tests** in `src/test.bash`: shebang `#!/usr/bin/env bash`, the version guard (exit 2), `here=$(cd "${BASH_SOURCE%/*}" && pwd)`, `source "$here/how-to.bash"`, `assert_eq`, and the `tmp`/trap setup. Then port every `clean:` assertion from `src/test.zsh` (fence, fence+lang, blank lines, trailing ws, multi-line, leading ws trimmed on first line, prose around fence, indented fence, indented fence dedents) with the same names and values, using `printf '%s\n' $'...' | _how_to_clean`. Add:
  - `ctx: default list` → `os shell cwd git tools` from `"${HOW_TO_CONTEXT[*]}"`
  - `ctx: preset kept` → `os` from `"$(HOW_TO_CONTEXT=(os); source "$here/how-to.bash"; echo "${HOW_TO_CONTEXT[*]}")"`
  - `prompt: matches zsh` → compare `"$HOW_TO_SYSTEM_PROMPT"` with `"$(zsh -c 'source '"$here"'/how-to.zsh; print -rn -- $HOW_TO_SYSTEM_PROMPT')"`, or print `skip prompt: matches zsh (no zsh)` when `type -P zsh` fails
  - `old bash refused` → when `/bin/bash` reports major version < 4, expected stderr `how-to: requires bash >= 4.4 (this is <its BASH_VERSION>)`, and `type _how_to_clean` fails inside it. Otherwise print `skip`.
  - End the file with `exit $(( failures > 0 ))`.

- [ ] **Step 2: Run** `/opt/homebrew/bin/bash src/test.bash`. Expected: it fails because `src/how-to.bash` doesn't exist.

- [ ] **Step 3: Implement** in `src/how-to.bash`: a header comment as in zsh, the version guard (`(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) || { ...; return 1; }`), config defaults (system prompt text copied exactly from `src/how-to.zsh`), and `_how_to_clean` following the spec's rules. Use `mapfile -t lines` and loops. Match the fence with `[[ $l =~ ^([[:space:]]*)\`\`\` ]]` and dedent with `${l#"$indent"}`.

- [ ] **Step 4: Run** the tests. Expected: everything `ok`, exit 0.

- [ ] **Step 5: Commit** `git add src/how-to.bash src/test.bash && git commit -m "bash: config, version guard, output cleaning"`

### Task 2: Context assembly and built-in context providers

**Files:**
- Modify: `src/how-to.bash`, `src/test.bash`

**Interfaces:**
- Consumes: Task 1 harness.
- Produces: `_how_to_context` (prints `<context>`, then each provider's non-empty output, then `</context>`), plus `_how_to_context_os|shell|cwd|git|tools`.

- [ ] **Step 1: Write the failing tests.** Port from `src/test.zsh` with the same names and values: `ctx: order+skip`, `ctx: scalar list split`, `cwd: path with space`, `cwd: files capped` (30), `git: silent outside repo`, `git: root in repo` (root = parent of `$here`), `tools: only installed` (`HOW_TO_TOOLS=(bash definitely-not-a-tool-xyz)` → `tools: bash`), `tools: scalar list split`, `os`, `os: ignores uname function`, `git: ignores git function`, `git: branch with no commits`, `git: no branch when detached`. Change `shell` to expect `shell: bash $BASH_VERSION`. Add:
  - `cwd: dotfiles included` → in a dir containing only `.hidden`, line 2 is `files: .hidden`
  - `cwd: empty dir` → only the `cwd:` line
  - `ctx: hostile opts` → the `order+skip` case run inside `( set -euo pipefail; shopt -s failglob nocasematch nullglob; IFS=:; ... )` gives the same output
  - `cwd: hostile opts` → `cwd: empty dir` under the same settings gives the same output

- [ ] **Step 2: Run.** Expected: the new tests FAIL (`command not found`).

- [ ] **Step 3: Implement** the six functions as the spec's table describes. Providers run with `2>/dev/null`. A failure (`out=$(...) || continue`) or empty output is skipped. Missing providers are detected with `declare -F`. `cwd` uses a local `shopt -s nullglob dotglob` and `shopt -u failglob`, `files=(*)`, and `"${files[@]:0:30}"`. Under `set -u`, use `${var-}` wherever a value may be unset.

- [ ] **Step 4: Run.** Expected: all `ok`.

- [ ] **Step 5: Commit** `git commit -am "bash: context providers"`

### Task 3: Claude provider, entry point, and glob alias

**Files:**
- Modify: `src/how-to.bash`, `src/test.bash`

**Interfaces:**
- Consumes: `_how_to_context`, `_how_to_clean`.
- Produces: `_how_to_provider_claude`, `_how_to_main "$@"` (the pipeline, ending in `_how_to_push "$cmd"`), `alias how-to='_how_to_f=$-; set -f; _how_to_main'` defined last in the file, and `shopt -s expand_aliases` in tests only.
- Note: a default `_how_to_push` is defined in Task 4. Here, tests stub it as `_how_to_push() { pushed=$1; }`.

- [ ] **Step 1: Write the failing tests.** Port the zsh e2e and error blocks with the same names and values. The stub provider writes `$1` to `$tmp/sys` and stdin to `$tmp/in`, prints `$stub_out`, and returns `${stub_rc:-0}`. `run()` calls `_how_to_main "$@"`. Port: e2e pushed/rc/request/sys/ctx block first, literal request, no args rc/msg, unknown rc/msg, prov fail rc/msg, empty rc/msg, fail rc/msg/not pushed, fenced fail msg/not pushed, fail on later line, claude argv, claude args override, and `re-source ok` (sourcing again prints nothing). Add:
  - `noglob request` → after `touch "$tmp/x.nomatch"` and `cd "$tmp"`, the line `how-to find all *.nomatch files` is processed via `eval` (aliases expand at parse time) and the last line of `$tmp/in` is `Request: find all *.nomatch files`
  - `glob restored` → `[[ $- != *f* ]]` holds after that call
  - `glob kept off` → after `set -f`, an alias call leaves `f` in `$-`; then `set +f`
  - `glob restored on error` → for each of no args, `HOW_TO_PROVIDER=nope`, and the `HOWTO_FAIL` stub, called via the alias, `$-` has no `f`
  - `e2e: hostile opts` → `stub_out=ls` run under `set -euo pipefail; shopt -s failglob nocasematch; IFS=:` pushes `ls`; write it to `$tmp/hostile` from a subshell
  - `fail: case-sensitive under nocasematch` → `stub_out='howto_fail: x'` with `nocasematch` set pushes `howto_fail: x`

- [ ] **Step 2: Run.** Expected: the new tests FAIL.

- [ ] **Step 3: Implement.** The first lines of `_how_to_main`, before `local -`, are `[[ ${_how_to_f-} == *f* ]] || set +f; unset _how_to_f`. They come first so that `local -` captures the restored state and every return path keeps it. Then follow the zsh `how-to` body step by step. `HOWTO_FAIL` detection is a loop over cleaned lines with `[[ $l == HOWTO_FAIL:* ]]` (with `nocasematch` off); the reason is `${l#HOWTO_FAIL:}` with one leading space removed. The provider is called as `printf '%s\n' "$msg" | "$fn" "$HOW_TO_SYSTEM_PROMPT"`.

- [ ] **Step 4: Run.** Expected: all `ok`.

- [ ] **Step 5: Commit** `git commit -am "bash: provider, entry point, glob alias"`

### Task 4: Push, readline insertion, and pty test

**Files:**
- Modify: `src/how-to.bash`, `src/test.bash`

**Interfaces:**
- Consumes: `_how_to_main`.
- Produces: `_how_to_pending` (global string); `_how_to_push "$cmd"`:
  - If `[[ $- == *i* ]]` and `saved=$(command stty -g </dev/tty 2>/dev/null)` succeeds: store the command in `_how_to_pending`, run `command stty -echo -icanon </dev/tty`, and `printf '\e[5n' >/dev/tty`.
  - Then poll `read -t 0 </dev/tty` up to 100 times with `command sleep 0.01` between tries, and restore with `command stty "$saved" </dev/tty`.
  - If the reply never showed up, clear `_how_to_pending` and fall through to printing.
  - Otherwise (non-interactive, no tty, or no reply), `printf '%s\n' "$1"`. Also `_how_to_insert` (no-op when `_how_to_pending` is empty; otherwise `READLINE_LINE=$_how_to_pending; READLINE_POINT=${#READLINE_LINE}; _how_to_pending=`) and, only when `[[ $- == *i* ]]`, `bind -m emacs -x '"\e[0n": _how_to_insert'` plus the same for `-m vi-insert`.
- Note: tests source the file again in a fresh subshell so they get the real `_how_to_push`, not Task 3's stub.

- [ ] **Step 1: Write the failing tests.**
  - `push: non-interactive prints` → `$(source "$here/how-to.bash"; _how_to_push 'printf %s\n a\tb')` equals `printf %s\n a\tb`
  - `insert: verbatim` → set `_how_to_pending='printf %s\n a\tb'`, call `_how_to_insert`, and expect `READLINE_LINE` to be that string, `READLINE_POINT` 16, and `_how_to_pending` empty
  - `insert: no-op when empty` → `READLINE_LINE=keep`, call `_how_to_insert`, and `READLINE_LINE` is still `keep`
  - `source: silent non-interactive` → `"$BASH" -c "source '$here/how-to.bash'" 2>&1` is empty
  - `bind: emacs` and `bind: vi-insert` → `"$BASH" --norc -ic "source '$here/how-to.bash'; bind -m emacs -X"` contains `"\e[0n": "_how_to_insert"`, and the same for vi-insert
  - pty tests: when `type -P expect` succeeds, generate an expect script in `$tmp/pty.exp`, parameterized by the stub output and the reply delay. Without `expect`, print `skip pty (no expect)`. The script spawns `$BASH --noprofile --norc -i`, sets `PS1='P> '`, sources the file, defines a stub provider, and runs `how-to x`. When `-ex "\033\[5n"` matches, it optionally sleeps, then sends `"\033\[0n"`, waits for `P> `, sends `\r`, and expects the marker. It prints `PTY-OK`, `PTY-FAIL`, or `PTY-ECHOED`; the last one fires if the captured output contains `\033[0n` (check with `string first`). Spike lessons: use `-ex` for escape-sequence matches, because glob patterns mangle `[`, and generate the `.exp` with the `$BASH` path substituted in.
    - `pty: inserted` → stub prints `echo INSERTED-$((6*7))`, reply immediately, expect `INSERTED-42`, result `PTY-OK`
    - `pty: slow reply` → same, but the reply comes after `sleep 0.3`, result `PTY-OK`
    - `pty: multi-line` → stub prints `echo A \` / `  && echo B-$((1+1))`, expect `B-2`, result `PTY-OK`
    - `pty: no reply` → never answer. Expect the stub command printed on its own line, then `P> `. Then send `echo TYPED\r` and expect the literal `echo TYPED` echoed back (tty restored) followed by `TYPED`, result `PTY-OK`. This takes about 1 s.

- [ ] **Step 2: Run.** Expected: the new tests FAIL.

- [ ] **Step 3: Implement** `_how_to_push`, `_how_to_insert`, and the guarded `bind` calls in `src/how-to.bash`, placed before the alias.

- [ ] **Step 4: Run** the full suite. Expected: all `ok`, exit 0. Then also run `zsh src/test.zsh` to confirm it's untouched: all `ok`.

- [ ] **Step 5: Commit** `git commit -am "bash: readline insertion via DSR reply"`

### Task 5: Docs

**Files:**
- Modify: `docs/usage.md`, `CLAUDE.md`, `docs/superpowers/specs/2026-10-10-how-to-design.md` (Scope "Later" bullet), `README.md` (mention bash if it says zsh-only)

- [ ] **Step 1: `docs/usage.md`.** Add a "bash" install subsection: `source /path/to/how-to/src/how-to.bash` in `~/.bashrc`; requires bash ≥ 4.4 (macOS `/bin/bash` is 3.2, so use `brew install bash`); explain how the command reaches the prompt (DSR reply) and give the check `s=$(stty -g); stty -echo; printf '\e[5n'; IFS= read -rs -t1 -d n r && echo ok || echo 'no DSR reply'; stty "$s"`; if the terminal doesn't reply within 1 s, or the shell isn't interactive, the command is printed instead. Quoting: `how-to` disables globbing for the request, like zsh. Give a bash example of the ollama provider (`_how_to_provider_ollama() { { printf '%s\n' "$1"; cat; } | ollama run llama3.2; }`) and of the docker context provider. Mention that `HOW_TO_CONTEXT+=(docker)` works in both shells.
- [ ] **Step 2: `CLAUDE.md`.** Add `/opt/homebrew/bin/bash src/test.bash` (any bash ≥ 4.4) to Commands. Add a "bash conventions" list: `local -`, the shopt save/restore rule, `command`, the alias and its restore-first rule, the DSR push and `_how_to_insert`, and that the system prompt must stay identical across both files (tested).
- [ ] **Step 3: Old spec.** Replace the bash "Later" bullet with a pointer to `2026-10-10-bash-support-design.md`.
- [ ] **Step 4: Verify** both suites pass: `zsh src/test.zsh; /opt/homebrew/bin/bash src/test.bash`, exit 0 each.
- [ ] **Step 5: Commit** `git commit -am "docs: bash support"`
