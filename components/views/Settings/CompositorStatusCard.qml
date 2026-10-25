pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable

// The Compositor section's first card (its `x-card`): whether
// the mode is in effect and what it needs, and, while a new mode waits for
// Save (`x-applyOnSave`), what saving will do
FieldGroup {
  id: root

  readonly property string mode: CompositorConfigManager.mode
  readonly property string status: CompositorConfigManager.status
  // The mode picked in the settings draft
  readonly property string pendingMode: SettingsManager.localConfig?.Compositor?.mode ?? root.mode
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

  readonly property color statusColor: {
    switch (root.status) {
    case "loaded":
    case "runtime":
      return Theme.success;
    case "fallback":
      return Theme.warning;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
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

  readonly property bool blocked: root.pendingMode === "managed" && CompositorConfigManager.managedCheck === "blocked"

  // Lines for the user's config: where they go, the text, Copy, and Add it
  // for me (with a backup) while `canAdd`
  component SetupLines: ColumnLayout {
    id: block

    property string hint
    property string lines
    property bool canAdd
    property bool adding
    property bool added

    signal copyClicked
    signal addClicked

    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: block.hint
      opacity: 0.7
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledContainer {
      Layout.fillWidth: true
      implicitHeight: linesText.implicitHeight + Widget.padding * 2
      backgroundColor: Theme.background

      StyledText {
        id: linesText
        anchors.fill: parent
        anchors.margins: Widget.padding
        text: block.lines
        textFamily: "monospace"
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WrapAnywhere
      }
    }

    RowLayout {
      spacing: Widget.spacing

      StyledTextButton {
        implicitHeight: Widget.height - Widget.px(4)
        text: I18n.tr("Copy")
        onClicked: block.copyClicked()
      }

      StyledTextButton {
        visible: block.canAdd
        enabled: !block.adding && !block.added
        implicitHeight: Widget.height - Widget.px(4)
        text: block.added ? I18n.tr("Added") : block.adding ? I18n.tr("Adding…") : I18n.tr("Add it for me")
        onClicked: block.addClicked()
      }
    }
  }

  headerExtras: [
    StyledText {
      text: root._modeLabel(root.mode)
      opacity: 0.7
    },
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  // --- A mode change waiting for Save ---

  StyledContainer {
    visible: root.pending
    Layout.fillWidth: true
    implicitHeight: pendingColumn.implicitHeight + Widget.padding * 2
    backgroundColor: Theme.background
    borderColor: root.blocked ? Theme.error : Theme.accent

    ColumnLayout {
      id: pendingColumn
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Widget.padding
      spacing: Widget.spacing / 2

      StyledText {
        text: root.blocked ? I18n.tr("Can't switch to Managed") : I18n.tr("Save switches to {0}:", root._modeLabel(root.pendingMode))
        textColor: root.blocked ? Theme.error : Theme.accent
        font.bold: true
        Layout.fillWidth: true
      }

      StyledText {
        visible: root.blocked
        text: CompositorConfigManager.managedBlockedBy === "git" ? I18n.tr("{0} is inside the git repository at {1}, so axiom won't take it over. Use Included instead.", Paths.shortenHome(CompositorConfigManager.configDir), Paths.shortenHome(CompositorConfigManager.managedBlockedRepo)) : I18n.tr("{0} is a symlink or in a git repository, so axiom won't take it over. Use Included instead.", Paths.shortenHome(CompositorConfigManager.configDir))
        textSize: Appearance.fontSizeBy(-1)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      Repeater {
        model: root.blocked ? [] : root.saveSteps

        delegate: StyledText {
          required property string modelData
          text: "•  " + modelData
          textSize: Appearance.fontSizeBy(-1)
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }
      }
    }
  }

  // --- The mode in effect ---

  // Managed waits for the user's go-ahead on this compositor
  StyledContainer {
    visible: CompositorConfigManager.takeoverPending && !root.pending
    Layout.fillWidth: true
    implicitHeight: approvalColumn.implicitHeight + Widget.padding * 2
    backgroundColor: Theme.background
    borderColor: Theme.warning

    ColumnLayout {
      id: approvalColumn
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Widget.padding
      spacing: Widget.spacing / 2

      StyledText {
        text: I18n.tr("Managed mode needs your approval")
        textColor: Theme.warning
        font.bold: true
        Layout.fillWidth: true
      }

      StyledText {
        text: I18n.tr("Taking over {0} moves your config into {1}, where it keeps working, with a dated backup beside it. Until then, axiom applies its layer at runtime. Included mode leaves your config alone.", Paths.shortenHome(CompositorConfigManager.managedPath), Paths.shortenHome(CompositorConfigManager.userDir))
        textSize: Appearance.fontSizeBy(-1)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      StyledTextButton {
        implicitHeight: Widget.height - Widget.px(4)
        text: I18n.tr("Allow takeover")
        onClicked: CompositorConfigManager.allowTakeover()
      }
    }
  }

  StyledText {
    visible: CompositorConfigManager.releaseProblem !== ""
    text: CompositorConfigManager.releaseProblem + "\n" + I18n.tr("axiom tries again by itself.")
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.status === "fallback" && !CompositorConfigManager.takeoverPending
    text: CompositorConfigManager.problem + "\n" + I18n.tr("Until then, axiom applies its layer at runtime.")
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.mode === "detached"
    text: root.autostartMissing ? I18n.tr("Binds on keys your config uses are skipped.") : I18n.tr("Nothing to set up. Binds on keys your config uses are skipped.")
    opacity: 0.7
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
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
    canAdd: root.status !== "loaded" && CompositorConfigManager.includeTarget !== null
    adding: IntegrationHookupManager.busy.compositorModule === true
    onCopyClicked: CompositorConfigManager.copyIncludeLines()
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
    adding: IntegrationHookupManager.busy.compositorAutostart === true
    added: root.autostartAdded
    onCopyClicked: CompositorConfigManager.copyAutostartLines()
    onAddClicked: CompositorConfigManager.addAutostartLines()
  }

  RowLayout {
    visible: root.mode === "managed"
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: I18n.tr("Your own settings go in {0}.", Paths.shortenHome(CompositorConfigManager.userFiles))
      opacity: 0.7
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Open folder")
      onClicked: CompositorConfigManager.openConfigDir()
    }
  }

  StyledText {
    visible: root.pendingMode !== "managed"
    text: I18n.tr("Managed mode adds the compositor's own settings and what starts with the session.")
    opacity: 0.6
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
}
