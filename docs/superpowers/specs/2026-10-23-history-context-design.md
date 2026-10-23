# how-to recent-command context — Design

## Goal

Let requests refer to what the user just did ("fix that", "do the same for
staging") by sending the last few commands and their exit statuses with
every request:

```
$ make test
...
make: *** [test] Error 2
$ how-to fix that
```

The model sees, inside `<context>`:

```
history: [exit 0] cd ~/proj
history: [exit 2] make test
```

Success criteria:

- Works in every terminal, in both `src/how-to.zsh` and `src/how-to.bash`,
  with identical output.
- On by default with 5 commands; `HOW_TO_HISTORY` sets the count, `0` turns
  it off.
- Lines the shell keeps out of history (`HIST_IGNORE_SPACE` /
  `HISTCONTROL=ignorespace`, `HISTIGNORE`, `zshaddhistory`) are never sent.
  how-to adds no filtering rules of its own; it reads history after the shell
  has filtered it.
- The `how-to` call itself is never sent.

## Scope

- **In:** a `history` context provider and a status-recording prompt hook in
  both files, the `HOW_TO_HISTORY` variable, one sentence in
  `HOW_TO_SYSTEM_PROMPT`, `docs/usage.md`, `CLAUDE.md`, tests in both suites.
- **Out:** command output of any kind (terminal scrollback, `tee`/`script`
  capture, piping into `how-to`, re-running commands), secret redaction,
  commands from other sessions.

## What the model sees

- One `history: [exit <n>] <command>` line per command, oldest first, so the
  last line is the most recent command.
- At most `HOW_TO_HISTORY` lines (default `5`). `0`, empty, or a non-number
  prints nothing.
- Only commands this shell recorded a status for: lines imported from other
  sessions (zsh `SHARE_HISTORY`), loaded from `HISTFILE`, or run before
  sourcing are left out.
- A command longer than 500 characters is cut to its first 500 followed by
  `…`. Each newline in a multi-line command is written as the two characters
  `\n`, so every entry stays on one line.
- `HOW_TO_SYSTEM_PROMPT` gains one line, byte-identical in both files, before
  the `HOWTO_FAIL` instructions:
  `"history:" lines are the user's latest commands, oldest first; "that"/"it" usually means the last one.`

## Recording statuses

Neither shell keeps past exit statuses, so a prompt hook records them, keyed
by history event number. Command text is never stored by the hook; it is
read from history when `how-to` runs.

Observed behavior both designs rely on (bash 5, `zsh -f`):

- In a prompt hook, `$HISTCMD` is the number the *next* command will get;
  the command that just finished is `HISTCMD - 1`.
- During a command (including inside `$(...)`), `$HISTCMD` is that command's
  own number.
- zsh: a line kept out of history by `HIST_IGNORE_SPACE` still holds an event
  number until the next line is entered, which reuses it.
- bash: a line dropped by `HISTCONTROL`/`HISTIGNORE` gets no number;
  `HISTCMD` does not advance.

State, in both shells: two global arrays, `_how_to_hist_num` and
`_how_to_hist_rc`, appended in step and trimmed to the newest 100 entries.
Recording to an event number that is already the last entry replaces that
entry instead of appending.

The first hook call after sourcing records nothing: at that prompt,
`HISTCMD - 1` is the last line loaded from `HISTFILE` (or the `source`
command), and `$?` is whatever the rc file left, not that command's status.
A global `_how_to_hist_ready`, unset by sourcing, marks that the first call
has happened.

### zsh

`_how_to_record` is added with `autoload -Uz add-zsh-hook; add-zsh-hook
precmd _how_to_record` (no duplicate on re-source), only in interactive
shells. On every prompt it records `$?` for event `HISTCMD - 1`, always:

- After a space-prefixed line, the entry for its number is overwritten when
  the next command, which takes that number, finishes.
- An empty Enter keeps `$?`, so re-recording the same event is harmless.
- A repeat dropped by `HIST_IGNORE_DUPS` updates the earlier command's
  status, which is the newer result for the same text.

The hook must see the command's `$?`. If another `precmd` function running
before it can change `$?`, it is moved to the front of `precmd_functions`;
the implementation verifies this with a test.

### bash

`_how_to_record` goes at the front of `PROMPT_COMMAND`, so it sees `$?`
before the user's hooks change it, and it returns the `$?` it saw. Array
`PROMPT_COMMAND` (bash 5.1+) gets it as element 0; a string gets
`_how_to_record` plus a newline prepended. Only in interactive shells, and
only once across re-sourcing, matching the existing `_how_to_restore_glob`
install.

It records only when `HISTCMD - 1` differs from the last recorded event
number, so a line bash dropped from history never overwrites the previous
command's status. Known limitation: with `ignoredups`, an identical command
repeated right away keeps the first run's status.

With history off (`set +o history`, `HISTSIZE=0`), `HISTCMD` never advances,
nothing is recorded and the provider prints nothing.

## The provider

`_how_to_context_history`, appended to the default `HOW_TO_CONTEXT`
(`os shell cwd git tools history`):

1. Return if `HOW_TO_HISTORY` is not a positive integer or nothing is
   recorded.
2. Take the recorded events with number below the current `$HISTCMD` (this
   drops the `how-to` call), newest last, and keep the last
   `HOW_TO_HISTORY`.
3. For each, read the text with `fc -ln <n> <n>` (bash: strip the leading
   whitespace `fc` adds). Skip the event if that fails or the text is empty.
4. Escape newlines, truncate, print `history: [exit <rc>] <text>`.

Conventions as for the other providers: zsh functions start with
`emulate -L zsh`; bash functions start with `local -`, use
`local IFS=$' \t\n'` when splitting, and work under `set -euo pipefail`,
`failglob`, `nocasematch` and an odd `IFS`. `fc` is a builtin and needs no
`command`.

## Configuration

`HOW_TO_HISTORY`, default `5`, set only when unset (zsh `(( ${+VAR} )) ||`,
bash `declare -p VAR &>/dev/null ||`), so it works as a prefix assignment
(`HOW_TO_HISTORY=0 how-to ...`) and survives re-sourcing. Removing `history`
from `HOW_TO_CONTEXT` also turns the provider off; the hook still records.

## Docs

- `docs/usage.md`: `HOW_TO_HISTORY` row and the new `HOW_TO_CONTEXT` default
  in the configuration table; a short section on recent-command context:
  what is sent, that starting a command with a space keeps it out when
  `HIST_IGNORE_SPACE` / `HISTCONTROL=ignorespace` is set, how to turn it off,
  and that bash prepends `_how_to_record` to `PROMPT_COMMAND`.
- `CLAUDE.md`: the provider and hook under Architecture; the bash hook
  under bash conventions.

## Testing

Unit tests, both suites (arrays set directly, `HISTCMD`-dependent paths
driven through the arrays and a stubbed history where needed):

- Order oldest-first, `HOW_TO_HISTORY` limit, `0`/empty/non-number prints
  nothing.
- Events at or above the current event are skipped.
- 500-character cut with `…`; multi-line command printed with `\n`.
- Event whose text can't be read is skipped.
- Recording: first call after sourcing records nothing, replace-on-same-event,
  trim to 100, bash skip-on-unchanged.
- zsh under `setopt ksharrays`; bash under the hostile-options set.
- Sourcing twice installs the hook once (zsh `precmd_functions`, bash
  `PROMPT_COMMAND` string and array forms); `_how_to_record` preserves `$?`.
- Prompt byte-identity test still passes with the new sentence.

pty tests (expect), both suites: in an interactive shell with ignore-space
on, run `true`, `false`, ` echo secret`, an empty Enter, then `how-to x` with
a stub provider that saves its stdin. The saved context contains exactly
`history: [exit 0] true` then `history: [exit 1] false` among its history
lines, and no `secret` and no `how-to`.
