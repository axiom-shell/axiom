---
paths:
  - "qml/components/surfaces/osd/**"
  - "tests/osd/**"
---

# The OSD (`qml/components/surfaces/osd/`)

`OSDHost` shows an OSD's parts (bars, status icons, a card); each item of its `systems` list is a folder of `systems/`, judged by the pure `OSDEngine` (`qml/components/methods/`). Docs: `docs/dev/features/osd.md` (› Engine is the contract). Recipe: `/osd-system`.

- **A definition is pure** (`systems/<Type>/<Type>.qml`, an `OSDSystem`): it imports only `QtQuick`, `qs.components.methods` and the engine folder, so `tst_OSDSystems` loads it.
- **Only `<Type>Watch.qml` reads services** (and the system's `design/`). No file of a system names another: each is loaded by URL (`Paths.osdSystemUrl`, `osdWatchUrl`, `osdDesignUrl`).
- **Declarations before code**: a definition is `exposes`, its model, policies and the declarations osd.md › Engine lists, plus `tile()` (and `card()`). No `judge()` without a reason written above it; a missing behaviour is a new generic declaration in `OSDEngine` with a `tst_OSDEngine` case and an osd.md line, never a system's name in the engine or host.
- **Every behaviour is a timeline row** in `tests/osd/<Type>.js` (listed in `tests/osd/index.js`; cross-system rows in `Cross.js`).
- `OSDHost` and `engine/` name no system; anything two systems draw goes in `design/`.
