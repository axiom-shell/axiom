pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom

// Custom widgets page, Module tab: the module's design size and whether the
// lock screen offers it, the canvas its elements are placed on, the
// selected element (or the library), and the module as it's drawn at other
// sizes a page may give it (it's laid out proportionally) and as the bar
// widget's popout (its design size).
ColumnLayout {
  id: root

  required property var grid
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var size: root.definition?.module?.size ?? [4, 2]
  readonly property bool hasElements: (root.definition?.module?.elements?.length ?? 0) > 0
  readonly property real card: root.grid?.unit ?? Widget.px(400)

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  // Size, lock screen, undo
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    SizeStepper {
      label: I18n.tr("Width")
      value: root.size[0]
      onStep: delta => root.editor.setDesignSize([root.size[0] + delta, root.size[1]])
    }
    SizeStepper {
      label: I18n.tr("Height")
      value: root.size[1]
      onStep: delta => root.editor.setDesignSize([root.size[0], root.size[1] + delta])
    }
    StyledText {
      text: I18n.tr("{0} cards across", GridPlacement.cards(root.size[0]))
      opacity: 0.6
    }
    Item {
      Layout.fillWidth: true
    }
    StyledText {
      text: I18n.tr("On the lock screen")
    }
    StyledSwitch {
      checked: root.definition?.module?.lockscreen ?? false
      onToggled: root.editor.set(["module", "lockscreen"], checked)
    }
    FlatIconButton {
      size: Widget.iconButton
      iconText: "undo"
      enabled: root.editor.elements.canUndo
      tooltipText: I18n.tr("Undo")
      onClicked: root.editor.elements.undo()
    }
    FlatIconButton {
      size: Widget.iconButton
      iconText: "redo"
      enabled: root.editor.elements.canRedo
      tooltipText: I18n.tr("Redo")
      onClicked: root.editor.elements.redo()
    }
  }

  StyledText {
    visible: !root.hasElements
    Layout.fillWidth: true
    text: I18n.tr("No elements yet: the module draws its icon, text and value by itself. Add elements to design it, or start from that layout.")
    wrapMode: Text.WordWrap
    opacity: 0.7
  }
  StyledTextButton {
    visible: !root.hasElements
    implicitHeight: Widget.height
    iconText: "auto_awesome"
    text: I18n.tr("Start from the default layout")
    onClicked: root.editor.useDefaultElements()
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing * 3

    ElementCanvas {
      Layout.fillWidth: true
      Layout.preferredWidth: designWidth
      Layout.alignment: Qt.AlignTop
      card: root.card
      maxHeight: root.card * 1.4
    }

    ElementInspector {
      Layout.preferredWidth: Appearance.fontSize * 22
      Layout.maximumWidth: Appearance.fontSize * 22
      Layout.alignment: Qt.AlignTop
    }
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("At other sizes")
    description: I18n.tr("A page can give the module any size; its elements keep their share of it. The first is the bar widget's popout.")

    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing * 2

      // I18n.tr("Popout") I18n.tr("Square") I18n.tr("Wide") I18n.tr("Large") I18n.tr("Strip")
      Repeater {
        model: [
          {
            "label": "Popout",
            "size": root.size
          },
          {
            "label": "Square",
            "size": [4, 4]
          },
          {
            "label": "Wide",
            "size": [8, 2]
          },
          {
            "label": "Large",
            "size": [8, 4]
          },
          {
            "label": "Strip",
            "size": [4, 1]
          }
        ]

        ColumnLayout {
          id: preview
          required property var modelData
          readonly property real zoom: 0.4
          spacing: Widget.spacing / 2

          StyledText {
            text: I18n.tr(preview.modelData.label)
            textSize: Appearance.fontSizeBy(-2)
            opacity: 0.7
          }
          Rectangle {
            implicitWidth: GridPlacement.span(preview.modelData.size[0], root.card) * preview.zoom
            implicitHeight: GridPlacement.span(preview.modelData.size[1], root.card) * preview.zoom
            radius: Widget.radius
            color: Appearance.fill(Theme.background)
            border.color: Theme.border
            border.width: Appearance.borderWidth
            clip: true

            Item {
              width: parent.width / preview.zoom
              height: parent.height / preview.zoom
              scale: preview.zoom
              transformOrigin: Item.TopLeft

              CustomLayout {
                anchors.fill: parent
                anchors.margins: Widget.cardPadding
                definition: root.definition
                fields: CustomWidgetsManager.fields[root.editor.selectedId] ?? ({})
                history: CustomWidgetsManager.history[root.editor.selectedId] ?? ({})
                actionsEnabled: false
              }
            }
          }
        }
      }
    }
  }

  // − n +
  component SizeStepper: RowLayout {
    id: stepper
    property string label
    property int value
    signal step(int delta)
    spacing: Widget.spacing / 2

    StyledText {
      text: stepper.label
    }
    FlatIconButton {
      size: Widget.iconButton
      iconText: "remove"
      enabled: stepper.value > 1
      onClicked: stepper.step(-1)
    }
    StyledText {
      text: String(stepper.value)
      font.bold: true
    }
    FlatIconButton {
      size: Widget.iconButton
      iconText: "add"
      enabled: stepper.value < 8
      onClicked: stepper.step(1)
    }
  }
}
