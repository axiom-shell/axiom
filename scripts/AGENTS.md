# Scripts (`scripts/`)

External scripts the shell runs (wallpaper, self-update, Hyprland claim, greeter) and the dev checks (`check_*.py`, `run_tests.sh`, `log.sh`, `dev/`).

Verify with `scripts/dev/verify.sh`.

- Shell scripts pass `shellcheck -x -S warning`; Python is checked by `tests/scripts/test_scripts.py`. A script's test class gets a line in `scripts/dev/verify.sh`'s `script_tests` map, so changing the script runs it (the whole file takes ~15 s).
- **Theme integrations** are the daemon's (`backend/internal/theme/integrations`; recipe `docs/recipes/theme-integration.md`); only the hookup (`integration_hookup.py`) and the Neovim module (`templates/nvim/`) live here.
- Test hookups, `self_update.sh` and `greeter/greeter_install.sh` only on scratch dirs (`HOME`/`XDG_CONFIG_HOME`, scratch clones, `AXIOM_GREETER_ROOT`), never the live system.
- Files the shell watches are written atomically (temp file + rename).
