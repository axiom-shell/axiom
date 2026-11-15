pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.content.parts.custom

// A custom widget's List element: rows of { text, icon, value, subtext, id,
// state, max, image } (the widget's items field, or a bound array), kept in
// a ListModel updated in place so a new sample never rebuilds them, down
// the element (a CustomListRow) or across it as tiles (`orientation`, a
// CustomListTile). A row's `state` tones its icon and meter through the
// definition's states; `max` with a numeric value draws a meter; `image` a
// thumbnail. A row's click runs the element's named action with {value} the
// row's id, else its value, else its text; without an action, the click
// command with {value} the row's text.
CustomElementBase {
  id: root

  readonly property bool clickable: root.canRun && (root.actionId !== "" || root.actions.click !== "")
  readonly property bool across: root.options.orientation === "horizontal"
  // A row's icon is an icon of the desktop icon theme, drawn as its picture
  readonly property bool themed: root.options.iconSource === "theme"
  // The output's items are rows already; a bound list is made them
  readonly property var rows: root.bind.items ? CustomWidgetData.rows(root.value("items")) : (root.fields?.items ?? [])
  onRowsChanged: root._fill()
  // Its icon source changing redraws the same rows
  onThemedChanged: root._fill()

  function _fill() {
    const rows = root.rows;
    for (let i = 0; i < rows.length; i++) {
      // Roles named apart from ItemRow's own properties
      const row = {
        "rowId": rows[i].id,
        "rowText": rows[i].text,
        "rowIcon": root.themed ? "" : rows[i].icon,
        "rowValue": CustomWidgetData.asText(rows[i].value),
        "rowSubtext": rows[i].subtext,
        "rowTone": CustomWidgetData.stateColor(rows[i].state, [], root.fields?.states, root.fields?.colorNames),
        "rowNumber": rows[i].value ?? 0,
        "rowMax": rows[i].max ?? 0,
        "rowImage": rows[i].image || !root.themed ? root.imageUrl(rows[i].image) : root.themeIcon(rows[i].icon)
      };
      if (i < rowsModel.count)
        rowsModel.set(i, row);
      else
        rowsModel.append(row);
    }
    if (rowsModel.count > rows.length)
      rowsModel.remove(rows.length, rowsModel.count - rows.length);
  }

  // The row whose first press with `confirm` was made (its id, else value,
  // else text), until it runs or 3 s pass: it says "Confirm?" in red
  property string asking: ""
  // A fixed time: how long the question is open
  Timer {
    id: askTimer
    interval: 3000
    onTriggered: root.asking = ""
  }

  // A row's press: the named action, else the click command. With `confirm`
  // the first press asks
  function press(id, value, text) {
    const key = id || value || text;
    if (root.options.confirm && root.asking !== key) {
      root.asking = key;
      askTimer.restart();
      return;
    }
    root.asking = "";
    askTimer.stop();
    if (root.actionId !== "")
      root.run("click", id || value || text);
    else
      root.act("click", text);
  }

  ListModel {
    id: rowsModel
  }

  ListView {
    anchors.fill: parent
    clip: true
    model: rowsModel
    orientation: root.across ? ListView.Horizontal : ListView.Vertical
    spacing: Widget.px(2)
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: row
      required property string rowId
      required property string rowText
      required property string rowIcon
      required property string rowValue
      required property string rowSubtext
      required property string rowTone
      required property real rowNumber
      required property real rowMax
      required property string rowImage
      // The row's colours: its tone's, else the element's own
      // Asked to confirm: it says so in the error colour
      readonly property bool asking: root.asking !== "" && root.asking === (row.rowId || row.rowValue || row.rowText)
      readonly property color tint: row.asking ? Style.error : row.rowTone ? Style.resolve(row.rowTone) : root.colorOf(Style.textMuted)
      readonly property color meter: row.rowTone ? Style.resolve(row.rowTone) : Style.toneFill("accent")

      // Tiles share the width, none narrower than a word
      width: root.across ? Math.max(Widget.textPx(56), (ListView.view.width - ListView.view.spacing * Math.max(0, ListView.view.count - 1)) / Math.max(1, ListView.view.count)) : ListView.view.width
      height: root.across ? ListView.view.height : (content.item as CustomListRow)?.implicitHeight ?? 0

      Loader {
        id: content
        anchors.fill: parent
        sourceComponent: root.across ? tile : line
      }

      Component {
        id: line
        CustomListRow {
          rowText: row.rowText
          rowIcon: row.rowIcon
          rowValue: row.rowValue
          rowSubtext: row.asking ? I18n.tr("Confirm?") : row.rowSubtext
          rowImage: row.rowImage
          rowNumber: row.rowNumber
          rowMax: row.rowMax
          iconTint: row.tint
          meterFill: row.meter
          clickable: root.clickable
          onActivated: root.press(row.rowId, row.rowValue, row.rowText)
        }
      }

      Component {
        id: tile
        CustomListTile {
          rowText: row.rowText
          rowIcon: row.rowIcon
          rowSubtext: row.asking ? I18n.tr("Confirm?") : row.rowSubtext
          rowImage: row.rowImage
          rowNumber: row.rowNumber
          rowMax: row.rowMax
          iconTint: row.tint
          meterFill: row.meter
          clickable: root.clickable
          onActivated: root.press(row.rowId, row.rowValue, row.rowText)
        }
      }
    }
  }
}
