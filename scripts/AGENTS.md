# Scripts (`scripts/`)

Dev tooling only: the checks (`check_*.py`, `run_tests.sh`), the generators (`generate.sh`, `gen_docs.py`), `log.sh` (a wrapper of `axiom log`) and `dev/`. Nothing the shell or the daemon runs at runtime lives here, and packages leave the whole folder out: runtime files that aren't QML are in `data/`.

Verify with `scripts/dev/verify.sh`.

- Shell scripts pass `shellcheck -x -S warning`; Python is checked by `tests/scripts/test_scripts.py`. A script's test class gets a line in `scripts/dev/verify.sh`'s `script_tests` map, so changing the script runs it (the whole file takes ~15 s).
- **Theme integrations** are the daemon's (`backend/internal/theme/integrations`; recipe `docs/recipes/theme-integration.md`); so are the hookups (`backend/internal/hookup`) and self-update (`backend/internal/selfupdate`); only the Neovim module the hookup copies (`data/templates/nvim/`) is a file of its own.
- The greeter installer is the daemon's too (`axiom greeter-install`, `backend/internal/greeterinstall`): `data/greeter/greeter_install.sh` is only root's way into it, at the path its polkit action names. Test it only on scratch dirs (`HOME`/`XDG_CONFIG_HOME`, `AXIOM_GREETER_ROOT`), never the live system.
- Files the shell watches are written atomically (temp file + rename).
