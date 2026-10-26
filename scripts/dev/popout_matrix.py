#!/usr/bin/env python3
"""Visual matrix of popouts across bar, border and opacity combinations.

Rewrites the live config.json ($XDG_CONFIG_HOME/axiom/, atomically) once per scenario, opens every
kind of popout on the running shell (bar popouts at each end of each bar and a
submenu, floating edge menus, docks, the OSD, the attached launcher), crops
each from a screenshot by its PopoutManager footprint and puts them on one
contact sheet per scenario. The config is restored, byte for byte, at the end
(or on any failure).

Bar popouts and submenus are opened through a `devPopouts` IPC hook the
script adds to shell.qml while it runs (in place, so the shell reloads it) and
takes out again at the end.

  scripts/dev/popout_matrix.py OUT_DIR [--only NAME ...] [--monitor DP-1]
"""

import argparse
import copy
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HOOK_MARK = "// popout_matrix.py hook"
HOOK_IMPORTS = "import QtQml " + HOOK_MARK + "\nimport Quickshell.Io " + HOOK_MARK + "\nimport qs.components.methods " + HOOK_MARK + "\n"
HOOK = """
  // popout_matrix.py: opens a bar popout (or a submenu in the open one)
  // with no pointer, held open; the script takes it out again
  QtObject {
    id: devPopoutsHelper
    property var host: null
    function trayEntries(item, out) {
      for (const c of item?.children ?? []) {
        if (c.menuItem !== undefined && c.menuItem?.hasChildren && c.visible)
          out.push(c);
        trayEntries(c, out);
      }
      return out;
    }
    function anchors(item, out) {
      for (const c of item?.children ?? []) {
        if (c.popoutName !== undefined && c.popoutName !== "" && c.visible)
          out.push(c);
        anchors(c, out);
      }
      return out;
    }
  }
  IpcHandler {
    target: "devPopouts"
    function open(screen: string, location: string, which: string): string {
      close();
      const panel = ScreenEdgeManager.barOn(screen, ScreenEdge.fromName(location));
      if (!panel)
        return "no bar";
      const vertical = panel.barConfig.vertical;
      const list = devPopoutsHelper.anchors(panel.contentItem, []).map(a => ({ a, p: a.mapToItem(null, 0, 0) })).sort((x, y) => vertical ? x.p.y - y.p.y : x.p.x - y.p.x);
      if (list.length === 0)
        return "no anchors";
      const n = which === "first" ? 0 : which === "last" ? list.length - 1 : which === "middle" ? Math.floor(list.length / 2) : parseInt(which);
      const pick = list[Math.max(0, Math.min(list.length - 1, n))].a;
      const host = panel.popoutHost;
      devPopoutsHelper.host = host;
      host.autoDismiss = false;
      pick.open();
      return pick.popoutName + " of " + list.map(e => e.a.popoutName).join(",");
    }
    function sub(which: string): string {
      const host = devPopoutsHelper.host;
      if (!host?.window)
        return "no host";
      const list = devPopoutsHelper.anchors(host.window.contentItem, []);
      if (list.length === 0) {
        // A tray menu's entries with a submenu
        const entries = devPopoutsHelper.trayEntries(host.window.contentItem, []);
        if (entries.length === 0)
          return "no anchors";
        const entry = entries[which === "last" ? entries.length - 1 : 0];
        const inner = Array.from(host.submenu.data).find(o => o.autoDismiss !== undefined);
        if (inner)
          inner.autoDismiss = false;
        host.submenu.safeOpenPopout(host.window, {
          "name": "parts/TraySubmenu",
          "menuItem": entry.menuItem,
          "anchorItem": entry
        });
        return "tray entry of " + entries.length;
      }
      const pick = list[which === "last" ? list.length - 1 : 0];
      pick.open();
      return pick.popoutName + " of " + list.length;
    }
    function close(): void {
      const host = devPopoutsHelper.host;
      devPopoutsHelper.host = null;
      if (!host)
        return;
      if (host.submenu) {
        const inner = Array.from(host.submenu.data).find(o => o.autoDismiss !== undefined);
        if (inner)
          inner.autoDismiss = Qt.binding(() => inner.currentItem?.autoDismiss ?? true);
        host.submenu.closePopout();
      }
      host.autoDismiss = Qt.binding(() => host.currentItem?.autoDismiss ?? true);
      host.hide();
    }
  }
"""

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "axiom", "config.json")
SHELL = os.path.join(ROOT, "shell.qml")


def write_in_place(path, text):
    # The same inode, so the running shell sees the change and reloads
    with open(path, "w") as f:
        f.write(text)


