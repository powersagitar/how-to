# how-to for bash — Design

## Goal

`how-to <request>` works in interactive bash exactly as it does in zsh: the
command lands on the next prompt, unexecuted, ready to edit and run.

```
$ how-to count lines of code in this repo
$ tokei .█
```

Success criteria:

- Same UX, pipeline, extension points, config variables, defaults, messages,
  and exit codes as `src/how-to.zsh`.
- One sourced file, no runtime beyond bash ≥ 4.4 and the provider's CLI.
- The zsh file is not changed.
- Correct under hostile user settings (`set -u`, `set -e`, `failglob`,
  `nocasematch`, odd `IFS`), as the zsh file is under `ksharrays`.

This replaces the "Later: bash ... `read -e -i`" note in
`2026-10-10-how-to-design.md`. `read -e -i` runs the command inside the
function (no normal history entry, `eval` semantics), so it is not used.

## Scope

- **In:** interactive bash ≥ 4.4 on Linux and macOS (Homebrew bash).
- **Out:** bash < 4.4 (incl. macOS `/bin/bash` 3.2), a hotkey widget, a
  history-based fallback, shared code between the zsh and bash files.

## Minimum version: 4.4

- 4.0: `bind -x` sets `READLINE_LINE` / `READLINE_POINT`.
- 4.4: `local -` (function-scoped `set` options, the closest thing to
  `emulate -L`).

On an older bash, sourcing prints
`how-to: requires bash >= 4.4 (this is $BASH_VERSION)` to stderr and returns
without defining anything, so a shared `.bashrc` stays usable.

## Layout

```
src/how-to.bash     the bash tool (sourced from ~/.bashrc)
src/test.bash       test script: `bash src/test.bash`
```

## Putting the command on the prompt

Bash has no `print -z`, and `TIOCSTI` is disabled. The terminal is made to
"type" a key sequence that readline maps to a shell function:

1. `_how_to_push "$cmd"` stores `$cmd` in `_how_to_pending`, saves the tty
   settings (`command stty -g`), sets `command stty -echo -icanon`, and writes
   the Device Status Report query `\e[5n` to `/dev/tty`.
2. The terminal replies `\e[0n` ("OK") on the tty's input. `_how_to_push`
   polls `read -t 0 </dev/tty` (checks without consuming) every 10 ms, for up
   to 1 s, until the reply is buffered, then restores the saved tty settings.
   - Without `-echo`, the cooked tty would echo the reply as `^[[0n` above
     the prompt, because it arrives before readline switches to raw mode.
   - Without `-icanon`, `read -t 0` can't see input that has no newline.
   - If no reply arrives within 1 s, `_how_to_pending` is cleared and the
     command is printed to stdout so it isn't lost.
3. Once readline is reading the next prompt it sees `\e[0n`, bound at
   source time with
   `bind -m emacs -x '"\e[0n": _how_to_insert'` (and the same for
   `vi-insert`).
4. `_how_to_insert` sets `READLINE_LINE=$_how_to_pending`,
   `READLINE_POINT=${#READLINE_LINE}`, and clears `_how_to_pending`. If nothing
   is pending it does nothing, so a stray DSR reply is harmless.

A spike (bash 5.3 on macOS, pty driven by `expect` acting as the terminal)
confirmed:
- Steps 3–4 work whether the reply arrives at an idle prompt or early, while
  the function is still running: the bytes wait in the tty buffer until
  readline reads them, including across the `-icanon` → `icanon` restore.
- With step 1–2's `stty` handling, the reply is not echoed for an immediate
  reply or a 300 ms one (SSH-like). With no reply, the wait times out after
  about 1 s and the tty is restored.
- A check in the user's own terminal showed the plain trick echoes
  `^[[0n`, which is what motivated the `stty` handling.

Bindings are installed only in interactive shells (`[[ $- == *i* ]]`). When
the shell isn't interactive or `/dev/tty` can't be opened, `_how_to_push`
prints the command to stdout instead.

No `history -s` fallback: when the DSR trick works, pressing Enter would put
the command in history twice, and removing the extra entry is unreliable
under `HISTCONTROL`. Instead the docs give a one-line check that the terminal
answers DSR (xterm, iTerm2, Terminal.app, kitty, VS Code, and tmux all do):

```
s=$(stty -g); stty -echo; printf '\e[5n'; IFS= read -rs -t1 -d n r && echo ok || echo 'no DSR reply'; stty "$s"
```

## Globbing in requests

zsh uses `alias how-to='noglob how-to'`. Bash equivalent:

```bash
alias how-to='_how_to_f=$-; set -f; _how_to_main'
```

Bash expands each command of a list only when it reaches it, so `set -f`
takes effect before `_how_to_main`'s arguments are expanded. `_how_to_main`
first restores globbing (`set +f`) if `_how_to_f` did not contain `f`, then
runs the pipeline. `how-to find *.log` therefore sends `*.log` literally.

## Pipeline

