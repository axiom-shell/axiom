---
paths:
  - "scripts/**"
  - "tests/scripts/**"
  - ".githooks/**"
---

# Scripts (`scripts/`)

Dev tooling only (checks, generators, `log.sh`, `dev/`): nothing at runtime runs it and packages leave it out; runtime non-QML files go in `data/`.

- Shell scripts pass `shellcheck -x -S warning`. Each check script has a `tests/scripts/test_scripts.py` class that breaks a fixture copy once per rule (a new rule gets its case), mapped in `scripts/dev/verify.sh`'s `script_tests` so changing the script runs it.
- Theme integrations, hookups, self-update and the greeter installer are the daemon's (`backend/internal/…`), not scripts. `data/greeter/greeter_install.sh` is only root's way into `axiom greeter-install`; test it only with scratch `HOME`/`XDG_CONFIG_HOME` and `AXIOM_GREETER_ROOT`.
- Files the shell watches are written atomically (temp file + rename); QML files the opposite: in place.
