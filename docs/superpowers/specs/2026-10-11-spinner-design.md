# how-to loading indicator — Design

## Goal

While the provider is working, show that `how-to` is alive and how long it
has been waiting, instead of sitting silent:

```
$ how-to count lines of code in this repo
/ thinking 3s
```

Success criteria:

- One style, chosen for portability: the ASCII line `| / - \` plus whole
  elapsed seconds. No Unicode glyphs, no SGR attributes; only `\r` and
  `\e[K` are sent to the terminal.
- Identical output and behavior in `src/how-to.zsh` and `src/how-to.bash`.
- Never left on screen after a normal finish, and never drawn over a later
  prompt.
- Off with one variable; invisible to pipes, scripts and the existing tests.

## Scope

- **In:** the provider call in both files, the `HOW_TO_SPINNER` variable,
  `docs/usage.md`, tests in both suites.
- **Out:** multiple or custom styles, fractional seconds, an indicator for
  context gathering or the bash DSR wait (both take well under a second),
  hiding the cursor.

## What the user sees

- During the provider call, stderr shows one line, redrawn every 0.1 s:
  `\r<frame> thinking <n>s\e[K`. `<frame>` cycles `|`, `/`, `-`, `\`;
  `<n>` is whole seconds since the call started, starting at `0`.
- Before anything else is printed (the pushed command, a `HOWTO_FAIL`
  reason, `how-to: provider failed`, `how-to: no command returned`, bash's
  DSR query or its printed fallback), the line is erased with `\r\e[K`.
- On Ctrl-C the spinner dies with the call. The last frame stays on its line
  followed by the terminal's `^C`, and the prompt appears on the next line,
  as with any interrupted command. Erasing here is deliberately not done:
  an erase racing the shell's prompt redraw could wipe the new prompt.
- Shown only when all of these hold: `HOW_TO_SPINNER` is not `0`, stderr is
  a terminal (`-t 2`), and `TERM` is not `dumb`.

## Configuration

`HOW_TO_SPINNER`, default `1`, set only if unset (zsh
`(( ${+HOW_TO_SPINNER} )) ||`, bash `declare -p HOW_TO_SPINNER &>/dev/null ||`).
`0` disables the indicator; any other value enables it. A prefix assignment
(`HOW_TO_SPINNER=0 how-to …`) works in both shells; in bash it reaches the
call through the existing `_how_to_pre` snapshot of `HOW_TO_*`.

## Mechanism

### `_how_to_spin`

A new function in each file. Its stdin is the read end of a pipe that is
never written to; the only event it ever sees is EOF, when the last writer
closes.

1. If disabled (see the three conditions above), exit 0 at once, drawing
   nothing.
2. Otherwise reset the elapsed counter in its own subshell (`SECONDS=0`;
   zsh declares it integer first, in case the user has `typeset -F SECONDS`)
   and loop:
   - wait up to 0.1 s for input: zsh `sysread -t 0.1` after
     `zmodload zsh/system` (status 4 = timeout, 5 = EOF); bash
     `read -t 0.1` (status > 128 = timeout);
   - on timeout, draw the next frame to stderr;
   - on EOF (or any other status), exit 0 **without writing anything**.
3. SIGINT keeps its default action, so Ctrl-C kills the spinner along with
   the provider.

The spinner never reads the terminal, so bash's typeahead check in
`_how_to_push` is unaffected.

### Call site

In zsh `how-to` and bash `_how_to_main`, the provider line becomes:

```zsh
{ raw=$(print -r -- "$msg" | $fn "$HOW_TO_SYSTEM_PROMPT" 3>&-); rc=$? } 3> >(_how_to_spin)
```

(bash: the same with `printf '%s\n'`, `"$fn"`, and `; }`.) Then:

- bash runs `wait $!` so the spinner has exited before continuing. zsh
  already waits for a `>(…)` process used in a redirection.
- If the spinner was enabled, the parent prints `\r\e[K` to stderr. Because
  the spinner has exited, nothing can draw after this erase.
- `rc` is checked as `raw=$(…)`'s status was before; all later steps are
  unchanged.

Details:

- One code path whether enabled or not: the spinner process always starts
  and exits at once when disabled. One extra fork per call is negligible
  next to an LLM call.
- `3>&-` on the provider keeps fd 3 out of it, so a lingering child of the
  provider cannot hold the pipe open and keep the spinner running.
- The enabled check lives in one helper per file (`_how_to_spin_on`), used
  by both the spinner and the parent's erase, so they always agree.

### Verified by probe (zsh 5.9, bash 5.3, under a pty)

- EOF reaches the spinner when the block ends; zsh waits for it unaided,
  bash with `wait $!`.
- Ctrl-C delivers SIGINT to the spinner; with the default action it dies
  without drawing again. (Ignoring SIGINT and erasing at EOF also works but
  races the prompt redraw; rejected.)

### To verify during implementation

- `wait $!` on a process substitution in bash 4.4 (only 5.3 was probed).
- zsh still waits for the spinner under `emulate -L zsh` and in the
  `ksharrays` re-runs.

## Testing

Non-pty, both suites (stderr is not a terminal, so the spinner stays off but
its process still starts on every call):

- Existing end-to-end stderr assertions keep passing, including zsh's
  `ksharrays` runs and bash's `set -euo pipefail` / `failglob` /
  `nocasematch` / odd-`IFS` runs.
- The stub provider records whether `/dev/fd/3` exists; it must not.
- `HOW_TO_SPINNER` defaults to `1`, and a user value survives re-sourcing.

pty, both suites (`expect`; skipped with a notice when `expect` is missing).
bash extends its existing harness; zsh gets an equivalent block. A stub
provider sleeps for a configured time.

1. Draws and clears: stub sleeps ~1.3 s; output contains `| thinking 0s`,
   later `1s`, then `\r\e[K`; the command still lands on the prompt.
2. `HOW_TO_SPINNER=0 how-to …`: no `thinking` in the output.
3. `TERM=dumb`: no `thinking`.
4. Ctrl-C during the sleep: the prompt returns, no `thinking` appears after
   it, and a follow-up command runs normally; in bash, tty settings and
   globbing are restored (existing checks).
5. Error path: stub replies `HOWTO_FAIL: nope` after a delay; `\r\e[K`
   precedes `nope`.

Run both suites on bash 4.4 if one can be obtained; otherwise report that
4.4 was not tested.

## Docs

`docs/usage.md` gets a short paragraph: what the indicator shows, that it
only appears on a terminal, the Ctrl-C behavior, and `HOW_TO_SPINNER=0`.
`CLAUDE.md` gains a line on `_how_to_spin` and the fd-3 call site.
