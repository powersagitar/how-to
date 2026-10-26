# Developing how-to

## Layout

- `src/how-to.zsh`, `src/how-to.bash`: the two implementations. They are
  independent files with the same pipeline.
- `src/test.zsh`, `src/test.bash`: the test suites.
- `docs/usage.md`: user docs. `docs/superpowers/specs/` and
  `docs/superpowers/plans/`: design specs and implementation plans.
- `.github/workflows/test.yml`, `release.yml`: CI and release.

Both files must be sourced, not run: a child process can't write to the
parent shell's line editor.

## Architecture

Every call runs one pipeline: `how-to` → `_how_to_context` → provider →
`_how_to_clean` → `HOWTO_FAIL` check → `_how_to_push`.

- Model providers are `_how_to_provider_<name>`, selected by
  `HOW_TO_PROVIDER`.
- Context providers are `_how_to_context_<name>`, run in the order given by
  `HOW_TO_CONTEXT`.
- zsh pushes the command onto the prompt with `print -rz`; bash does it via a
  terminal DSR reply (see `docs/usage.md`).

Shell conventions (zsh and bash), the history hook and the testing approach
are in `CLAUDE.md`. Read it before changing either file.

## Tests

```
zsh src/test.zsh                    # full suite; exit 1 if any FAIL
zsh src/test.zsh | grep -v '^ok'    # show only failures
zsh src/test.zsh | grep 'git:'      # one group (filter by test name)
bash src/test.bash                  # any bash >= 4.4 (macOS /bin/bash is 3.2)
```

The bash suite uses expect for its pty tests if installed. Tests are flat
`assert_eq "<name>" expected actual` calls. There is no build or lint step.

## CI

`.github/workflows/test.yml` runs on every push, with expect installed, on
Ubuntu: the zsh suite once, and the bash suite on bash 4.4.18 and 5.0 (built
from source) plus the runner's /bin/bash. Skipped pty or prompt tests fail the
job. A failing pty test prints the end of its transcript.

## Releasing

Push a tag `vX.Y.Z`. `.github/workflows/release.yml` calls `test.yml`, and if
every job passes it creates a GitHub release with `how-to-X.Y.Z.tar.gz` and
its `.sha256`. The tarball contains `src/how-to.zsh`, `src/how-to.bash`,
`LICENSE`, `README.md` and `docs/usage.md`.

The Homebrew formula lives in `powersagitar/homebrew-tap`, whose daily
autobump workflow opens a pull request for each new release.
