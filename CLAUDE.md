# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`how-to <request>` is a zsh function. It asks an LLM for a single shell command
and places it on the user's prompt with `print -rz`, unexecuted. All the code is
in `src/how-to.zsh`, which is meant to be sourced from `~/.zshrc`. It must be
sourced, not run as a script, because a child process can't write to the
parent shell's line editor. User docs are in `docs/usage.md`; the design spec
is in `docs/superpowers/specs/`.

## Commands

```
zsh src/test.zsh                    # full suite; exit 1 if any FAIL
zsh src/test.zsh | grep -v '^ok'    # show only failures
zsh src/test.zsh | grep 'git:'      # one group (no runner; filter by test name)
```

There is no build or lint step. Tests are flat `assert_eq "<name>" expected actual` calls.

## Architecture

Every call runs one pipeline, `how-to` → `_how_to_context` → provider →
`_how_to_clean` → `HOWTO_FAIL` check → `_how_to_push`. The two extension
points are discovered by function name:

- **Model providers** are `_how_to_provider_<name>`, selected by
  `HOW_TO_PROVIDER` (default `claude`). `$1` is the system prompt, stdin is
  the message, stdout is the raw reply, and failure is a non-zero exit. The
  claude provider runs `command claude --print --tools "" --no-session-persistence --system-prompt "$1"`
  plus `HOW_TO_CLAUDE_ARGS` (default `--model haiku`). **Never add `--bare`**,
  because it breaks OAuth login.
- **Context providers** are `_how_to_context_<name>`, run in the order given by
  `HOW_TO_CONTEXT` (an array or a space-separated string, split with `${=...}`).
  Each prints `key: value` lines into a `<context>` block. Missing, failing, or
  empty providers are skipped silently.

When there's no command to give, the model replies `HOWTO_FAIL: <reason>`.
This line can appear anywhere in the reply, including inside a fence, and only
the reason is shown on stderr. `_how_to_clean` keeps only the inside of the
first code fence (the fence may be indented, and its content is dedented to
match), then trims the result.

Config variables are only set when unset (`(( ${+VAR} )) ||`), so user values
survive re-sourcing.

## zsh conventions (enforced by tests)

- Every function starts with `emulate -L zsh`. Tests re-run key paths under
  `setopt ksharrays` to catch leaked user options.
- Call external programs through `command` (`command git`, `command uname`) so
  user aliases and functions can't interfere. Don't put `builtin` in front of
  `local`/`typeset`, because it breaks array-assignment syntax.
- `how-to` is defined as `function how-to {` (so it re-sources cleanly) and
  aliased to `noglob how-to`.

## Testing notes

- Tests stub `_how_to_push` and use a `stub` provider. The provider runs in a
  pipeline subshell, so it writes what it captures to files in `$tmp` instead
  of setting variables.
- The claude provider is tested with a fake `claude` script prepended to
  `PATH`, which is possible because `command` bypasses functions, not `PATH`.
