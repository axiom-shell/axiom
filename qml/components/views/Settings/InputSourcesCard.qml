pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.system
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// The Input section's first card (its `x-card`): the input sources
// (Input.sources) as edited, saved or not, through the settings draft: the
// keyboard layouts (added from the xkb registry, layout and variant) and,
// while axiom manages the input method (Input.method.enabled), the engines
// (added from the running framework's), in order, each moved or removed,
// an engine's typing layout picked. Off, it lists the layouts alone, and
// with fcitx5 or ibus running offers to manage it. On, which framework
// runs, and a choice of which list wins while turning managing on with a
// framework whose list differs, or after an edit in fcitx5-configtool:
// take its list into the draft (InputSourceManager.importFromFramework),
// or give it axiom's (Save; useOwn after an outside edit).
FieldGroup {
  id: root

  // The sources as edited, saved or not
  readonly property var sources: SettingsManager.localConfig?.Input?.sources ?? InputConfig.sources
  // Managing the input method, as edited
  readonly property bool managing: SettingsManager.configValueAt("Input.method.enabled") === true
  // Being turned on: the framework isn't given anything until Save
  readonly property bool turningOn: root.managing && !InputConfig.savedMethodEnabled
  // The sources' indices the card lists: the xkb ones alone while off
  readonly property var shown: root.sources.map((s, i) => root.managing || s.kind === "xkb" ? i : -1).filter(i => i >= 0)
  readonly property var registry: InputSourceManager.registry
  readonly property string framework: InputSourceManager.detectedFramework
  // The framework asked for, as edited ("fcitx5", "ibus", "auto", "none")
  readonly property string chosen: String(SettingsManager.configValueAt("Input.method.framework") ?? "")
  // Installed: true, false, or undefined until checked
  readonly property var hasFcitx5: DependencyManager.has("fcitx5")
  readonly property var hasIbus: DependencyManager.has("ibus-daemon")
  // "Use axiom's" picked while turning on (asked again after a Discard)
  property bool answered: false
  onTurningOnChanged: root.answered = false
  // Which list wins: turning on with a framework whose list isn't the
  // sources', or after an edit made outside axiom
  readonly property string asks: {
    if (!InputSourceManager.detected)
      return "";
    if (root.turningOn && !root.answered && !InputSourceManager.matches(root.sources))
      return "first";
    if (root.managing && InputConfig.savedMethodEnabled && InputSourceManager.outsideEdit)
      return "outside";
    return "";
  }
  // The xkb layouts an engine can type on: { value: "layout|variant",
  // label }, the distinct ones of the xkb sources
  readonly property var typingLayouts: {
    const out = [];
    for (const s of root.sources) {
      if (s.kind !== "xkb" || String(s.layout ?? "") === "")
        continue;
      const value = s.layout + "|" + (s.variant ?? "");
      if (!out.some(o => o.value === value))
        out.push({
          "value": value,
          "label": InputSources.describe(root.registry, s.layout, s.variant)
        });
    }
    return out;
  }

  Component.onCompleted: DependencyManager.check(["fcitx5", "ibus-daemon"])

  function setSources(list) {
    SettingsManager.setValue(["Input", "sources"], list);
  }

  function addLayout(layout, variant) {
    const list = Utils.clone(root.sources);
    list.push({
      "id": InputSources.freeId(list, variant !== "" ? layout + "-" + variant : layout),
      "kind": "xkb",
      "layout": layout,
      "variant": variant,
      "engine": ""
    });
    root.setSources(list);
  }

  function addEngine(name) {
    const list = Utils.clone(root.sources);
    list.push({
      "id": InputSources.freeId(list, name),
      "kind": "ime",
      "layout": "",
      "variant": "",
      "engine": name
    });
    root.setSources(list);
  }

  function edit(index, changes) {
    const list = Utils.clone(root.sources);
    Object.assign(list[index], changes);
    root.setSources(list);
  }

  // Swaps the listed row `row` with the one `by` rows away (the sources
  // hidden while off keep their places)
  function move(row, by) {
    const a = root.shown[row];
    const b = root.shown[row + by];
    if (a === undefined || b === undefined)
      return;
    const list = Utils.clone(root.sources);
    const moved = list[a];
    list[a] = list[b];
    list[b] = moved;
    root.setSources(list);
  }

  function remove(index) {
    root.setSources(root.sources.filter((_, i) => i !== index));
  }

  // The framework's engine a source is (its `available` entry), or null
  function engineOf(source) {
    const name = InputSources.imName(source, root.framework, root.registry);
    return InputSourceManager.available.find(a => a.name === name) ?? null;
  }

  // Off, with a framework running: offer to manage it
  RowLayout {
    visible: !root.managing && InputSourceManager.detected
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledIcon {
      text: "translate"
      textColor: Theme.foregroundAlt
    }

    StyledText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      textSize: Appearance.fontSizeBy(-1)
      text: I18n.tr("{0} is running: let axiom manage it?", root.framework)
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Manage it")
      onClicked: SettingsManager.setValue(["Input", "method", "enabled"], true)
    }
  }

  // On: which framework runs, or why none does
  RowLayout {
    visible: root.managing
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      text: InputSourceManager.detected ? root.framework : root.chosen === "none" ? I18n.tr("Off") : I18n.tr("Not running")
      color: InputSourceManager.detected ? Theme.success : root.chosen === "none" ? Theme.foregroundAlt : Theme.warning
    }

    StyledText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      textSize: Appearance.fontSizeBy(-1)
      text: {
        if (InputSourceManager.detected)
          return I18n.tr("{0} is running: its engines can be added below, and it gets these sources.", root.framework);
        if (root.chosen === "none")
          return I18n.tr("No input method framework is used (Input method, below): only keyboard layouts switch.");
        const wanted = root.chosen === "ibus" ? root.hasIbus : root.chosen === "fcitx5" ? root.hasFcitx5 : (root.hasFcitx5 === true || root.hasIbus === true ? true : root.hasFcitx5 === false && root.hasIbus === false ? false : undefined);
        if (wanted === false)
          return root.chosen === "auto" ? I18n.tr("Neither fcitx5 nor ibus is installed: install fcitx5 to type Japanese, Chinese, Korean and more.") : I18n.tr("{0} isn't installed: install it to type Japanese, Chinese, Korean and more.", root.chosen);
        return root.chosen === "auto" ? I18n.tr("No input method framework is running.") : I18n.tr("{0} isn't running.", root.chosen);
      }
    }
  }

  // The framework's list isn't axiom's: which wins
  StyledContainer {
    visible: root.asks !== ""
    Layout.fillWidth: true
    implicitHeight: askColumn.implicitHeight + Widget.padding * 1.5
    backgroundColor: Qt.alpha(Theme.warning, 0.12)
    borderColor: Theme.warning

    ColumnLayout {
      id: askColumn
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Widget.padding * 0.75
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.asks === "outside" ? I18n.tr("{0}'s list was changed outside axiom since axiom gave it these sources.", root.framework) : I18n.tr("{0} has a list of its own that isn't these sources. Which should it keep?", root.framework)
      }

      RowLayout {
        spacing: Widget.spacing

        StyledTextButton {
          implicitHeight: Widget.height - Widget.px(4)
          text: I18n.tr("Use {0}'s list", root.framework)
          iconText: "download"
          onClicked: {
            const imported = InputSourceManager.importFromFramework();
            if (imported.length > 0)
              root.setSources(imported);
          }
        }

        StyledTextButton {
          implicitHeight: Widget.height - Widget.px(4)
          text: I18n.tr("Use axiom's")
          iconText: "upload"
          onClicked: {
            if (root.asks === "outside")
              InputSourceManager.useOwn();
            else
              root.answered = true;
          }
        }
      }

      StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        text: root.asks === "outside" ? I18n.tr("Using its list puts it here unsaved: Save to keep it. Using axiom's gives {0} these sources again now.", root.framework) : I18n.tr("Using its list puts it here unsaved. Either way, {0} gets these sources when you Save.", root.framework)
      }
    }
  }

  StyledText {
    visible: root.shown.length === 0
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
    text: I18n.tr("No input sources: the compositor types on us. Add a layout below.")
  }

  Repeater {
    model: root.shown.length

    delegate: StyledContainer {
      id: row
      // The listed row, and the source's index in the list
      required property int index
      readonly property int at: root.shown[index] ?? -1
      readonly property var source: root.sources[at] ?? {}
      readonly property bool ime: source.kind === "ime"
      readonly property var engine: ime ? root.engineOf(source) : null

      Layout.fillWidth: true
      implicitHeight: rowLayout.implicitHeight + Widget.smallPadding * 2
      backgroundColor: Theme.background

      RowLayout {
        id: rowLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Widget.padding
        anchors.rightMargin: Widget.smallPadding
        spacing: Widget.spacing

        StyledIcon {
          text: row.ime ? "translate" : "keyboard"
          textColor: Theme.foregroundAlt
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: row.ime ? (row.engine?.displayName || row.source.engine) : InputSources.describe(root.registry, row.source.layout, row.source.variant)
          }

          StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textColor: row.ime && InputSourceManager.running && !row.engine ? Theme.warning : Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-2)
            text: {
              if (!row.ime)
                return [row.source.layout, row.source.variant].filter(t => t).join(" ");
              if (InputSourceManager.running && !row.engine)
                return I18n.tr("{0}: not installed in {1}", row.source.engine, root.framework);
              return row.source.engine;
            }
          }
        }

        // An engine's typing layout: one of the xkb sources', or the first
        StyledText {
          visible: row.ime
          text: I18n.tr("Types on")
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
        }

        StyledComboEntry {
          id: typing
          readonly property string own: String(row.source.layout ?? "") === "" ? "" : row.source.layout + "|" + (row.source.variant ?? "")
          visible: row.ime
          Layout.preferredWidth: Widget.px(200)
          Layout.preferredHeight: Widget.height
          options: {
            const list = [
              {
                "value": "",
                "label": I18n.tr("The first layout")
              }
            ].concat(root.typingLayouts);
            // One no xkb source has (taken from a framework's list) stays shown
            if (typing.own !== "" && !list.some(o => o.value === typing.own))
              list.push({
                "value": typing.own,
                "label": InputSources.describe(root.registry, row.source.layout, row.source.variant)
              });
            return list;
          }
          value: typing.own
          onPicked: value => {
            const at = value.indexOf("|");
            root.edit(row.at, at < 0 ? {
              "layout": "",
              "variant": ""
            } : {
              "layout": value.slice(0, at),
              "variant": value.slice(at + 1)
            });
          }
        }

        StyledIconButton {
          iconText: "arrow_upward"
          tooltipText: I18n.tr("Move up")
          enabled: row.index > 0
          size: Widget.height - Widget.px(4)
          onClicked: root.move(row.index, -1)
        }

        StyledIconButton {
          iconText: "arrow_downward"
          tooltipText: I18n.tr("Move down")
          enabled: row.index < root.shown.length - 1
          size: Widget.height - Widget.px(4)
          onClicked: root.move(row.index, 1)
        }

        StyledIconButton {
          iconText: "close"
          tooltipText: I18n.tr("Remove")
          hoverColor: Theme.error
          size: Widget.height - Widget.px(4)
          onClicked: root.remove(row.at)
        }
      }
    }
  }

  // Adding: a layout from the registry, an engine from the framework's
  GridLayout {
    Layout.fillWidth: true
    columns: root.managing && root.width > Widget.px(560) ? 2 : 1
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing / 2

      StyledText {
        text: I18n.tr("Add a keyboard layout")
        font.bold: true
      }

      StyledComboEntry {
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        editable: true
        icon: "keyboard"
        enabled: root.registry !== null
        placeholderText: root.registry !== null ? I18n.tr("Search layouts (German, dvorak, jp…)") : I18n.tr("Reading the layouts…")
        search: query => InputSources.searchLayouts(root.registry, query, 60).map(row => ({
                "value": row.layout + "|" + row.variant,
                "label": row.description + "  ·  " + [row.layout, row.variant].filter(t => t).join(" ")
              }))
        value: ""
        onPicked: value => {
          const at = value.indexOf("|");
          if (at > 0)
            root.addLayout(value.slice(0, at), value.slice(at + 1));
        }
      }
    }

    ColumnLayout {
      visible: root.managing
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing / 2

      StyledText {
        text: I18n.tr("Add an input method")
        font.bold: true
      }

      StyledComboEntry {
        id: enginePicker
        // The engines installed, but the keyboard layouts fcitx5 lists as
        // engines too and those already added
        readonly property var engines: InputSourceManager.available.filter(a => !String(a.name).startsWith("keyboard-") && !String(a.name).startsWith("xkb:") && !root.sources.some(s => s.kind === "ime" && s.engine === a.name))
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        editable: true
        icon: "translate"
        enabled: InputSourceManager.running && enginePicker.engines.length > 0
        placeholderText: !InputSourceManager.running ? I18n.tr("Needs fcitx5 or ibus running") : enginePicker.engines.length > 0 ? I18n.tr("Search engines (Mozc, Pinyin, Hangul…)") : I18n.tr("Every installed engine is added")
        options: enginePicker.engines.map(a => ({
              "value": a.name,
              "label": (a.displayName || a.name) + (a.lang ? "  ·  " + a.lang : "")
            }))
        value: ""
        onPicked: value => {
          if (enginePicker.engines.some(a => a.name === value))
            root.addEngine(value);
        }
      }

      StyledText {
        visible: !InputSourceManager.running
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        text: I18n.tr("Input methods (Japanese, Chinese, Korean, …) are engines of fcitx5 or ibus: start one to pick from the engines it has installed.")
      }
    }
  }
}
