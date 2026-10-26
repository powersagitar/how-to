# Using how-to

## Install

With [Homebrew](https://brew.sh) (macOS or Linux):

```sh
brew install powersagitar/tap/how-to
```

Then add to `~/.zshrc`:

```zsh
source /opt/homebrew/opt/how-to/share/how-to/how-to.zsh
```

The path above is for Apple silicon. Elsewhere, replace `/opt/homebrew` with
the output of `brew --prefix` (`/usr/local` on Intel macOS,
`/home/linuxbrew/.linuxbrew` on Linux). `brew info how-to` prints the exact
lines. The `opt` path stays the same across upgrades.

Without Homebrew, clone the repository and source the file from it:

```sh
git clone https://github.com/powersagitar/how-to ~/.how-to
echo 'source ~/.how-to/src/how-to.zsh' >> ~/.zshrc
```

`how-to` must be sourced, not run as a script: a child process cannot type
into its parent shell's prompt (`TIOCSTI` is disabled on modern macOS and
Linux), so the function uses zsh's `print -z` to place the command in your
line editor.

The default provider needs `claude` on your `PATH` and logged in.

### bash

Add to `~/.bashrc` (Homebrew path, or `~/.how-to/src/how-to.bash` for a
clone):

```bash
source /opt/homebrew/opt/how-to/share/how-to/how-to.bash
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

If you type while `how-to` is waiting for the model, the command is printed
instead (your keys stay on the prompt). A terminal that doesn't answer within
1 s is remembered, so calls in the next 10 minutes print at once without the
wait; after that, `how-to` asks again. A terminal that is only slow (for
example over a laggy ssh link) recovers sooner: its late answer reaches the
next prompt and makes the next call ask again. If that answer arrives just as
the prompt is being drawn, `^[[0n` may show on the screen; it is harmless.
Known limitation: on a terminal that doesn't answer, a key pressed during the
1 s wait is mistaken for the reply, so that command is neither placed nor
printed. Run it again.

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
expanded (`_how_to_pre && _how_to_run`), so globs pass through the same way.
The quoting advice above applies too. `cond && how-to ...` and
`cond || how-to ...` work as usual. An assignment in front applies to that
call only if its name starts with `HOW_TO_` (`HOW_TO_PROVIDER=ollama how-to
...`); any other assignment in front is ignored.

## Recent commands

Each request carries your last few commands and their exit statuses, so
"fix that" works:

```
$ make test
make: *** [test] Error 2
$ how-to fix that
```

The model sees:

```
history: [exit 0] cd ~/proj
history: [exit 2] make test
```

- Oldest first, at most `HOW_TO_HISTORY` lines (default 5). Set
  `HOW_TO_HISTORY=0` to turn it off, in your rc file or in front of one call.
- Only commands from this shell since sourcing. Lines loaded from the history
  file or imported from other sessions are left out, and so is the `how-to`
  call itself.
- A command the shell keeps out of history is never sent. Start a command
  with a space to keep it private when `HIST_IGNORE_SPACE` (zsh) or
  `HISTCONTROL=ignorespace` (bash) is set. `HISTIGNORE` and a
  `zshaddhistory` hook that returns 1 work the same way. A hook that returns
  2 only keeps the line out of `HISTFILE`, so it is still sent.
- A command is cut at 500 characters, and each newline is shown as `\n`.
- Output is never sent, only the command and its status.
- bash prepends `_how_to_record` to `PROMPT_COMMAND`. Keep it if you reassign
  `PROMPT_COMMAND`. With `HISTCONTROL=ignoredups`, an immediate repeat keeps
  the first run's status.

Known limitations:

- At most 100 entries are kept, so `HOW_TO_HISTORY` above 100 sends 100. A
  very large values aren't supported.
- Events that history renumbers are left out: bash `erasedups` and
  `history -c; history -r`, and zsh `fc -p`. The stored text no longer
  matches, so they're skipped.
- Control characters in commands are shown differently in zsh and bash.
- If something is put before `_how_to_record` in `PROMPT_COMMAND`, the hook
  moves itself back to the front once. The prompt where the move happens
  records nothing. That rewrites `PROMPT_COMMAND`, and other mentions of
  `_how_to_record` in it become `:`.
- With an array `PROMPT_COMMAND`, bash before 5.1 runs only element 0, so
  the hooks go into element 0 there.

## Progress indicator

While the model works, stderr shows a spinner and the seconds waited so far,
like `/ thinking 3s`. The line is erased before the command (or an error)
appears. It only shows when stderr is a terminal and `TERM` isn't `dumb`, so
pipes and scripts never see it. If you press Ctrl-C, the last frame stays on
its line next to `^C`. Set `HOW_TO_SPINNER=0` in your rc file to turn it off,
or put it in front of a single call (`HOW_TO_SPINNER=0 how-to ...`).

## Configuration

Set these in `~/.zshrc` or `~/.bashrc` (before or after sourcing).

| variable | default | purpose |
|----------|---------|---------|
| `HOW_TO_PROVIDER` | `claude` | which `_how_to_provider_<name>` to use |
| `HOW_TO_CLAUDE_ARGS` | `--model haiku` | extra flags for `claude --print` |
| `HOW_TO_CONTEXT` | `(os shell cwd git tools history)` | context providers, in order |
| `HOW_TO_TOOLS` | `(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)` | tools reported as installed, if found |
| `HOW_TO_SYSTEM_PROMPT` | see `src/how-to.zsh` | rules sent to the model |
| `HOW_TO_HISTORY` | `5` | recent commands sent with their exit status; `0` turns it off |
| `HOW_TO_SPINNER` | `1` | `0` turns the progress indicator off |

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
