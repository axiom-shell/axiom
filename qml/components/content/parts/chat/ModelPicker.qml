pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.reusable

// The conversation's preset, then each provider's models, in one list
DropdownSurface {
  id: root

  signal picked

  // Presets, then per provider a header and its models
  readonly property var rows: {
    const out = [
      {
        header: I18n.tr("Presets")
      }
    ];
    ChatConfig.presets.forEach(preset => out.push({
        preset: preset
      }));
    ChatConfig.providers.forEach(provider => {
      out.push({
        header: provider.name,
        provider: provider
      });
      const models = provider.models ?? [];
      if (models.length === 0)
        out.push({
          empty: provider
        });
      models.forEach(model => out.push({
          provider: provider,
          model: model
        }));
    });
    return out;
  }

  // The most it may grow to (the chat sets what's left below the header)
  property real maxHeight: Widget.px(420)

  implicitHeight: Math.min(listColumn.implicitHeight + Widget.spacing * 2, root.maxHeight)

  StyledScrollView {
    id: scroll
    anchors.fill: parent
    anchors.margins: Widget.spacing
    contentPadding: 0
    // A lane of its own for the scroll bar, so it never covers a row
    showScrollBar: listColumn.implicitHeight > scroll.height

    ColumnLayout {
      id: listColumn
      width: scroll.availableWidth
      spacing: 1

      Repeater {
        model: root.rows.length
        delegate: Loader {
          id: row
          required property int index
          readonly property var rowData: root.rows[index] ?? ({})
          Layout.fillWidth: true
          sourceComponent: rowData.header !== undefined ? headerRow : rowData.empty ? emptyRow : choiceRow

          Component {
            id: headerRow
            RowLayout {
              width: row.width
              spacing: Widget.spacing / 2

              StyledLabel {
                role: "micro"
                tone: "faint"
                Layout.topMargin: row.index > 0 ? Widget.spacing * 2 : Widget.spacing / 2
                Layout.bottomMargin: Widget.spacing / 2
                Layout.leftMargin: Widget.spacing
                Layout.fillWidth: true
                text: row.rowData.header
              }

              // Whether the provider has a key
              StyledIcon {
                readonly property string status: row.rowData.provider ? SecretsManager.status(row.rowData.provider) : "unneeded"
                visible: status === "none"
                Layout.topMargin: row.index > 0 ? Widget.spacing * 2 : Widget.spacing / 2
                Layout.bottomMargin: Widget.spacing / 2
                Layout.rightMargin: Widget.spacing
                text: "key_off"
                tone: "warning"
                size: "xs"
              }
            }
          }

          Component {
            id: emptyRow
            StyledText {
              width: row.width
              leftPadding: Widget.spacing
              rightPadding: Widget.spacing
              text: I18n.tr("No models: fetch them in Settings → Chat")
              role: "micro"
              overflow: "wrap"
              tone: "faint"
            }
          }

          Component {
            id: choiceRow
            MenuRow {
              id: choice
              readonly property var preset: row.rowData.preset ?? null
              readonly property bool selected: preset ? preset.name === ChatManager.preset.name : row.rowData.provider.id === ChatManager.provider?.id && row.rowData.model === ChatManager.model
              width: row.width
              icon: choice.preset ? (choice.preset.icon || "chat") : ""
              text: choice.preset ? choice.preset.name : row.rowData.model
              current: choice.selected
              onActivated: {
                if (choice.preset)
                  ChatManager.setPreset(choice.preset.name);
                else
                  ChatManager.setModel(row.rowData.provider.id, row.rowData.model);
                root.picked();
              }
            }
          }
        }
      }
    }
  }
}
