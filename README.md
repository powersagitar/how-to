# how-to

Describe what you want in plain English; get the exact shell command placed
on your prompt, ready to review and run with Enter. One zsh (or bash) file, no
dependencies beyond the [Claude Code](https://claude.com/claude-code) CLI
(or any provider you plug in).

```
$ how-to find all markdown files changed in the last week
$ fd -e md --changed-within 1w█
```

## Install

```sh
brew install powersagitar/tap/how-to
```

Then source it from your shell's rc file (Apple silicon paths shown; use
`brew --prefix` in place of `/opt/homebrew` elsewhere, or see `brew info how-to`):

```sh
# ~/.zshrc
source /opt/homebrew/opt/how-to/share/how-to/how-to.zsh
# ~/.bashrc (bash >= 4.4)
source /opt/homebrew/opt/how-to/share/how-to/how-to.bash
```

The default provider needs `claude` on your `PATH` and logged in.

See [docs/usage.md](docs/usage.md) for installing without Homebrew and for
configuration.
