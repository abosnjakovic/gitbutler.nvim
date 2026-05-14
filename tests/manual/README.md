# Manual tests

These scripts exercise flows that depend on `but`, `git`, and (sometimes) a network round-trip. They are **not** part of `make test` because the dependencies aren't guaranteed in CI.

Run them yourself when you've changed something they cover.

## direct_to_main.sh

End-to-end check for the `M` keybind in `:Butler` (commit selected files straight to main).

Covers:

1. **Happy path** — commit to a clean scratch repo, assert local `main`, `origin/main`, and that the ephemeral `direct-to-main-*` branch is gone from both local and origin.
2. **Divergent local target** — make a divergent commit on local `main`, run the harness, assert the action refuses (pre-flight `preflight` error) and leaves both refs untouched.

### Requirements

- `but` on PATH (`brew install gitbutler`)
- `git` on PATH
- `nvim` 0.10+
- Network access if your `but setup` configuration reaches out (most local setups do not for a bare-origin scratch repo)

### Run

```sh
bash tests/manual/direct_to_main.sh
```

Exits 0 on success; non-zero with a description on failure. Temp dirs are removed via `trap`.