def install_hook(original):
    if "devPopouts" in original:
        return False
    text = original.replace("import Quickshell\n", "import Quickshell\n" + HOOK_IMPORTS, 1)
    end = text.rstrip().rfind("}")
    text = text[:end].rstrip("\n") + "\n" + HOOK + "}\n"
    write_in_place(SHELL, text)
    time.sleep(3)
    return True

EDGES = ["top", "bottom", "left", "right"]
LOCATION = {"top": "Top", "bottom": "Bottom", "left": "Left", "right": "Right"}

# Layouts: what bar (background) sits on each edge; others have none
LAYOUTS = {
    "none": {},
    "solid-TL": {"top": "solid", "left": "solid"},
    "pills-TL": {"top": "pills", "left": "pills"},
    "pills-BL": {"bottom": "pills", "left": "pills"},
    "transp-T-pills-L": {"top": "transparent", "left": "pills"},
    "float-T-pills-L": {"top": "floating", "left": "pills"},
    "fpills-T-solid-R": {"top": "floatingPills", "right": "solid"},
    "solid-T-transp-L": {"top": "solid", "left": "transparent"},
    "solid-B-float-L": {"bottom": "solid", "left": "floating"},
    "pills-T-solid-B": {"top": "pills", "bottom": "solid", "right": "pills"},
}
VARIANTS = [
    ("b1-o100", True, 100),
    ("b1-o70", True, 70),
    ("b0-o100", False, 100),
    ("b0-o70", False, 70),
]


