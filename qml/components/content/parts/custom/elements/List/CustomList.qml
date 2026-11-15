pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.content.parts.custom

// A custom widget's List element: rows of { text, icon, value, subtext, id,
// state, max, image } (the widget's items field, or a bound array), kept in
// a ListModel updated in place so a new sample never rebuilds them, down
// the element (a CustomListRow) or across it as tiles (`orientation`, a
// CustomListTile). The colour part's rules (`colorStates`, read from the
// row's own keys, `state` by default) tone a row's icon and meter; a row's `unit` follows its value; `max` with a numeric value draws a meter; `image` a
// thumbnail. A row's click runs the element's click action with {value} the
// row's id, else its value, else its text; with no action the rows aren't
// pressable. The element's Size scales the rows (text, icons, meters, gaps)
// as one: Small to Huge are the shell's text sizes against the body size;
// Fit grows them to fill the box (rows down the element, tiles across it),
// never below Normal.
CustomElementBase {
  id: root

  readonly property bool clickable: root.canRun("click")
  // How much bigger than the natural row it is drawn (1 = Normal)
  readonly property real zoom: root.fixedTextSize !== 0 ? root.fixedTextSize / Style.typeBody : root.fitZoom
  // Fit: rows share the box's height (down), tiles the box's smaller side (across)
  readonly property real fitZoom: {
    const count = Math.max(1, rowsModel.count);
    const natural = root.across ? Widget.textPx(56) : Widget.textPx(44);
    const room = root.across ? Math.min(root.height, root.width / count) : root.height / count;
    return Math.max(1, Math.min(3, room / natural));
  }
  readonly property bool across: root.options.orientation === "horizontal"
  // A row's icon is an icon of the desktop icon theme, drawn as its picture
  readonly property bool themed: root.options.iconSource === "theme"
  // The output's items, or a bound list, made rows by the element's `row` map
  readonly property var rows: CustomWidgetData.rows(root.bind.items ? root.value("items") : root.fields?.sample?.items, root.options.row)
  onRowsChanged: root._fill()
  // Its icon source changing redraws the same rows
  onThemedChanged: root._fill()
  // Its colour part changing re-tints the same rows
  readonly property string tones: JSON.stringify([root.options.color ?? "", root.options.colorStates ?? null])
  onTonesChanged: root._fill()

  // The colour name the element's colour part gives a row (its rules read
  // the row's own keys): "" for none, so the element's own colour tints it
  function rowName(row) {
    return CustomWidgetData.rowColor(root.options.color, root.options.colorStates, row);
  }

  function _fill() {
    const rows = root.rows;
    for (let i = 0; i < rows.length; i++) {
      // Roles named apart from ItemRow's own properties
      const row = {
        "rowId": rows[i].id,
        "rowText": rows[i].text,
        "rowIcon": root.themed ? "" : rows[i].icon,
        "rowValue": CustomWidgetData.rowValueText(rows[i]),
        "rowSubtext": rows[i].subtext,
        "rowTone": rowName(rows[i]),
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
    root.runTrigger("click", key);
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
      height: root.across ? ListView.view.height : ((content.item as CustomListRow)?.implicitHeight ?? 0) * root.zoom

      // Drawn at its natural size in a box 1/zoom as big, then scaled up
      Loader {
        id: content
        width: row.width / root.zoom
        height: row.height / root.zoom
        scale: root.zoom
        transformOrigin: Item.TopLeft
        readonly property real contentZoom: scale
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
