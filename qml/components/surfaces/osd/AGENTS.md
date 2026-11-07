# The OSD (`qml/components/surfaces/osd/`)

`OSDHost` shows an OSD's parts (bars, status icons, a card); each item of its `systems` list is a folder of `systems/`, judged by the pure `OSDEngine` (`qml/components/methods/`). Docs: `docs/dev/features/osd.md` (Engine is the contract).

**Recipe:** `docs/recipes/osd-system.md` (a new system); verify with `scripts/dev/verify.sh`.

- **A definition is pure** (`systems/<Type>/<Type>.qml`, an `OSDSystem`): it imports only `QtQuick`, `qs.components.methods` and the engine folder, so `tst_OSDSystems` loads it (`check_structure`).
- **Only `<Type>Watch.qml` reads services** (and the system's `design/`); no file of a system's folder names another: each is loaded by URL (`Paths.osdSystemUrl`, `osdWatchUrl`, `osdDesignUrl`; `check_structure`).
- **Declarations before code.** A definition is `exposes`, its model, policies and the declarations osd.md › Engine lists, plus `tile()` (and `card()` for what its card reads). No `judge()` without a reason no declaration covers, written above it; a behaviour the engine lacks is a new generic declaration in `OSDEngine` with its `tst_OSDEngine` case and its osd.md › Engine line, never a system's name in the engine or the host.
- **Every behaviour is a timeline row** (`tests/osd/<Type>.js`, listed in `tests/osd/index.js`; across systems `Cross.js`); a row of a system with no folder fails.
- `OSDHost` and `engine/` name no system; anything two systems draw goes in `design/`, imported by the host.
