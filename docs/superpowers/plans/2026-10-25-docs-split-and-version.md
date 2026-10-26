# Docs Split and Version Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** (1) Split `docs/usage.md` into user docs (`docs/usage.md`) and developer docs (`docs/development.md`). (2) Add `-v` / `--version` to `how-to` in zsh and bash; when flags are present, the request comes after all flags or after `--`.

**Spec:** none beyond this plan (user request: "split development from usage, so there should be 2 docs under docs/" and "add a -v and --version flag to how-to. if flags present, the prompt comes after all flags or --").

## Global Constraints

- Two independent files, same behavior: `src/how-to.zsh`, `src/how-to.bash`. Follow CLAUDE.md conventions (zsh: `emulate -L zsh`, `command` for externals; bash: `local -`, survives `set -euo pipefail`, `failglob`, `nocasematch`, odd `IFS`).
- Version lives in a plain variable `_how_to_version=0.3.0` near the top of each file (after the header comment), assigned unconditionally (not a config variable). Both files must hold the same value (bash test compares against zsh, like the system prompt test).
- `how-to -v` and `how-to --version` print exactly `how-to 0.3.0` (i.e. `how-to $_how_to_version`) to stdout and return 0. Nothing else runs (no provider, no push).
- Option parsing, from the first argument: `-v`/`--version` → set version flag, keep parsing; `--` → drop it, stop parsing; any other word starting with `-` (and longer than just `-`) → stderr `how-to: unknown option '<word>'` then the usage line, return 2; any other word → stop parsing (that word and the rest are the request). Only leading words are options: `how-to list files -v` sends `list files -v` as the request.
- If the version flag was set, print the version and return 0, ignoring any request words.
- After parsing, if no request words remain → usage, return 2 (so `how-to --` gives usage).
- Usage line, both files, exactly: `usage: how-to [-v | --version] [--] <what you want to do>`.
- `how-to -- -v x` sends request `-v x`.
- Release workflow: in `.github/workflows/release.yml` "Check tag" step, fail with `::error::` if `_how_to_version` in either source file differs from the tag's `X.Y.Z`.

## Task 1: Split docs

Files: `docs/usage.md` (modify), `docs/development.md` (create), `README.md`, `CLAUDE.md`.

- Move the `## Tests` section out of `docs/usage.md` into new `docs/development.md`.
- `docs/development.md` (title `# Developing how-to`) covers, concisely, in the same terse style as usage.md: layout of the repo (`src/how-to.zsh`, `src/how-to.bash`, tests, `docs/superpowers/specs` and `plans`); running tests (commands from CLAUDE.md "Commands"); CI (what `test.yml` runs); releasing (push tag `vX.Y.Z`, `release.yml` tests then publishes tarball + sha256, Homebrew tap autobump); a short architecture overview of the pipeline (`how-to` → `_how_to_context` → provider → `_how_to_clean` → `HOWTO_FAIL` check → `_how_to_push`) and pointers to CLAUDE.md for shell conventions. Derive content from CLAUDE.md and the workflows; do not invent facts.
- "Writing a provider" and "Writing a context provider" stay in usage.md (users write these in their rc files).
- README: keep the existing usage.md link; add one line linking `docs/development.md` for contributors.
- CLAUDE.md: where it says "User docs are in `docs/usage.md`", also mention `docs/development.md` for developer docs.
- Release tarball keeps shipping only `docs/usage.md` (no change to release.yml in this task).
- No code changes. Verify both test suites still pass.

## Task 2: Version flag

Files: `src/how-to.zsh`, `src/how-to.bash`, `src/test.zsh`, `src/test.bash`, `.github/workflows/release.yml`, `docs/usage.md`, `docs/development.md`, `CLAUDE.md`.

- Implement per Global Constraints in `function how-to` (zsh) and `_how_to_main` (bash; parsing goes after the `eval "$env"` line, replacing the current `(( ! $# ))` check). In bash, pattern matching must be safe under `nocasematch`/`extglob` changes — use `case` or `[[ == ]]` with the shopt save/restore convention if needed, or plain string comparisons.
- Update existing tests asserting the old usage line (`src/test.zsh` "no args msg", `src/test.bash` "no args msg").
- New tests in both suites (same names): `version: -v` (stdout `how-to 0.3.0`, rc 0, provider not called), `version: --version`, `version: ignores request` (`-v foo`), `opts: -- passes dash request` (`-- -v x` → request `-v x`), `opts: -- alone is usage` (rc 2), `opts: unknown option` (`-x foo` → rc 2, stderr first line `how-to: unknown option '-x'`), `opts: trailing -v is request` (`list -v` → request `list -v`), `version: same in both files` (bash only, compare with zsh's `_how_to_version`). Bash version tests should also run under the existing strict-mode harness if one exists for the main path.
- `release.yml`: add the version check described in Global Constraints.
- `docs/usage.md`: short "Options" subsection under `## Use` documenting `-v`/`--version` and `--`.
- `docs/development.md` releasing section and CLAUDE.md release paragraph: bump `_how_to_version` in both files before tagging; release fails otherwise.
- Run both suites (`zsh src/test.zsh`, `/opt/homebrew/bin/bash src/test.bash`).
