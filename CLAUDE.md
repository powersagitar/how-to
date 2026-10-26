# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`how-to <request>` is a shell function for zsh and bash. It asks an LLM for a
single shell command and places it on the user's prompt, unexecuted. There are
two independent files with the same pipeline: `src/how-to.zsh` (sourced from
`~/.zshrc`, pushes with `print -rz`) and `src/how-to.bash` (sourced from
`~/.bashrc`, bash >= 4.4, pushes via a terminal DSR reply; see "bash
conventions" below). They must be sourced, not run as scripts, because a child
process can't write to the parent shell's line editor. User docs are in
`docs/usage.md`, developer docs in `docs/development.md`; the design spec is in
`docs/superpowers/specs/`.

## Commands

```
zsh src/test.zsh                    # full suite; exit 1 if any FAIL
zsh src/test.zsh | grep -v '^ok'    # show only failures
zsh src/test.zsh | grep 'git:'      # one group (no runner; filter by test name)
/opt/homebrew/bin/bash src/test.bash # bash suite; any bash >= 4.4 (macOS /bin/bash is 3.2)
```

CI (`.github/workflows/test.yml`, every push) runs both suites on Ubuntu with
expect: zsh once, and bash 4.4.18 and 5.0 (built from source) plus the runner's
/bin/bash. A failing pty test prints the end of its transcript.

Pushing a tag `vX.Y.Z` runs `.github/workflows/release.yml` instead: it calls
`test.yml` (`workflow_call`), and if every job passes it creates a GitHub
release with `how-to-X.Y.Z.tar.gz` and its `.sha256`. The Homebrew formula
lives only in `powersagitar/homebrew-tap`, whose daily autobump workflow opens
a pull request for each new release. Its `test do` sources both files (bash via
Homebrew's bash, since macOS has 3.2). Before tagging, set `_how_to_version`
(top of both source files) to `X.Y.Z`; the release fails if either differs
from the tag.

There is no build or lint step. Tests are flat `assert_eq "<name>" expected actual` calls.

## Architecture

Every call runs one pipeline, `how-to` → `_how_to_context` → provider →
`_how_to_clean` → `HOWTO_FAIL` check → `_how_to_push`. The two extension
points are discovered by function name. Leading words are parsed as options
first: `-v`/`--version` prints `how-to $_how_to_version` and returns 0, `--`
ends options, and any other `-word` prints `how-to: unknown option '<word>'`
plus usage and returns 2. `_how_to_version` is a plain variable, assigned
unconditionally (not a config variable), and must match in both files and the
release tag.

- **Model providers** are `_how_to_provider_<name>`, selected by
  `HOW_TO_PROVIDER` (default `claude`). `$1` is the system prompt, stdin is
  the message, stdout is the raw reply, and failure is a non-zero exit. The
  claude provider runs `command claude --print --tools "" --no-session-persistence --system-prompt "$1"`
  plus `HOW_TO_CLAUDE_ARGS` (default `--model haiku`). **Never add `--bare`**,
  because it breaks OAuth login.
- **Context providers** are `_how_to_context_<name>`, run in the order given by
  `HOW_TO_CONTEXT` (an array or a space-separated string; zsh splits with
  `${=...}`, bash with `read -ra`).
  Each prints `key: value` lines into a `<context>` block. Missing, failing, or
  empty providers are skipped silently.

Exit statuses for the `history` context provider come from a prompt hook,
`_how_to_record` (zsh `precmd`, bash `PROMPT_COMMAND`). It stores
`(event, $?, text)` in `_how_to_hist_num`, `_how_to_hist_rc` and
`_how_to_hist_txt` (newest 100, via `_how_to_hist_add`); the first call after
sourcing is skipped (`_how_to_hist_ready`). zsh records only when a command
ran since the last prompt (preexec `_how_to_hist_ran` sets
`_how_to_hist_flag`), so Ctrl-C at an empty prompt doesn't overwrite a
status. `_how_to_context_history` reads command text at call time
(`_how_to_hist_text`: zsh `fc`, bash `history -p "!N"`) for recorded events
below the current one. `_how_to_hist_txt` is the text stored at record time:
an event whose current text differs (history renumbered) is skipped.

When there's no command to give, the model replies `HOWTO_FAIL: <reason>`.
This line can appear anywhere in the reply, including inside a fence, and only
the reason is shown on stderr. `_how_to_clean` keeps only the inside of the
first code fence (the fence may be indented, and its content is dedented to
match), then trims the result.

The provider call is wrapped as `{ raw=$(… 3>&-); rc=$? } 3> >(_how_to_spin)`.
`_how_to_spin` reads that never-written pipe, draws a frame on each 0.1 s
timeout (off when `HOW_TO_SPINNER=0`, `TERM=dumb` or stderr isn't a tty), and
exits at EOF without writing; the parent then erases with `\r\e[K`. bash
`wait`s only if `$!` changed, and times with `EPOCHREALTIME` (bash's `SECONDS`
ticks on wall-clock seconds).

Config variables are only set when unset (zsh `(( ${+VAR} )) ||`, bash
`declare -p VAR &>/dev/null ||`), so user values survive re-sourcing.

## zsh conventions (enforced by tests)

- Every function starts with `emulate -L zsh`. Tests re-run key paths under
  `setopt ksharrays` to catch leaked user options.
- Call external programs through `command` (`command git`, `command uname`) so
  user aliases and functions can't interfere. Don't put `builtin` in front of
  `local`/`typeset`, because it breaks array-assignment syntax.
- `how-to` is defined as `function how-to {` (so it re-sources cleanly) and
  aliased to `noglob how-to`.

## bash conventions (`src/how-to.bash`, enforced by `src/test.bash`)

- Same pipeline, names, messages and defaults as the zsh file; the entry
  function is `_how_to_main`. `HOW_TO_SYSTEM_PROMPT` must stay byte-identical
  across both files (tested against zsh).
- Every function starts with `local -`; functions that split or join words
  use `local IFS=$' \t\n'`. A function that pattern-matches or globs saves
  `shopt -p nocasematch nullglob dotglob failglob extglob`, sets what it
  needs, and `eval`s the saved value before returning. Code must work under
  `set -euo pipefail`, `failglob`, `nocasematch` and an odd `IFS` (tested).
- External programs go through `command`; tool detection uses `type -P`.
  Config is set only if unset with `declare -p VAR &>/dev/null ||` (not
  `[[ -v ]]`, which is false for an empty array).
- `alias how-to='_how_to_pre && _how_to_run'`, defined last. `_how_to_pre`
  saves `$-` in `_how_to_f`, sets `-f`, and snapshots `HOW_TO_*` (`declare -p`)
  so a prefix assignment, which only reaches `_how_to_pre`, applies to the
  call. `_how_to_run` does nothing unless `_how_to_f` is set (`cond || how-to`).
  Neither has `local -`. `_how_to_main` restores globbing *before* `local -`,
  and only when `_how_to_f` is set (a direct call leaves `-f` alone). If a
  request word fails to expand (e.g. `$1` under `set -u`), `_how_to_run` never
  runs; `_how_to_restore_glob`, appended once to `PROMPT_COMMAND` in
  interactive shells, undoes the `set -f` at the next prompt.
- `_how_to_push` stores the command in `_how_to_pending`, sets
  `stty -echo -icanon`, skips the query if input is already waiting
  (typeahead; prints instead), writes `\e[5n` to `/dev/tty`, polls
  `read -t 0` for up to 1 s, and restores the tty (in a subshell with an EXIT
  trap, so Ctrl-C restores it too); no reply → prints the command, and a
  silent timeout sets `_how_to_no_dsr=$SECONDS`, which skips the query for
  600 s. The terminal's `\e[0n` reply is bound (`bind -x`, emacs and
  vi-insert, only in interactive shells) to `_how_to_insert`, which unsets
  `_how_to_no_dsr` (a late reply proves the terminal answers) and, if
  `_how_to_pending` is set, sets `READLINE_LINE`.
- `_how_to_record` is prepended to `PROMPT_COMMAND` and returns the `$?` it
  saw. It starts with `local rc=$?` before anything else, an exception to the
  "starts with `local -`" rule (zsh does the same before `emulate -L zsh`).
- PROMPT_COMMAND functions (`_how_to_record`, `_how_to_hist_add`) have no
  `local -`, because on 4.4/5.0 it turns history back on in PROMPT_COMMAND.
- Event numbers come from `history 1`, not `HISTCMD` (which is 1 in
  PROMPT_COMMAND and `$(...)` on bash < 5.1). Command text uses
  `history -p "!N"`, not `fc` (5.1+ `fc -ln N N` lists from entry 1).
- If `_how_to_record` isn't first in `PROMPT_COMMAND`, it moves itself to the
  front once (`_how_to_hist_moved`), replacing other mentions with `:`. The
  install uses the array form only on 5.1+; before that only element 0 runs,
  so the hooks go into element 0.
- pty tests drive an interactive bash with `expect`. Use the unbraced
  `expect -ex $pat {...} timeout {...}` form (a one-line braced body is
  treated as a single pattern) and `-ex` for escape sequences.

## Testing notes

- Tests stub `_how_to_push` and use a `stub` provider. The provider runs in a
  pipeline subshell, so it writes what it captures to files in `$tmp` instead
  of setting variables.
- The hist tests stub the text readers (`_how_to_hist_text`, and in bash
  `_how_to_hist_last`) instead of driving real history.
- The claude provider is tested with a fake `claude` script prepended to
  `PATH`, which is possible because `command` bypasses functions, not `PATH`.
