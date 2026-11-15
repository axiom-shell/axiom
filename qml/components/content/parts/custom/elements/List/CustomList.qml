pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.content.parts
import qs.components.content.parts.custom

// A custom widget's List element: ItemRows of { text, icon, value,
// subtext, id } (the widget's items field, or a bound array), kept in a
// ListModel updated in place so a new sample never rebuilds them. A row's
// click runs the element's named action with {value} the row's id, else its
// value, else its text; without an action, the click command with {value}
// the row's text.
CustomElementBase {
  id: root

  readonly property bool clickable: root.canRun && (root.actionId !== "" || root.actions.click !== "")
  // The output's items are rows already; a bound list is made them
  readonly property var rows: root.bind.items ? CustomWidgetData.rows(root.value("items")) : (root.fields?.items ?? [])
  onRowsChanged: {
    const rows = root.rows;
    for (let i = 0; i < rows.length; i++) {
      // Roles named apart from ItemRow's own properties
      const row = {
        "rowId": rows[i].id,
        "rowText": rows[i].text,
        "rowIcon": rows[i].icon,
        "rowValue": CustomWidgetData.asText(rows[i].value),
        "rowSubtext": rows[i].subtext
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
      required property string rowId
      required property string rowText
      required property string rowIcon
      required property string rowValue
      required property string rowSubtext
      width: ListView.view.width
      icon: row.rowIcon
      title: row.rowText
      subtitle: row.rowSubtext
      detail: row.rowValue
      iconColor: root.colorOf(Style.textMuted)
      clickable: root.clickable
      onActivated: {
        if (root.actionId !== "")
          root.run("click", row.rowId || row.rowValue || row.rowText);
        else
          root.act("click", row.rowText);
      }
    }
  }
}
