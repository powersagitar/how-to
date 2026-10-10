# how-to — Design

## Goal

`how-to <plain-English request>` asks an LLM for the exact shell command and
places it on the user's prompt line, unexecuted, so the user can review/edit
it and press Enter to run it.

```
$ how-to list number of lines of code in the repo
$ tokei .        <- pre-filled, cursor at end, nothing has run
```

Success criteria:

- Minimal and extremely lightweight: one zsh file, no build step, no runtime
  beyond zsh and the provider's CLI.
- Default provider is Claude Code (`claude --print`), reusing its auth and
  provider configuration.
- Swapping providers requires no change to the core.
- Context sent to the model is extensible without changing the core.
- Model output is only the command — no prose, no fences.

## Scope

- **In:** zsh.
- **Later:** bash, as a separate `src/how-to.bash`; see
  `2026-10-10-bash-support-design.md`. The zsh file is free to use zsh idioms.
- **Out:** fish, built-in HTTP providers, command history/caching, explaining
  commands, auto-execution.

## Why a shell function

A child process cannot write into its parent shell's line editor (`TIOCSTI`
is disabled on modern macOS/Linux). So `how-to` is a zsh function, sourced
from `.zshrc`, that ends with `print -z -- "$cmd"` to push the command onto
the editing buffer.

## Layout

```
src/how-to.zsh      the whole tool (sourced from .zshrc)
src/test.zsh        test script: `zsh src/test.zsh`
docs/usage.md       install, configuration, writing providers/context
README.md           one-paragraph summary + link to docs/usage.md
```

## Flow

```
how-to "$@"
  ├─ no args → usage to stderr, return 2
  ├─ resolve provider fn  _how_to_provider_${HOW_TO_PROVIDER:-claude}
  │     missing → "how-to: unknown provider '<name>'", return 1
  ├─ build user message   = <context> block + "Request: $*"
  ├─ raw=$(print -r -- "$msg" | $provider_fn "$system_prompt")
  │     non-zero → provider stderr passes through + "how-to: provider failed", return 1
  ├─ cmd=$(_how_to_clean "$raw")
  │     empty → "how-to: no command returned", return 1
  │     starts with HOWTO_FAIL: → print reason (marker stripped) to stderr, return 1
  └─ print -z -- "$cmd"     # return 0
```

Ctrl-C during the provider call aborts the function; nothing is pushed.

## Model provider interface

A provider is a zsh function named `_how_to_provider_<name>`:

- `$1` — the system prompt (rules).
- stdin — the user message (context block + request).
- stdout — the raw model response.
- exit status — non-zero on failure; diagnostics on stderr.

Providers without a native system-prompt option simply concatenate `$1` and
stdin. Selection: `HOW_TO_PROVIDER=<name>` (default `claude`). Users define
additional providers anywhere (e.g. `.zshrc`) after sourcing `how-to.zsh`.

Built-in provider:

```zsh
_how_to_provider_claude() {
  command claude --print --tools "" --no-session-persistence \
    --system-prompt "$1" ${=HOW_TO_CLAUDE_ARGS:---model haiku}
}
```

- `command` bypasses user aliases (e.g. `claude` aliased to `caffeinate claude`).
- `--tools ""` disables tool use: this is pure text generation.
- `--bare` is deliberately **not** used: it disables OAuth/keychain auth,
  which would break reuse of Claude Code login.
- `HOW_TO_CLAUDE_ARGS` overrides the extra flags; default `--model haiku`
  for latency.

Example user-defined provider (documented in `docs/usage.md`):

```zsh
_how_to_provider_ollama() { { print -r -- "$1"; cat } | ollama run llama3.2 }
```

## Context provider interface

Context is assembled from an ordered list of context providers:

```zsh
typeset -ga HOW_TO_CONTEXT=(os shell cwd git tools)   # only set if unset
```

Each entry `<name>` maps to a function `_how_to_context_<name>` which prints
zero or more `key: value` lines on stdout. The core runs each in order with
stderr suppressed; a failing or missing context provider contributes nothing
and never aborts the run. Output is wrapped:

```
<context>
os: Darwin 27.0.0
shell: zsh 5.9
cwd: /Users/me/project
files: src docs README.md LICENSE
git_root: /Users/me/project
git_branch: main
tools: rg fd jq tokei git
</context>
Request: list number of lines of code in the repo
```

Built-ins (all local, no network, no file contents):

| name    | output |
|---------|--------|
| `os`    | `os: $(uname -sr)` |
| `shell` | `shell: zsh $ZSH_VERSION` |
| `cwd`   | `cwd: $PWD`; `files:` up to 30 entries (incl. dotfiles, unsorted), space-separated |
| `git`   | `git_root:`, `git_branch:` (from `symbolic-ref`; omitted when detached) — nothing if not in a repo |
| `tools` | `tools:` the subset of a fixed list that is on `$PATH` (via `$+commands[...]`) |

The `tools` candidate list is a variable, `HOW_TO_TOOLS`, defaulting to a
short list of common alternatives the model might otherwise guess wrong:
`rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node`.

Extending: define `_how_to_context_docker() { ... }` and
`HOW_TO_CONTEXT+=(docker)`.

## System prompt

```
You convert a request into a single shell command for the user's environment
described in <context>.
Output ONLY the command: no explanation, no markdown, no code fences.
Prefer tools listed in "tools:" when they fit; otherwise use standard POSIX/
OS-native utilities.
Use a single line; chain with && or | when needed.
Do not refuse destructive commands; the user reviews before running.
If the request cannot be done with a shell command, output exactly:
HOWTO_FAIL: <short reason>
```

The `HOWTO_FAIL:` marker is internal; users see only the reason.

## Output cleaning (`_how_to_clean`)

1. Remove lines that are code fences (```` ``` ```` optionally followed by a
   language tag).
2. Trim leading/trailing blank lines and trailing whitespace on each line.
3. Leave remaining multi-line content intact (`print -z` handles it; the user
   sees all of it before pressing Enter).

## Errors

All errors go to stderr and leave the prompt buffer untouched.

| case | message | status |
|------|---------|--------|
| no args | `usage: how-to <what you want to do>` | 2 |
| unknown provider | `how-to: unknown provider '<name>'` | 1 |
| provider non-zero | provider's stderr, then `how-to: provider failed` | 1 |
| empty after cleaning | `how-to: no command returned` | 1 |
| model can't do it | `<reason>` | 1 |

## Testing

`src/test.zsh`, no framework: small `assert_eq` helper, exits non-zero on any
failure. It sources `src/how-to.zsh` and overrides functions as needed.

- `_how_to_clean`: fenced input, fenced with lang tag, leading/trailing blank
  lines, trailing whitespace, multi-line command preserved.
- Context assembly: stub `HOW_TO_CONTEXT=(a b)` with stub providers; missing
  provider and failing provider are skipped; empty output omitted.
- End-to-end with `_how_to_provider_stub` and `print -z` captured by running
  the function inside a test that reads the buffer via a wrapper (the core
  calls `_how_to_push "$cmd"`, which defaults to `print -z --` and is
  overridden in tests).
- Error paths: no args (status 2), unknown provider, provider exits 1, empty
  output, `HOWTO_FAIL:` reason printed without marker and nothing pushed.

The real `claude` provider is verified manually once; automated tests make no
network calls.
