pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A custom widget's List element: rows of { text, icon, value, subtext }
// (the widget's items field, or a bound array), kept in a ListModel updated
// in place so a new sample never rebuilds the rows.
// options: color (the icons)
CustomElementBase {
  id: root

  readonly property var rows: {
    const v = root.bind.items ? root.value("items") : root.fields?.items;
    return Array.isArray(v) ? v : [];
  }
  onRowsChanged: {
    const rows = root.rows;
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i] !== null && typeof rows[i] === "object" ? rows[i] : {
        "text": String(rows[i])
      };
      const row = {
        "text": String(r.text ?? ""),
        "icon": String(r.icon ?? ""),
        "value": r.value === undefined || r.value === null ? "" : String(r.value),
        "subtext": String(r.subtext ?? "")
      };
      if (i < rowsModel.count)
        rowsModel.set(i, row);
      else
        rowsModel.append(row);
    }
    if (rowsModel.count > rows.length)
      rowsModel.remove(rows.length, rowsModel.count - rows.length);
  }

  ListModel {
    id: rowsModel
  }

  ListView {
    anchors.fill: parent
    clip: true
    model: rowsModel
    spacing: Widget.px(2)
    boundsBehavior: Flickable.StopAtBounds

    delegate: RowLayout {
      id: row
      required property string text
      required property string icon
      required property string value
      required property string subtext
      width: ListView.view.width
      spacing: Widget.spacing

      StyledIcon {
        visible: row.icon !== ""
        text: row.icon
        textColor: root.colorOf("color", Theme.accent)
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
          Layout.fillWidth: true
          text: row.text
          elide: Text.ElideRight
        }
        StyledText {
          visible: row.subtext !== ""
          Layout.fillWidth: true
          text: row.subtext
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-2)
          textColor: Theme.foregroundAlt
        }
      }
      StyledText {
        visible: row.value !== ""
        text: row.value
        textColor: Theme.foregroundAlt
      }
    }
  }
}
