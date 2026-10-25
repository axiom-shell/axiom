pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.services.ui
import qs.components.reusable

// i18n: keys from the schema (x-hookup `where`, x-hookupNote)
// Hooking a theme integration up to its app (its schema `x-hookup`): per
// config file, the text that loads axiom's file, to copy, and what Apply
// does to that file (back it up, then add the text where it's read last
// or where the format needs it), then Apply. Copy-only targets (configs
// in code, like wezterm.lua) just say where the text goes.
Rectangle {
  id: root

  // The ThemeIntegrations key
  required property string integration
  // Whether the integration is on (Settings passes its unsaved value)
  property bool active: ThemeIntegrations[root.integration] === true
  // The line beside the status chip, set up and not (the Hyprland page's
  // own targets say what their lines do)
  property string doneText: I18n.tr("axiom's file is loaded from your config.")
  property string todoText: I18n.tr("Load axiom's file from your config: copy the text, or Apply to add it for you.")

  readonly property var rows: IntegrationHookupManager.status[root.integration]?.targets ?? []
  readonly property var results: IntegrationHookupManager.results[root.integration] ?? []
  readonly property bool busy: IntegrationHookupManager.busy[root.integration] === true
  readonly property string note: IntegrationHookupManager.note(root.integration)

  // Targets Apply would change
  readonly property var pending: root.rows.filter(t => !t.copyOnly && !t.skipped && !t.done && t.conflicts.length === 0)
  readonly property bool applicable: root.rows.some(t => !t.copyOnly && !t.skipped)
  readonly property bool allDone: IntegrationHookupManager.isDone(root.integration)

  visible: root.active && IntegrationHookupManager.targets(root.integration).length > 0
  implicitHeight: body.implicitHeight + Widget.padding * 2
  radius: Widget.radius
  color: Qt.alpha(Theme.backgroundHighlight, 0.5)

  onVisibleChanged: if (visible)
    IntegrationHookupManager.check(root.integration)
  Component.onCompleted: if (visible)
    IntegrationHookupManager.check(root.integration)

  // What Apply does to one target, a line each
  function outline(t) {
    if (t.skipped === "requires")
      return [I18n.tr("Skipped: {0} isn't installed.", t.requires)];
    if (t.skipped === "shell")
      return [I18n.tr("Your shell isn't zsh, bash or fish: add the line to its startup file yourself.")];
    if (t.skipped === "profiles")
      return [I18n.tr("No browser profile found: start the browser once, then check again.")];
    if (t.skipped === "readonly")
      return [t.link ? I18n.tr("Skipped: {0} is a link to {1}, which you can't change. Add the text to a file of your own.", t.path, t.resolved) : I18n.tr("Skipped: you can't change {0}. Add the text yourself.", t.path)];
    if (t.copyOnly)
      return [];
    if (t.place === "copy")
      return t.done ? [I18n.tr("{0} is in place (Apply never overwrites it).", t.path)] : [I18n.tr("Copies axiom's module to {0}.", t.path)];
    if (t.done)
      return [I18n.tr("Already set up in {0}.", t.path)];
    if (t.conflicts.length > 0)
      return [I18n.tr("{0} already sets this ({1}): add axiom's file to it yourself.", t.path, t.conflicts.join(", "))];
    if (t.wraps)
      return [I18n.tr("{0} is a link to {1}, which you can't change: Apply replaces the link with a file that loads {1}, then axiom's file after it.", t.path, t.resolved), I18n.tr("The link is kept as {0}.", t.path + ".axiom-bak-<date>")];
    const lines = [];
    if (t.link)
      lines.push(I18n.tr("{0} is a link to {1}: that file is the one changed, and the link stays.", t.path, t.resolved));
    lines.push(t.exists ? I18n.tr("Backs up {0} to {1}.", t.resolved, t.resolved + ".axiom-bak-<date>") : I18n.tr("Creates {0}.", t.path));
    if (t.note)
      lines.push(I18n.tr(t.note));
    else if (t.place === "end")
      lines.push(I18n.tr("Adds the text at the end, so it's read last and wins over earlier settings."));
    else if (t.place === "start")
      lines.push(I18n.tr("Adds the text at the top: CSS imports must come before any rule, so your own rules still win over it."));
    else if (t.place === "top")
      lines.push(I18n.tr("Adds the text to the top-level settings, before the first [section]."));
    else if (t.place === "section")
      lines.push(t.createsSection ? I18n.tr("Adds a [{0}] section with the text at the end.", t.section) : I18n.tr("Adds the text at the end of the [{0}] section.", t.section));
    else if (t.place === "shellrc")
      lines.push(t.shell === "fish" ? I18n.tr("Fish reads it at startup: new shells pick it up.") : I18n.tr("Adds the text at the end: new shells pick it up."));
    for (const line of t.replaces)
      lines.push(I18n.tr("Comments out {0}, which sets the same thing.", line));
    for (const line of t.alongside)
      lines.push(I18n.tr("Leaves {0} as it is: axiom's line comes after it.", line));
    return lines;
  }

  ColumnLayout {
    id: body
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StatusChip {
        text: root.rows.length === 0 ? I18n.tr("Checking") : root.allDone ? I18n.tr("Set up") : root.applicable ? I18n.tr("Not set up") : I18n.tr("Copy the text")
        color: root.allDone ? Theme.success : root.pending.length > 0 ? Theme.warning : Theme.foregroundAlt
      }

      StyledText {
        Layout.fillWidth: true
        text: root.allDone ? root.doneText : root.applicable ? root.todoText : I18n.tr("This app's config is code: copy the text into it.")
        textColor: Theme.foregroundAlt
        wrapMode: Text.WordWrap
      }

      FlatIconButton {
        iconText: "refresh"
        tooltipText: I18n.tr("Check again")
        enabled: !root.busy
        onClicked: IntegrationHookupManager.check(root.integration)
      }
    }

    StyledText {
      Layout.fillWidth: true
      visible: root.note !== ""
      text: root.note === "" ? "" : I18n.tr(root.note)
      textColor: Theme.foregroundAlt
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.rows.length

      delegate: ColumnLayout {
        id: target
        required property int index
        readonly property var t: root.rows[index] ?? ({})
        readonly property var lines: root.outline(target.t)
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        StyledText {
          Layout.fillWidth: true
          visible: text !== ""
          text: target.t.copyOnly ? I18n.tr(target.t.where ?? "") : target.t.title ? I18n.tr("{0}: {1}", I18n.tr(target.t.title), target.t.path ?? "") : target.t.path ?? ""
          font.bold: true
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          visible: (target.t.text ?? "") !== "" && !target.t.done
          spacing: Widget.spacing / 2

          StyledTextArea {
            Layout.fillWidth: true
            text: target.t.text ?? ""
            readOnly: true
            expandable: true
            minHeight: 0
            horizontalMargin: Widget.padding
            verticalMargin: Widget.padding / 2
            input.font.family: "monospace"
          }

          SquareIconButton {
            size: Widget.height - Widget.px(6)
            iconText: "content_copy"
            tooltipText: I18n.tr("Copy")
            onClicked: ClipboardManager.copyText(target.t.text)
          }
        }

        StyledText {
          Layout.fillWidth: true
          visible: target.lines.length > 0
          text: target.lines.map(line => "• " + line).join("\n")
          textColor: target.t.done ? Theme.success : target.t.conflicts?.length > 0 ? Theme.warning : Theme.foreground
          wrapMode: Text.WordWrap
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      visible: root.pending.length > 0
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Nothing else is changed. To undo it, put the backup back.")
        textColor: Theme.foregroundAlt
        wrapMode: Text.WordWrap
      }

      StyledTextButton {
        text: root.busy ? I18n.tr("Applying…") : I18n.tr("Apply")
        iconText: "done"
        onClicked: if (!root.busy)
          IntegrationHookupManager.apply(root.integration)
      }
    }

    // The last Apply: where each file was backed up, or what went wrong
    StyledText {
      Layout.fillWidth: true
      readonly property var changed: root.results.filter(r => r.changed || r.error)
      visible: changed.length > 0
      text: changed.map(r => r.error ? I18n.tr("{0}: {1}", r.path, r.error === "conflict" ? I18n.tr("already set, left alone") : r.error) : r.backup ? I18n.tr("Changed {0} (backup: {1})", r.path, r.backup) : I18n.tr("Created {0}", r.path)).join("\n")
      textColor: changed.some(r => r.error) ? Theme.error : Theme.success
      wrapMode: Text.WordWrap
    }
  }
}