def qs(*args, check=False):
    r = subprocess.run(["qs", "-c", "axiom", "ipc", "call", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"ipc {args}: {r.stderr.strip()}")
    return r.stdout.strip()


def write_atomic(path, data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".matrix-", suffix=".json")
    with os.fdopen(fd, "w") as f:
        f.write(data)
    os.replace(tmp, path)


def footprints():
    """PopoutManager's entries: key -> (x, y, w, h) bounding all its rects."""
    out = {}
    for line in qs("popouts", "list").splitlines():
        m = re.match(r"(\S+) .*? (-?\d+),(-?\d+) (\d+)x(\d+)", line)
        if m:
            out[m.group(1)] = tuple(int(v) for v in m.groups()[1:])
    return out


def build(base, layout, border, opacity):
    cfg = copy.deepcopy(base)
    bars = {b["location"].lower(): b for b in base["Bars"]}
    horiz = bars.get("top") or bars.get("bottom") or base["Bars"][0]
    vert = bars.get("left") or bars.get("right") or base["Bars"][0]
    out = []
    for edge, background in layout.items():
        tpl = bars.get(edge) or (horiz if edge in ("top", "bottom") else vert)
        b = copy.deepcopy(tpl)
        b.update({"id": f"m-{edge}", "location": LOCATION[edge], "background": background, "enabled": True, "monitor": "", "reserveSpace": True})
        out.append(b)
    cfg["Bars"] = out
    cfg["Appearance"]["shape"]["screenBorder"] = border
    cfg["Appearance"]["surface"]["opacity"] = opacity
    return cfg


def grab(path, monitor):
    subprocess.run(["grim", "-o", monitor, path], check=True)


def crop(full, rect, out, pad=70):
    x, y, w, h = rect
    x0, y0 = max(0, x - pad), max(0, y - pad)
    subprocess.run(["magick", full, "-crop", f"{w + 2 * pad}x{h + 2 * pad}+{x0}+{y0}", "+repage", "-resize", "700x700>", out], check=True)


def corners(full, rect, out, size=150):
    """The footprint's four corners at 1:1, side by side: where joins are."""
    x, y, w, h = rect
    tiles = []
    for cx, cy in ((x, y), (x + w, y), (x, y + h), (x + w, y + h)):
        tile = f"{out}.{len(tiles)}.png"
        subprocess.run(["magick", full, "-crop", f"{size}x{size}+{max(0, cx - size // 2)}+{max(0, cy - size // 2)}", "+repage", tile], check=True)
        tiles.append(tile)
    subprocess.run(["magick", *tiles, "+append", out], check=True)
    for t in tiles:
        os.remove(t)


def shoot(name, monitor, outdir, scenario, settle=1.2, key_prefix=None):
    time.sleep(settle)
    full = os.path.join(outdir, f".{scenario}.png")
    grab(full, monitor)
    fps = footprints()
    shots = []
    for key, rect in fps.items():
        if key_prefix and not key.startswith(key_prefix):
            continue
        out = os.path.join(outdir, scenario, f"{name}__{key.replace(':', '_').replace('/', '-')}.png")
        crop(full, rect, out)
        corners(full, rect, os.path.join(outdir, scenario, "corners", os.path.basename(out)))
        shots.append(out)
    return shots


def run_scenario(base, scenario, layout, border, opacity, monitor, outdir):
    os.makedirs(os.path.join(outdir, scenario, "corners"), exist_ok=True)
    write_atomic(CONFIG, json.dumps(build(base, layout, border, opacity), indent=2))
    time.sleep(2.5)
    shots = []
    for edge in layout:
        names = []
        for which in ("first", "last"):
            r = qs("devPopouts", "open", monitor, edge, which)
            names = r.split(" of ")[1].split(",") if " of " in r else []
            shots += shoot(f"bar-{edge}-{which}", monitor, outdir, scenario, key_prefix=f"bar:m-{edge}")
            qs("devPopouts", "close")
            time.sleep(0.5)
        # A submenu: the first tray item whose menu has one
        for i in [i for i, n in enumerate(names) if n == "SystemTray"]:
            qs("devPopouts", "open", monitor, edge, str(i))
            time.sleep(1.2)
            if not qs("devPopouts", "sub", "first").startswith("no "):
                shots += shoot(f"bar-{edge}-sub", monitor, outdir, scenario, key_prefix=f"bar:m-{edge}")
                qs("devPopouts", "close")
                time.sleep(0.5)
                break
            qs("devPopouts", "close")
            time.sleep(0.5)
    pinned = {l.split()[0] for l in qs("edgeMenu", "list").splitlines() if "(pinned)" in l}
    for menu in [m["id"] for m in base["EdgeMenus"] if m.get("mode") == "floating" and m.get("enabled")]:
        # Opened without the pointer, an unpinned menu closes at once
        qs("edgeMenu", "pin", menu)
        qs("edgeMenu", "open", menu)
        shots += shoot(f"menu-{menu}", monitor, outdir, scenario, key_prefix=f"menu:{menu}")
        if menu not in pinned:
            qs("edgeMenu", "unpin", menu)
        qs("edgeMenu", "close", menu)
        time.sleep(0.5)
    for dock in [d["id"] for d in base["Dock"]["docks"] if d.get("enabled")]:
        qs("dock", "open", dock)
        shots += shoot(f"dock-{dock}", monitor, outdir, scenario, key_prefix=f"dock:{dock}:")
        qs("dock", "close", dock)
    qs("audio", "volumeUp")
    qs("audio", "volumeDown")
    shots += shoot("osd", monitor, outdir, scenario, settle=0.4, key_prefix="osd:")
    qs("appLauncher", "open")
    shots += shoot("launcher", monitor, outdir, scenario, key_prefix="launcher:")
    qs("appLauncher", "close")
    time.sleep(0.6)
    if shots:
        sheet = os.path.join(outdir, f"{scenario}.png")
        subprocess.run(["magick", "montage", "-label", "%t", *shots, "-geometry", "+6+6", "-tile", "5x", "-pointsize", "12", "-background", "#202020", "-fill", "white", sheet], check=True)
        cdir = os.path.join(outdir, scenario, "corners")
        subprocess.run(["magick", "montage", "-label", "%t", *[os.path.join(cdir, os.path.basename(f)) for f in shots], "-geometry", "+4+4", "-tile", "2x", "-pointsize", "12", "-background", "#202020", "-fill", "white", os.path.join(outdir, f"{scenario}-corners.png")], check=True)
    return len(shots)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--only", nargs="*", help="scenario names (layout[__variant], by prefix)")
    ap.add_argument("--monitor", default="DP-1")
    ap.add_argument("--workspace", default="9", help="an empty workspace to shoot on, so windows behind don't muddle the strokes")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    with open(CONFIG, "rb") as f:
        original = f.read()
    backup = os.path.join(args.outdir, "config.backup.json")
    with open(backup, "wb") as f:
        f.write(original)
    base = json.loads(original)

    with open(SHELL) as f:
        shell_original = f.read()
    before = json.loads(subprocess.run(["hyprctl", "-j", "activeworkspace"], capture_output=True, text=True).stdout)["id"]
    hooked = False
    try:
        hooked = install_hook(shell_original)
        qs("workspaces", "go", args.workspace)
        for lname, layout in LAYOUTS.items():
            for vname, border, opacity in VARIANTS:
                scenario = f"{lname}__{vname}"
                if args.only and not any(scenario.startswith(o) for o in args.only):
                    continue
                n = run_scenario(base, scenario, layout, border, opacity, args.monitor, args.outdir)
                print(f"{scenario}: {n} shots", flush=True)
    finally:
        # (qs never raises: only the writes can, the shell's hook first)
        if hooked:
            qs("devPopouts", "close")
            write_in_place(SHELL, shell_original)
        qs("workspaces", "go", str(before))
        write_atomic(CONFIG, original.decode())
        time.sleep(2)
        with open(CONFIG, "rb") as f:
            ok = f.read() == original
        if not ok:
            write_atomic(CONFIG, original.decode())
        print("config restored" if ok else f"config rewritten after the shell changed it; backup at {backup}", file=sys.stderr)


if __name__ == "__main__":
    main()
