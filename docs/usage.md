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

## Use

```
$ how-to count lines of code in this repo
$ rg --files -0 | xargs -0 wc -l | tail -n 1█
```

Nothing runs until you press Enter; edit the command first if you like. If
the request isn't something a shell command can do, the reason is printed
and your prompt stays empty.

`how-to` is aliased to `noglob how-to`, so `*.log` and friends in your
request are passed through as words. Quote the request if it contains other
shell syntax (`|`, `;`, `>`, `&`).

## Configuration

Set these in `~/.zshrc` (before or after sourcing).

| variable | default | purpose |
|----------|---------|---------|
| `HOW_TO_PROVIDER` | `claude` | which `_how_to_provider_<name>` to use |
| `HOW_TO_CLAUDE_ARGS` | `--model haiku` | extra flags for `claude --print` |
| `HOW_TO_CONTEXT` | `(os shell cwd git tools)` | context providers, in order |
| `HOW_TO_TOOLS` | `(rg fd jq yq tokei cloc fzf bat eza gh docker kubectl brew git python3 node)` | tools reported as installed, if found |
| `HOW_TO_SYSTEM_PROMPT` | see `src/how-to.zsh` | rules sent to the model |

## Writing a provider

A provider is a zsh function named `_how_to_provider_<name>`:

- `$1` — the system prompt
- stdin — the user message (context block and request)
- stdout — the model's reply
- non-zero exit on failure, with details on stderr

Providers without a system-prompt option can prepend it to the message:

```zsh
_how_to_provider_ollama() { { print -r -- "$1"; cat } | ollama run llama3.2 }
HOW_TO_PROVIDER=ollama
```

To report that a request can't be done, the model replies
`HOWTO_FAIL: <reason>`; the default system prompt asks for this.

## Writing a context provider

A context provider is a zsh function named `_how_to_context_<name>` that
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

Keep providers fast; they run on every call.

## Tests

```
zsh src/test.zsh
```
