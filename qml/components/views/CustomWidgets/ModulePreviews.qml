pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom

// Custom widgets page, Module tab, above the canvas: a header line (what the
// previews draw with, Keep, the Test actions switch: one RowLayout, every
// item centred on it) and the module as it's drawn: the popout at its design
// size, then the sizes a page may give it. Test mode swaps the previews for
// the popout fitted, as it is live with its actions on, and the log of what it
// ran beside it; the header never moves. The previews draw the edited
// screen's sample (CustomWidgetsEditor.previewFields).
ColumnLayout {
  id: root

  // The selected definition
  required property var definition
  // One grid unit in px at the design size
  required property real card
  // The module's design size, [w, h] in grid units
  required property var designSize
  // The height the tab has: the previews' zoom reads it, never this column's,
  // or they would shrink while a screen's form shows
  required property real tabHeight
  readonly property var editor: CustomWidgetsManager.editor
  // The live output the test preview draws (null before the script's first
  // output: the previewed sample then)
  readonly property var liveFields: CustomWidgetsManager.fields[root.editor.selectedId] ?? null
  // Why the live sample can't be kept (its count or size limit), or ""
  readonly property string keepReason: root.editor.keepRefused === "count" ? I18n.tr("{0} samples are kept: remove one first", root.editor.sampleLimits.entries) : root.editor.keepRefused === "size" ? I18n.tr("The samples are over {0} KB: remove one first", root.editor.sampleLimits.bytes / 1024) : ""
  // The previews: the popout at the design size, then the sizes a page may give
  // I18n.tr("Popout") I18n.tr("Square") I18n.tr("Wide") I18n.tr("Large") I18n.tr("Strip")
  readonly property var previews: [
    {
      "label": "Popout",
      "size": root.designSize
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
  readonly property real previewZoom: CustomWidgetData.previewZoom(root.previews.map(p => p.size), root.card, root.width, root.tabHeight, 0, Widget.spacing * 2)
  // The test popout fits this column's width (less room for the log) and half the tab's height
  readonly property real testZoom: CustomWidgetData.fitZoom(root.designSize, root.card, root.width * 0.6, root.tabHeight * 0.5)

  Layout.fillWidth: true
  spacing: Widget.spacing

  RowLayout {
    Layout.fillWidth: true
    // Keep comes and goes: the line keeps its height
    Layout.preferredHeight: Widget.height
    spacing: Widget.spacing

    StyledText {
      Layout.alignment: Qt.AlignVCenter
      text: I18n.tr("Previews")
      role: "label"
    }
    StatusChip {
      Layout.alignment: Qt.AlignVCenter
      text: root.editor.sampleSource === "saved" ? I18n.tr("Previewing: saved") : root.editor.sampleSource === "live" ? I18n.tr("Previewing: live") : I18n.tr("Previewing: none")
      tone: root.editor.sampleSource === "saved" ? "success" : root.editor.sampleSource === "live" ? "info" : "neutral"
    }
    // Keeps the live sample as the edited screen's
    StyledTextButton {
      visible: root.editor.sampleSource === "live"
      Layout.alignment: Qt.AlignVCenter
      implicitHeight: Widget.height
      kind: "text"
      enabled: root.editor.liveSample !== null && root.keepReason === ""
      iconText: "bookmark_add"
      text: I18n.tr("Keep")
      tooltipText: root.keepReason
      onClicked: root.editor.keepSample()
    }
    Item {
      Layout.fillWidth: true
    }
    // Test mode: not saved, off each time the page opens
    StyledSwitch {
      Layout.alignment: Qt.AlignVCenter
      compact: true
      checked: root.editor.testMode
      onToggled: root.editor.testMode = checked
    }
    StyledLabel {
      Layout.alignment: Qt.AlignVCenter
      text: I18n.tr("Test actions")
    }
    StatusChip {
      visible: root.editor.testMode
      Layout.alignment: Qt.AlignVCenter
      text: I18n.tr("Runs real commands")
      tone: "warning"
    }
  }

  // The previews (not in test mode)
  Row {
    id: band
    visible: !root.editor.testMode
    Layout.fillWidth: true
    clip: true
    spacing: Widget.spacing * 2

    HoverHandler {
      id: bandHover
    }
    LazyLoader {
      active: bandHover.hovered && !root.editor.testMode
      StyledToolTip {
        target: band
        text: I18n.tr("Turn on Test actions to click")
      }
    }

    Repeater {
      model: root.previews

      Column {
        id: preview
        required property var modelData
        readonly property real zoom: root.previewZoom
        spacing: Widget.spacing / 2

        StyledText {
          text: I18n.tr(preview.modelData.label)
          role: "caption"
          tone: "muted"
        }
        // A module card sits on the overlay's page colour, as on a real page
        Surface {
          width: GridPlacement.span(preview.modelData.size[0], root.card) * preview.zoom
          height: GridPlacement.span(preview.modelData.size[1], root.card) * preview.zoom
          tone: "page"
          clip: true

          Item {
            width: parent.width / preview.zoom
            height: parent.height / preview.zoom
            scale: preview.zoom
            readonly property real contentZoom: scale
            transformOrigin: Item.TopLeft

            CustomLayout {
              anchors.fill: parent
              anchors.margins: Widget.cardPadding
              definition: root.definition
              fields: root.editor.previewFields ?? ({})
              history: CustomWidgetsManager.history[root.editor.selectedId] ?? ({})
              actionsEnabled: false
              viewIndex: root.editor.viewIndex
            }
          }
        }
      }
    }
  }

  // Test mode: the popout at its design size, fitted, as it is live with its
  // actions and Entries on (they run the real commands); what it ran at its
  // right, in a box of the popout's height that scrolls
  Loader {
    active: root.editor.testMode
    visible: active
    Layout.fillWidth: true
    Layout.preferredHeight: active ? GridPlacement.span(root.designSize[1], root.card) * root.testZoom : 0

    sourceComponent: Item {
      Surface {
        id: testBox
        anchors.left: parent.left
        anchors.top: parent.top
        width: GridPlacement.span(root.designSize[0], root.card) * root.testZoom
        height: GridPlacement.span(root.designSize[1], root.card) * root.testZoom
        tone: "page"
        clip: true

        Item {
          width: parent.width / root.testZoom
          height: parent.height / root.testZoom
          scale: root.testZoom
          readonly property real contentZoom: scale
          transformOrigin: Item.TopLeft

          CustomLayout {
            anchors.fill: parent
            anchors.margins: Widget.cardPadding
            definition: root.definition
            fields: root.liveFields ?? root.editor.previewFields ?? ({})
            history: CustomWidgetsManager.history[root.editor.selectedId] ?? ({})
            actionsEnabled: true
            keysHost: true
            // The screen a Go to action chose, as the live module draws it
            viewIndex: root.liveFields ? CustomWidgetData.pickView(root.definition?.module, root.liveFields, CustomWidgetsManager.pages[root.editor.selectedId] ?? null).index : root.editor.viewIndex
          }
        }
      }

      StyledScrollView {
        id: logScroll
        anchors.left: testBox.right
        anchors.leftMargin: Widget.spacing * 2
        anchors.right: parent.right
        anchors.top: parent.top
        height: testBox.height
        contentPadding: 0
        clip: true

        ActionLog {
          width: logScroll.availableWidth
        }
      }
    }
  }
}