Same as zsh: `_how_to_main` → `_how_to_context` →
`_how_to_provider_${HOW_TO_PROVIDER:-claude}` → `_how_to_clean` →
`HOWTO_FAIL` check → `_how_to_push`. Same error table, messages, and exit codes
(usage → 2, unknown provider / provider failed / no command returned /
`HOWTO_FAIL` reason → 1). `HOWTO_FAIL:` may appear on any line of the cleaned
output; only the reason is printed.

## Interfaces (unchanged, bash syntax)

- Model provider: `_how_to_provider_<name>`; `$1` system prompt, stdin
  message, stdout reply, non-zero on failure.
- Context provider: `_how_to_context_<name>` prints `key: value` lines; run in
  `HOW_TO_CONTEXT` order; missing, failing (stderr suppressed), or empty
  providers are skipped.
- Built-in claude provider runs
  `command claude --print --tools "" --no-session-persistence --system-prompt "$1"`
  plus `HOW_TO_CLAUDE_ARGS` (default `--model haiku`). Never `--bare`.

## Config

Same variables and defaults: `HOW_TO_PROVIDER`, `HOW_TO_CLAUDE_ARGS`,
`HOW_TO_CONTEXT=(os shell cwd git tools)`, `HOW_TO_TOOLS=(...)` (same list),
`HOW_TO_SYSTEM_PROMPT` (byte-identical text). Each is set only if unset
(`[[ -v VAR ]] ||`), so re-sourcing keeps user values. List variables accept
arrays or space-separated strings: split with
`read -ra list <<< "${VAR[*]}"` under a local default `IFS`.

## Built-in context providers

| name    | output |
|---------|--------|
| `os`    | `os: $(command uname -sr)` |
| `shell` | `shell: bash $BASH_VERSION` |
| `cwd`   | `cwd: $PWD`; `files:` first 30 entries incl. dotfiles (glob with local `nullglob dotglob`, excluding `.`/`..`) |
| `git`   | `git_root:` from `command git rev-parse --show-toplevel`; `git_branch:` from `symbolic-ref --short -q HEAD`, omitted when detached; nothing outside a repo |
| `tools` | `tools:` entries of `HOW_TO_TOOLS` found by `type -P` (PATH only, like zsh `$commands`) |

## `_how_to_clean`

Same rules as zsh, in plain bash (no `extglob`): if a line starting with
optional whitespace then ```` ``` ```` exists, keep only the lines up to the
next such line, removing the opening fence's leading whitespace from each;
strip trailing whitespace per line; drop leading/trailing blank lines; strip
leading whitespace from the first line.

## Bash conventions

- Every function starts with `local -`; functions that split words also
  `local IFS=$' \t\n'`. Functions needing `shopt` options save `shopt -p`
  output and restore it before returning.
- External programs via `command` (`command git`, `command uname`,
  `command claude`).
- Functions are defined so the file re-sources cleanly; the alias is defined
  last (after all function definitions, so `how-to` inside the file is never
  alias-expanded).
- No reliance on user options: code is correct under `set -euo pipefail`,
  `shopt -s failglob nocasematch nullglob`, and a non-default `IFS`.

## Testing

`src/test.bash`, run with `bash src/test.bash`; flat
`assert_eq "<name>" expected actual`; exits 1 on any failure; exits 2 with a
clear message if bash < 4.4.

Mirrors the zsh suite group by group: clean, ctx (order, skip, preset kept,
scalar split), built-in providers (cwd path with space, 30 cap, git
in/out/no commits/detached, tools, os, shell, ignoring same-named shell
functions), e2e with a `stub` provider writing to `$tmp` and a stubbed
`_how_to_push`, error paths, claude argv via a fake `claude` on `PATH`,
re-source.

Bash-specific:

- Option-leak tests: key paths re-run with `set -u`, `set -e`,
  `shopt -s failglob nocasematch`, and `IFS=:`.
- Glob alias: `how-to find all *.nomatch` sends the literal request, and
  globbing is still enabled afterwards (and still disabled if it was).
- System prompt identical to zsh's, read via
  `zsh -c 'source src/how-to.zsh; print -rn -- $HOW_TO_SYSTEM_PROMPT'`;
  skipped with a note if `zsh` is absent.
- `_how_to_push` falls back to stdout when non-interactive.
- pty tests with `expect` (skipped with a note if `expect` is absent):
  interactive bash sources the file and runs `how-to` with a stub provider.
  - Reply: expect answers `\e[5n` with `\e[0n` (immediately and after
    300 ms), presses Enter, and checks that the stubbed command ran and that
    `\e[0n` never appeared in the output.
  - No reply: the command is printed, nothing is inserted, and echo works
    again afterward (a typed command is echoed).

Automated tests make no network calls; the real claude provider is checked
manually once.

## Docs

- `docs/usage.md`: bash install (`source .../how-to.bash` in `~/.bashrc`),
  bash ≥ 4.4 minimum (macOS: `brew install bash`, since `/bin/bash` is 3.2),
  the DSR check, quoting notes for bash, bash provider/context examples.
- `CLAUDE.md`: bash test command and bash conventions.
- `2026-10-10-how-to-design.md`: Scope "Later" bullet points to this spec.
