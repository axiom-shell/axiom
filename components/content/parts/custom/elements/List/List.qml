pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.content.parts
import qs.components.content.parts.custom

// A custom widget's List element: ItemRows of { text, icon, value,
// subtext } (the widget's items field, or a bound array), kept in a
// ListModel updated in place so a new sample never rebuilds them. A row's
// click runs the click command with {value} the row's text.
CustomElementBase {
  id: root

  readonly property bool clickable: root.actionsEnabled && root.actions.click !== ""
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
      // Roles named apart from ItemRow's own properties
      const row = {
        "rowText": String(r.text ?? ""),
        "rowIcon": String(r.icon ?? ""),
        "rowValue": r.value === undefined || r.value === null ? "" : String(r.value),
        "rowSubtext": String(r.subtext ?? "")
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

    delegate: ItemRow {
      id: row
      required property string rowText
      required property string rowIcon
      required property string rowValue
      required property string rowSubtext
      width: ListView.view.width
      icon: row.rowIcon
      title: row.rowText
      subtitle: row.rowSubtext
      detail: row.rowValue
      iconColor: root.colorOf(Theme.foregroundAlt)
      clickable: root.clickable
      onActivated: root.act("click", row.rowText)
    }
  }
}
