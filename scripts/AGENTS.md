# Scripts (`scripts/`)

External scripts the shell runs (wallpaper, Hyprland claim, greeter) and the dev checks (`check_*.py`, `run_tests.sh`, `log.sh`, `dev/`).

Verify with `scripts/dev/verify.sh`.

- Shell scripts pass `shellcheck -x -S warning`; Python is checked by `tests/scripts/test_scripts.py`. A script's test class gets a line in `scripts/dev/verify.sh`'s `script_tests` map, so changing the script runs it (the whole file takes ~15 s).
- **Theme integrations** are the daemon's (`backend/internal/theme/integrations`; recipe `docs/recipes/theme-integration.md`); so are the hookups (`backend/internal/hookup`) and self-update (`backend/internal/selfupdate`); only the Neovim module the hookup copies (`templates/nvim/`) lives here.
- Test `greeter/greeter_install.sh` only on scratch dirs (`HOME`/`XDG_CONFIG_HOME`, `AXIOM_GREETER_ROOT`), never the live system.
- Files the shell watches are written atomically (temp file + rename).
