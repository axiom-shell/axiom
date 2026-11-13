pragma Singleton

import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/* Whether each running auto-hiding bar (Bars.items[].autoHide always or
 * whenCovered) is shown, by its id in ScreenEdgeManager.bars (a bar on
 * every monitor has one per screen): pinned (the `bar` IPC toggle, which
 * also makes it reserve its space), hovered (its edge strip or the bar,
 * after timing.openDelay, until timing.closeDelay after the pointer
 * leaves), held (its open popouts, an edge menu opened from it, the bar
 * editor with it selected), revealed for a moment (revealFor: a workspace
 * change, a widget's news, the IPC reveal), or for whenCovered, while no
 * window covers its slot. One one-shot Timer runs to the earliest
 * deadline. A bar a window rule hides (`hiddenByRule`) is hidden at
 * once as that starts (hideNow: a pin or a moment from before doesn't
 * keep it shown); its edge, holds, the IPC reveal and a pin made then
 * show it, and nothing is undone as the hold ends. The bars themselves
 * (BarPanel) report hover, holds and coverage, and slide in and out by
 * `shownOf`. */
QtObject {
  id: root

  // Pinned bars by id ({ id: true }): ScreenEdgeManager gives each its
  // effective reserve from this, so it changes only on a pin
  readonly property var pinned: root._pinned
  property var _pinned: ({})

  // Hovered (delays applied), held ({ id: { key: true } }), revealed for a
  // moment, and covered by a window, by bar id
  property var _hover: ({})
  property var _holds: ({})
  property var _momentary: ({})
  property var _covered: ({})

  // Deadlines in ms since the epoch: a moment's end ({ id: at }), and a
  // hover change waiting on its delay ({ id: { on, at } })
  property var _until: ({})
  property var _pendingHover: ({})
  // When each bar was made: its widgets' first news is their startup
  property var _born: ({})

  // How long after a bar is made its widgets' news is ignored
  readonly property int _settleMs: 2000

  // Whether a bar (a ScreenEdgeManager.bars entry) shows
  function shownOf(bar) {
    if (!bar || !bar.autoHiding)
      return true;
    const id = bar.id;
    return root._pinned[id] === true || root._hover[id] === true || Object.keys(root._holds[id] ?? {}).length > 0 || root._momentary[id] === true || (bar.autoHide === "whenCovered" && root._covered[id] !== true);
  }

  function _bar(id) {
    return ScreenEdgeManager.bars.find(bar => bar.id === id) ?? null;
  }

  // A bar was made (BarPanel), or gone
  function register(id) {
    root._born = Utils.withEntry(root._born, id, Date.now());
  }

  function forget(id) {
    root._born = Utils.withEntry(root._born, id, undefined);
    root._hover = Utils.withEntry(root._hover, id, undefined);
    root._holds = Utils.withEntry(root._holds, id, undefined);
    root._momentary = Utils.withEntry(root._momentary, id, undefined);
    root._covered = Utils.withEntry(root._covered, id, undefined);
    root._until = Utils.withEntry(root._until, id, undefined);
    root._pendingHover = Utils.withEntry(root._pendingHover, id, undefined);
  }

  // Whether a window covers the bar's slot (whenCovered)
  function setCovered(id, on) {
    if ((root._covered[id] === true) !== on)
      root._covered = Utils.withEntry(root._covered, id, on ? true : undefined);
  }

  // The pointer on the bar or its edge strip. Shown already, it takes at
  // once; hidden, after openDelay; leaving, after closeDelay
  function setHover(id, on) {
    const bar = root._bar(id);
    if (!bar)
      return;
    if ((root._hover[id] === true) === on) {
      root._pendingHover = Utils.withEntry(root._pendingHover, id, undefined);
      root._schedule();
      return;
    }
    const delay = on ? (root.shownOf(bar) ? 0 : bar.timing.openDelay) : bar.timing.closeDelay;
    if (delay <= 0) {
      root._pendingHover = Utils.withEntry(root._pendingHover, id, undefined);
      root._hover = Utils.withEntry(root._hover, id, on ? true : undefined);
    } else {
      root._pendingHover = Utils.withEntry(root._pendingHover, id, {
        "on": on,
        "at": Date.now() + delay
      });
    }
    root._schedule();
  }

  // Something keeps the bar shown while on (`key`: "popout", "menu",
  // "editor"); let go, it stays closeDelay longer, as the pointer leaving
  // it would
  function hold(id, key, on) {
    const keys = Object.assign({}, root._holds[id] ?? {});
    if ((keys[key] === true) === on)
      return;
    if (on)
      keys[key] = true;
    else
      delete keys[key];
    root._holds = Utils.withEntry(root._holds, id, Object.keys(keys).length > 0 ? keys : undefined);
    const bar = root._bar(id);
    if (!on && bar)
      root.reveal(id, bar.timing.closeDelay);
  }

  // Shows the bar for `ms` (at least until any moment already under way ends)
  function reveal(id, ms) {
    if (!root._bar(id)?.autoHiding || ms <= 0)
      return;
    const at = Math.max(root._until[id] ?? 0, Date.now() + ms);
    root._until = Utils.withEntry(root._until, id, at);
    if (root._momentary[id] !== true)
      root._momentary = Utils.withEntry(root._momentary, id, true);
    root._schedule();
  }

  // A widget on the bar has news (BarWidgetHost): shown for revealFor with
  // revealOnActivity, unless the bar was only just made
  function attention(id) {
    const bar = root._bar(id);
    if (!bar?.autoHiding || !bar.revealOnActivity)
      return;
    if (Date.now() - (root._born[id] ?? 0) < root._settleMs)
      return;
    root.reveal(id, bar.revealFor);
  }

  function setPinned(id, on) {
    if ((root._pinned[id] === true) !== on)
      root._pinned = Utils.withEntry(root._pinned, id, on ? true : undefined);
  }

  // Unpinned and hidden now: hover, moments and pending changes dropped
  // (holds and coverage stay, being facts about the bar)
  function hideNow(id) {
    root.setPinned(id, false);
    root._hover = Utils.withEntry(root._hover, id, undefined);
    root._momentary = Utils.withEntry(root._momentary, id, undefined);
    root._until = Utils.withEntry(root._until, id, undefined);
    root._pendingHover = Utils.withEntry(root._pendingHover, id, undefined);
    root._schedule();
  }

  // --- The one timer ---

  function _schedule() {
    const deadlines = Object.values(root._until).concat(Object.values(root._pendingHover).map(p => p.at));
    if (deadlines.length === 0) {
      root._timer.stop();
      return;
    }
    root._timer.interval = Math.max(1, Math.min(...deadlines) - Date.now());
    root._timer.restart();
  }

  function _due() {
    const now = Date.now();
    Object.keys(root._until).forEach(id => {
      if (root._until[id] <= now) {
        root._until = Utils.withEntry(root._until, id, undefined);
        root._momentary = Utils.withEntry(root._momentary, id, undefined);
      }
    });
    Object.keys(root._pendingHover).forEach(id => {
      const pending = root._pendingHover[id];
      if (pending.at <= now) {
        root._pendingHover = Utils.withEntry(root._pendingHover, id, undefined);
        root._hover = Utils.withEntry(root._hover, id, pending.on ? true : undefined);
      }
    });
    root._schedule();
  }

  property Timer _timer: Timer {
    repeat: false
    onTriggered: root._due()
  }

  // --- Workspace changes (revealOnWorkspace) ---

  // Each output's active and special workspace as last seen ({ name:
  // "id/special" }); the first look only records them
  property var _workspaces: null

  function _checkWorkspaces() {
    const now = CompositorManager.outputs.reduce((all, out) => {
      all[out.name] = out.activeWorkspaceId + "/" + out.specialWorkspaceId;
      return all;
    }, {});
    const before = root._workspaces;
    root._workspaces = now;
    if (before === null)
      return;
    Object.keys(now).forEach(name => {
      if (before[name] === undefined || before[name] === now[name])
        return;
      ScreenEdgeManager.bars.filter(bar => bar.monitor === name && bar.enabled && bar.autoHiding && bar.revealOnWorkspace).forEach(bar => root.reveal(bar.id, bar.revealFor));
    });
  }

  property Connections _compositor: Connections {
    target: CompositorManager
    function onOutputsChanged() {
      root._checkWorkspaces();
    }
  }

  // --- Hidden by a window rule ---

  // The ids of the bars hidden by a window rule, as last seen
  property var _ruleHidden: ({})

  function _checkRuleHidden() {
    const was = root._ruleHidden;
    const now = {};
    ScreenEdgeManager.bars.filter(bar => bar.hiddenByRule).forEach(bar => {
      now[bar.id] = true;
    });
    // Set first: hideNow rebuilds the bars and re-enters this
    root._ruleHidden = now;
    Object.keys(now).filter(id => was[id] !== true).forEach(id => root.hideNow(id));
  }

  property Connections _edges: Connections {
    target: ScreenEdgeManager
    function onBarsChanged() {
      root._checkRuleHidden();
    }
  }

  Component.onCompleted: {
    root._checkWorkspaces();
    root._checkRuleHidden();
  }

  // --- IPC (`axiom ipc bar …`; the keybind action `bar`) ---

  // The running auto-hiding bars a call means: a bar's config id (on
  // every monitor it's on), or "" / "focused", those on the focused
  // monitor
  function _barsFor(id) {
    const auto = ScreenEdgeManager.bars.filter(bar => bar.enabled && bar.autoHiding);
    if (id === "" || id === "focused")
      return auto.filter(bar => bar.monitor === CompositorManager.focusedOutput);
    const bars = auto.filter(bar => bar.sourceId === id);
    if (bars.length === 0)
      throw {
        "kind": "not_found",
        "message": "no running auto-hiding bar " + id
      };
    return bars;
  }

  property IpcTarget _ipc: IpcTarget {
    target: "bar"
    enabled: !Paths.greeter

    // Shows it for its revealFor
    function reveal(id: string): void {
      root._barsFor(id).forEach(bar => root.reveal(bar.id, bar.revealFor));
    }

    // Pins it shown, reserving its space, or unpins it (all of them pinned
    // when any isn't)
    function toggle(id: string): void {
      const bars = root._barsFor(id);
      const pin = bars.some(bar => root._pinned[bar.id] !== true);
      bars.forEach(bar => root.setPinned(bar.id, pin));
    }

    // Unpins and hides it now (what holds it, an open popout, still does)
    function hide(id: string): void {
      root._barsFor(id).forEach(bar => root.hideNow(bar.id));
    }
  }
}
