pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Custom widgets page, Module tab, between the strip and the canvas: the
// selected screen's form, two lines in one box (its name and whether the base
// shows under it, then when it is drawn), and nothing at all while the base is
// edited. A screen with no condition says only an action shows it and offers
// one that does. Below it, a line while the sample picks no screen.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var views: root.definition?.module?.views ?? []
  readonly property var view: root.views[root.editor.viewIndex] ?? null
  // Its "Go to" action exists already
  readonly property bool hasGoTo: root.view !== null && (root.definition?.actions?.items ?? []).some(a => a.kind === "axiom" && a.axiom === "screen:" + root.view.id)
  readonly property string formKey: root.view ? root.editor.selectedId + "/" + root.editor.viewIndex : ""
  // The paths a screen's condition can read, then the failure
  readonly property var keyOptions: [
    {
      "value": "",
      "label": I18n.tr("Only an action")
    },
    {
      "value": "state",
      "label": "state"
    },
    {
      "value": "error",
      "label": I18n.tr("error (the script failed)")
    }
  ].concat(root.editor.bindPaths.filter(p => p.type !== "array" && p.path !== "state").map(p => ({
        "value": p.path,
        "label": p.path
      })))
  // The tests, as the schema names them
  readonly property var testOptions: ["is", "isNot", "set", "unset"].map(value => ({
        "value": value,
        "label": ({
            "is": I18n.tr("Is one of"),
            "isNot": I18n.tr("Is none of"),
            "set": I18n.tr("Is set"),
            "unset": I18n.tr("Is not set")
          })[value]
      }))
  // The base is empty and the sample picks no screen: nothing to draw
  readonly property bool nothingDrawn: root.editor.viewIndex < 0 && root.views.length > 0 && root.editor.layerElements.length === 0 && CustomWidgetData.pickView(root.definition?.module, CustomWidgetsManager.fields[root.editor.selectedId] ?? null, null).index < 0

  Layout.fillWidth: true
  spacing: Widget.spacing

  // Rebuilt per screen (a form reused for another would write the old values onto it)
  KeyedLoader {
    visible: root.view !== null
    Layout.fillWidth: true
    Layout.preferredHeight: root.view !== null ? childrenRect.height : 0
    key: root.formKey

    sourceComponent: Surface {
      id: screen

      // The key it was made for (the loader's model): a flag raised for the
      // next form must not be taken by one that is going
      required property string modelData
      readonly property var when: root?.view?.when ?? ({})
      readonly property bool noKey: (screen.when.key ?? "") === ""
      readonly property bool listed: screen.when.test === "is" || screen.when.test === "isNot"
      // The two labels share a width, so Name and Show when start their fields at one edge
      readonly property real labelWidth: Math.max(nameLabel.implicitWidth, whenLabel.implicitWidth)

      width: parent?.width ?? 0
      height: lines.implicitHeight + Widget.smallPadding * 2
      tone: "surface"

      // A new screen (or Rename) takes the focus in its Name
      function focusName() {
        // (root is null while the form is torn down with the page)
        if (!root || !root.editor.focusScreenName || screen.modelData !== root.formKey)
          return;
        root.editor.focusScreenName = false;
        nameEntry.input.forceActiveFocus();
        nameEntry.input.selectAll();
      }
      Component.onCompleted: screen.focusName()
      Connections {
        target: root.editor
        function onFocusScreenNameChanged() {
          screen.focusName();
        }
      }

      ColumnLayout {
        id: lines
        anchors.fill: parent
        anchors.margins: Widget.smallPadding
        spacing: Widget.spacing

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledLabel {
            id: nameLabel
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: screen.labelWidth
            text: I18n.tr("Name")
          }
          StyledTextEntry {
            id: nameEntry
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.minimumWidth: Widget.px(120)
            onTextEdited: root.editor.setView(["name"], nameEntry.text)
            Binding {
              target: nameEntry
              property: "text"
              value: root.view?.name ?? ""
              when: !nameEntry.input.activeFocus
              restoreMode: Binding.RestoreNone
            }
          }
          StyledSwitch {
            Layout.alignment: Qt.AlignVCenter
            compact: true
            checked: root.view?.base ?? true
            onToggled: root.editor.setView(["base"], checked)
          }
          StyledLabel {
            Layout.alignment: Qt.AlignVCenter
            text: I18n.tr("Show the base")
          }
          StyledIconButton {
            Layout.alignment: Qt.AlignVCenter
            kind: "danger"
            size: Widget.height
            iconText: "delete"
            tooltipText: I18n.tr("Remove this screen")
            onClicked: root.editor.removeView(root.editor.viewIndex)
          }
        }

        // "Show when [key] [is one of] [values]"; with no key, what shows it instead
        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledLabel {
            id: whenLabel
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: screen.labelWidth
            text: I18n.tr("Show when")
          }
          StyledComboEntry {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: Widget.px(120)
            editable: true
            value: screen.when.key ?? ""
            placeholderText: I18n.tr("Only an action")
            options: root.keyOptions
            onPicked: value => root.editor.setViewKey(root.editor.viewIndex, value)
          }
          StyledComboEntry {
            visible: !screen.noKey
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: Widget.px(120)
            value: screen.when.test ?? "is"
            options: root.testOptions
            onPicked: value => root.editor.setView(["when", "test"], value)
          }
          StyledTextEntry {
            id: valuesEntry
            visible: !screen.noKey && screen.listed
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: Widget.px(120)
            placeholderText: root.editor.seenStates.length > 0 ? I18n.tr("e.g. {0}", root.editor.seenStates.slice(0, 2).join(", ")) : I18n.tr("Values, separated by commas")
            onTextEdited: root.editor.setView(["when", "values"], valuesEntry.text.split(",").map(v => v.trim()).filter(v => v !== ""))
            Binding {
              target: valuesEntry
              property: "text"
              value: (screen.when.values ?? []).join(", ")
              when: !valuesEntry.input.activeFocus
              restoreMode: Binding.RestoreNone
            }
          }
          StyledText {
            visible: screen.noKey
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            text: I18n.tr("Only an action shows it.")
            role: "caption"
            tone: "muted"
            overflow: "wrap"
          }
          // The action it makes is named "Show <screen>"
          StyledTextButton {
            visible: screen.noKey && !root.hasGoTo
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Widget.height
            kind: "text"
            text: I18n.tr("Add a \"Go to\" action")
            onClicked: root.editor.addAction({
              "name": I18n.tr("Show {0}", root.view?.name || root.view?.id || ""),
              "kind": "axiom",
              "axiom": "screen:" + root.view?.id
            })
          }
        }
      }
    }
  }

  StyledText {
    visible: root.nothingDrawn
    Layout.fillWidth: true
    text: I18n.tr("No screen for this sample: the base elements are empty, so pick a screen to design it.")
    role: "caption"
    tone: "warning"
    overflow: "wrap"
  }
}
