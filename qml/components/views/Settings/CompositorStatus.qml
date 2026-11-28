pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.services.session
import qs.services.system
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// The top of the Compositor card (the section's `x-intro`, its `mode` the
// setup row under it): the mode in effect and what it needs, and, while a
// new mode waits for Save (`x-applyOnSave`), what saving will do. `status`
// and `statusTone` are the card's header chip
ColumnLayout {
  id: root

  readonly property string mode: CompositorConfigManager.mode
  readonly property string stage: CompositorConfigManager.status
  // The mode picked in the settings draft (the defaults' while the mode is
  // the daemon's: config.json doesn't load, so nothing was picked)
  readonly property string pendingMode: CompositorConfigManager.modeFromDaemon ? root.mode : (SettingsManager.localConfig?.Compositor?.mode ?? root.mode)
  readonly property bool pending: root.pendingMode !== root.mode

  function _checkPending() {
    if (root.pendingMode === "managed")
      CompositorConfigManager.checkManaged();
  }
  onPendingModeChanged: root._checkPending()
  Component.onCompleted: {
    root._checkPending();
    root._checkAutostart();
  }

  // Whether the user's config starts axiom (checked when the card is
  // built and when the mode changes; managed starts it itself)
  readonly property bool autostartMissing: root.mode !== "managed" && IntegrationHookupManager.status.compositorAutostart !== undefined && !IntegrationHookupManager.isDone("compositorAutostart")
  readonly property bool autostartAdded: (IntegrationHookupManager.results.compositorAutostart ?? []).some(result => result.changed)

  function _checkAutostart() {
    if (root.mode !== "managed")
      IntegrationHookupManager.check("compositorAutostart");
  }
  onModeChanged: root._checkAutostart()

  // I18n.tr("Detached") I18n.tr("Included") I18n.tr("Managed")
  function _modeLabel(mode) {
    return I18n.tr(mode.charAt(0).toUpperCase() + mode.slice(1));
  }

  readonly property string statusTone: {
    switch (root.stage) {
    case "loaded":
    case "runtime":
      return "success";
    case "fallback":
      return "warning";
    }
    return "neutral";
  }

  readonly property string status: {
    switch (root.stage) {
    case "runtime":
      return I18n.tr("Applied at runtime");
    case "loaded":
      return I18n.tr("Loaded");
    case "fallback":
      return I18n.tr("Not loaded");
    }
    return I18n.tr("Checking…");
  }

  // What saving the pending mode does, step by step
  readonly property var saveSteps: {
    const steps = [];
    const managed = Paths.shortenHome(CompositorConfigManager.managedPath);
    const user = Paths.shortenHome(CompositorConfigManager.userDir);
    const files = Paths.shortenHome(CompositorConfigManager.userFiles);
    const module = Paths.shortenHome(CompositorConfigManager.includePath);
    const compositor = CompositorManager.displayName;
    // Leaving a mode gives back what it took (CompositorConfigManager._leave)
    if (root.mode === "managed")
      steps.push(I18n.tr("Gives {0} back: your previous one returns (in {1}, or the example config's backup), else a new one that starts axiom and loads {2}", managed, user, files));
    if (root.mode === "included")
      steps.push(I18n.tr("Empties {0}, so a config that still loads it gets nothing", module));
    if (root.pendingMode === "managed") {
      switch (CompositorConfigManager.managedCheck) {
      case "adopt":
        steps.push(I18n.tr("Asks for your approval (Allow takeover) before it touches your {0}", managed));
        steps.push(I18n.tr("Then moves your {0} into {1}, where it keeps working, with a dated backup beside it", managed, user));
        break;
      case "stock":
        steps.push(I18n.tr("Replaces the example config {0}, keeping a dated backup beside it: its binds and monitor rule would fight axiom's", managed));
        break;
      case "released":
        steps.push(I18n.tr("Replaces {0}, which axiom wrote when it last left managed mode", managed));
        break;
      case "ours":
        steps.push(I18n.tr("Takes back {0}, which axiom already wrote", managed));
        break;
      case "":
        steps.push(I18n.tr("Checking {0}…", Paths.shortenHome(CompositorConfigManager.configDir)));
        break;
      }
      steps.push(I18n.tr("Writes {0} from the cards below, loading {1} after it", managed, files));
      steps.push(I18n.tr("Reloads {0}", compositor));
    } else if (root.pendingMode === "included") {
      steps.push(I18n.tr("Writes {0}", module));
      steps.push(I18n.tr("Shows the lines to add to your config. Until you do, axiom applies its layer at runtime"));
    } else {
      steps.push(I18n.tr("Applies axiom's layer at runtime"));
    }
    if (root.mode === "managed")
      steps.push(I18n.tr("Reloads {0}", compositor));
    return steps;
  }

  // The Recommended setup list is offered once after a save into managed
  // mode (RecommendedSetupManager.offered); its button reads Close once an
  // Apply has finished
  readonly property bool offersRecommended: RecommendedSetupManager.offered && root.mode === "managed" && !root.pending
  readonly property var _recommendedStates: RecommendedSetupManager.ids.map(id => RecommendedSetupManager.rows[id].state)
  readonly property bool recommendedRan: root._recommendedStates.some(state => state !== "idle") && !root._recommendedStates.some(state => state === "pending" || state === "running")

  readonly property bool blocked: root.pendingMode === "managed" && CompositorConfigManager.managedCheck === "blocked"

  spacing: Widget.spacing * 1.5

  StyledText {
    text: I18n.tr("In effect: {0}", root._modeLabel(root.mode))
    tone: "muted"
  }

  // -- A mode change waiting for Save --

  Notice {
    id: pendingBox
    status: root.blocked ? "error" : "accent"
    icon: root.blocked ? "error" : "info"
    visible: root.pending
    title: root.blocked ? I18n.tr("Can't switch to Managed") : I18n.tr("Save switches to {0}:", root._modeLabel(root.pendingMode))
    text: root.blocked ? (CompositorConfigManager.managedBlockedBy === "elsewhere" ? CompositorConfigManager.elsewhereReason : CompositorConfigManager.managedBlockedBy === "git" ? I18n.tr("{0} is inside the git repository at {1}, so axiom won't take it over. Use Included instead.", Paths.shortenHome(CompositorConfigManager.configDir), Paths.shortenHome(CompositorConfigManager.managedBlockedRepo)) : I18n.tr("{0} is a symlink or in a git repository, so axiom won't take it over. Use Included instead.", Paths.shortenHome(CompositorConfigManager.configDir))) : root.saveSteps.map(step => "•  " + step).join("\n")
  }

  // -- The mode in effect --

  // Managed waits for the user's go-ahead on this compositor
  Notice {
    id: approvalBox
    status: "warning"
    visible: CompositorConfigManager.takeoverPending && !root.pending
    title: I18n.tr("Managed mode needs your approval")
    text: I18n.tr("Taking over {0} moves your config into {1}, where it keeps working, with a dated backup beside it. Until then, axiom applies its layer at runtime. Included mode leaves your config alone.", Paths.shortenHome(CompositorConfigManager.managedPath), Paths.shortenHome(CompositorConfigManager.userDir))
    actionText: I18n.tr("Allow takeover")
    onTriggered: CompositorConfigManager.allowTakeover()
  }

  // The Recommended setup, once, after a save into managed mode: the callout
  // (its button closes it), then the list to apply
  Notice {
    id: recommendedBox
    status: "accent"
    visible: root.offersRecommended
    title: I18n.tr("Recommended setup")
    text: I18n.tr("Managed mode is on. Turn on the rest of what axiom can run for you: untick what you'd rather keep your own, then Apply.")
    actionText: root.recommendedRan ? I18n.tr("Close") : I18n.tr("Not now")
    onTriggered: RecommendedSetupManager.dismiss()
  }

  // Built only while offered: its begin() resets the shared state
  StreamedLoader {
    Layout.fillWidth: true
    wanted: root.offersRecommended
    sourceComponent: RecommendedSetupList {}
  }

  StyledText {
    visible: CompositorConfigManager.releaseProblem !== ""
    text: CompositorConfigManager.releaseProblem + "\n" + I18n.tr("axiom tries again by itself.")
    tone: "warning"
    role: "body"
    overflow: "wrap"
    Layout.fillWidth: true
  }

  StyledText {
    // Detached, a problem is only the runtime layer's (its binds went on unread)
    visible: (root.stage === "fallback" || root.mode === "detached" && CompositorConfigManager.problem !== "") && !CompositorConfigManager.takeoverPending
    text: CompositorConfigManager.problem + (root.stage === "fallback" ? "\n" + I18n.tr("Until then, axiom applies its layer at runtime.") : "")
    tone: "warning"
    role: "body"
    overflow: "wrap"
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.mode === "detached"
    text: I18n.tr("Detached: axiom changes none of your compositor's files and takes its binds and look away when it stops. Great for trying it out; for full-time use, pick Included or Managed.")
    role: "body"
    overflow: "wrap"
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.mode === "detached"
    text: root.autostartMissing ? I18n.tr("Binds on keys your config uses are skipped.") : I18n.tr("Nothing to set up. Binds on keys your config uses are skipped.")
    tone: "muted"
    role: "caption"
    overflow: "wrap"
    Layout.fillWidth: true
  }

  SetupLines {
    visible: root.mode === "included"
    // Where the writer puts it (its include target): at the top, where
    // the user's own lines after it win, or at the end (niri), where
    // axiom's look wins
    hint: {
      const target = CompositorConfigManager.includeTarget;
      const file = Paths.shortenHome(target?.file ?? CompositorConfigManager.managedPath);
      return target?.place === "end" ? I18n.tr("Add at the end of {0} (axiom's look wins; binds on keys you bind stay yours):", file) : I18n.tr("Add near the top of {0} (anything after overrides axiom):", file);
    }
    lines: CompositorConfigManager.includeLines
    // While it isn't loaded: adds the lines (with a backup), as the
    // notification's Add it for me does
    canAdd: root.stage !== "loaded" && CompositorConfigManager.includeTarget !== null
    adding: IntegrationHookupManager.busy.compositorModule > 0
    onCopyClicked: ClipboardManager.copyText(CompositorConfigManager.includeLines)
    onAddClicked: CompositorConfigManager.addIncludeLines()
  }

  // The modes that leave starting axiom to the user's config: shown while
  // its autostart line is missing (the compositorAutostart hookup's check),
  // and after Add it for me, until the next reload
  SetupLines {
    visible: root.mode !== "managed" && (root.autostartMissing || root.autostartAdded)
    hint: {
      const target = CompositorConfigManager.autostartTarget;
      const file = Paths.shortenHome(target?.file ?? CompositorConfigManager.managedPath);
      return target?.place === "start" ? I18n.tr("{0} doesn't start axiom with the session. Add near the top of {1}:", CompositorManager.displayName, file) : I18n.tr("{0} doesn't start axiom with the session. Add at the end of {1}:", CompositorManager.displayName, file);
    }
    lines: CompositorConfigManager.autostartLines
    canAdd: CompositorConfigManager.autostartTarget !== null
    adding: IntegrationHookupManager.busy.compositorAutostart > 0
    added: root.autostartAdded
    onCopyClicked: ClipboardManager.copyText(CompositorConfigManager.autostartLines)
    onAddClicked: CompositorConfigManager.addAutostartLines()
  }

  RowLayout {
    visible: root.mode === "managed"
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: I18n.tr("Your own settings go in {0}.", Paths.shortenHome(CompositorConfigManager.userFiles))
      tone: "muted"
      role: "caption"
      overflow: "wrap"
      Layout.fillWidth: true
    }

    StyledTextButton {
      text: I18n.tr("Open folder")
      onClicked: CompositorConfigManager.openConfigDir()
    }
  }

  StyledText {
    visible: root.pendingMode !== "managed"
    text: I18n.tr("Managed mode adds the compositor's own settings and what starts with the session.")
    tone: "muted"
    role: "caption"
    overflow: "wrap"
    Layout.fillWidth: true
  }
}
