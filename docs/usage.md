# Using how-to

## Install

Add to `~/.zshrc`:

```zsh
source /path/to/how-to/src/how-to.zsh
```

`how-to` must be sourced, not run as a script: a child process cannot type
into its parent shell's prompt (`TIOCSTI` is disabled on modern macOS and
Linux), so the function uses zsh's `print -z` to place the command in your
line editor.

The default provider needs `claude` on your `PATH` and logged in.

### bash

Add to `~/.bashrc`:

```bash
source /path/to/how-to/src/how-to.bash
```

Requires bash 4.4 or newer. macOS ships bash 3.2 as `/bin/bash`; install a
current one with `brew install bash`. On an older bash, sourcing prints a
one-line notice and defines nothing, so a shared `.bashrc` keeps working.

bash has no `print -z`, so the command reaches your prompt through the
terminal: `how-to` sends a Device Status Report query (`\e[5n`), the terminal
answers `\e[0n`, and that answer is bound to a readline function that fills in
the prompt. xterm, iTerm2, Terminal.app, kitty, VS Code and tmux all answer.
To check yours:

```bash
s=$(stty -g); stty -echo; printf '\e[5n'; IFS= read -rs -t1 -d n r && echo ok || echo 'no DSR reply'; stty "$s"
```

If the terminal doesn't answer within 1 s, or the shell isn't interactive, the
command is printed instead of placed on the prompt. Ctrl-C during that wait
cancels the call and leaves your terminal as it was. Both emacs and vi
(`set -o vi`) editing modes work.

Known limitation: on a terminal that doesn't answer, keys you type while
`how-to` is waiting for the model are mistaken for the reply, so the command
is neither placed nor printed. Run it again without typing ahead.

Sourcing the bash file in an interactive shell also appends
`_how_to_restore_glob` to `PROMPT_COMMAND` (once, even if you re-source).
It turns globbing back on if a request word failed to expand (for example
`how-to print $1` under `set -u`), which aborts the line before `how-to` can
undo its `set -f`. It keeps `$?` intact for your other prompt hooks. If you
assign `PROMPT_COMMAND` after sourcing, append to it instead of replacing it.

## Use

```
$ how-to count lines of code in this repo
$ rg --files -0 | xargs -0 wc -l | tail -n 1█
```

Nothing runs until you press Enter; edit the command first if you like. If
the request isn't something a shell command can do, the reason is printed
and your prompt stays empty.

`how-to` is aliased to `noglob how-to`, so `*.log` and friends in your
request are passed through as words. Everything else is still parsed by your
shell before `how-to` sees it, so single-quote the request when it contains
apostrophes, quotes, `$`, `#`, `|`, `;`, `>`, `<` or `&`:

```
$ how-to 'what'"'"'s using port 8080'     # or: how-to what is using port 8080
$ how-to 'files > 100MB in $HOME'
```

`how-to` itself never evaluates the request; it is sent to the model as text.

In bash, `how-to` is an alias that turns globbing off before your words are
expanded (`_how_to_f=$-; set -f; _how_to_main`), so globs pass through the
same way. The quoting advice above applies too. Because the alias is several
commands joined by `;`:

- `HOW_TO_PROVIDER=ollama how-to ...` sets the variable for the rest of the
  session, not just this call. For a one-off, call the function behind the
  alias directly: `HOW_TO_PROVIDER=ollama _how_to_main ...`. That skips the
  glob protection, so quote any `*` in the request, and it turns globbing on
  if you had it off with `set -f`.
- Don't chain it: `cond && how-to ...` runs `how-to` even when `cond` fails.

## Configuration

Set these in `~/.zshrc` or `~/.bashrc` (before or after sourcing).

| variable | default | purpose |
|----------|---------|---------|
| `HOW_TO_PROVIDER` | `claude` | which `_how_to_provider_<name>` to use |
| `HOW_TO_CLAUDE_ARGS` | `--model haiku` | extra flags for `claude --print` |
| `HOW_TO_CONTEXT` | `(os shell cwd git tools)` | context providers, in order |
| `HOW_TO_TOOLS` | `(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)` | tools reported as installed, if found |
| `HOW_TO_SYSTEM_PROMPT` | see `src/how-to.zsh` | rules sent to the model |

`HOW_TO_CONTEXT` and `HOW_TO_TOOLS` can be arrays or space-separated strings.
In bash, set a string only before sourcing; after sourcing they are arrays,
and assigning a string replaces just the first element. Appending with
`HOW_TO_CONTEXT+=(docker)` works in both shells.

## Writing a provider

A provider is a shell function named `_how_to_provider_<name>`:

- `$1` — the system prompt
- stdin — the user message (context block and request)
- stdout — the model's reply
- non-zero exit on failure, with details on stderr

Providers without a system-prompt option can prepend it to the message:

```zsh
_how_to_provider_ollama() { { print -r -- "$1"; cat } | ollama run llama3.2 }
HOW_TO_PROVIDER=ollama
```

The same in bash:

```bash
_how_to_provider_ollama() { { printf '%s\n' "$1"; cat; } | ollama run llama3.2; }
HOW_TO_PROVIDER=ollama
```

To report that a request can't be done, the model replies
`HOWTO_FAIL: <reason>`; the default system prompt asks for this.

## Writing a context provider

A context provider is a shell function named `_how_to_context_<name>` that
prints zero or more `key: value` lines. Output is collected into a
`<context>` block sent before the request. A provider that fails or prints
nothing is skipped.

```zsh
_how_to_context_docker() {
  (( $+commands[docker] )) || return
  print -r -- "containers: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
}
HOW_TO_CONTEXT+=(docker)
```

The same in bash:

```bash
_how_to_context_docker() {
  type -P docker >/dev/null || return
  printf '%s\n' "containers: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
}
HOW_TO_CONTEXT+=(docker)
```

Keep providers fast; they run on every call.

## Tests

```
zsh src/test.zsh
bash src/test.bash     # any bash >= 4.4; uses expect for pty tests if installed
```
