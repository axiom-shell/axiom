pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable

// Fixed page navigator for the overlay's pages: arrows at the ends and a tab
// per page (icon and name), the current one under a sliding accent pill.
// Tool pages follow the user's own after a divider, as icons (named in a
// tooltip), even when current. When every name doesn't fit `maxWidth`, the
// other tabs drop to their icons too; `labels` can keep them there, or
// every tab. Scrolling over it steps through the pages.
// Pages with unsaved edits get a dot, and while another page has some,
// Save all / Discard all follow the arrows (EditsManager: a reminder, as
// drafts survive leaving a page or closing the overlay).
// After a link took the user to another page (ShellManager.followLink), a
// back chip leads the arrows: back arrow and that page's icon.
// Kept as its own item, anchored directly to the overlay's screen edge,
// so it doesn't move when the current page's content height changes.
Rectangle {
  id: root

  required property int currentIndex
  // [{ type, icon, label, tool }], one per page (OverlayPages.pages)
  required property var pages
  // The widest it may get; 0 for no limit
  property real maxWidth: 0
  // Which tabs show their names (Overlay.navigatorLabels): "auto" (all
  // while they fit, else the current one), "current" or "icons" (none)
  property string labels: "auto"

  signal previous
  signal next
  signal select(int index)

  readonly property real inset: 6
  readonly property real controlHeight: root.height - root.inset * 2
  readonly property real innerRadius: Math.max(0, Widget.radius - root.inset / 2)
  readonly property real tabPadding: Widget.padding * 1.5
  readonly property real iconSize: Appearance.fontSize * 1.4
  readonly property real labelSpacing: Widget.spacing / 2
  readonly property real tabSpacing: Widget.spacing
  readonly property string currentType: root.pages[root.currentIndex]?.type ?? ""
  // Save all / Discard all: while a page other than this one has edits
  // they'd act on (the current page has its own buttons)
  readonly property bool showEditActions: EditsManager.canActOnAll && EditsManager.unsaved.some(type => type !== root.currentType && !EditsManager.separate.includes(type))
  // The page a link was followed from, while it isn't the current one
  readonly property var backPage: ShellManager.linkOrigin === "" || ShellManager.linkOrigin === root.currentType ? null : root.pages.find(page => page.type === ShellManager.linkOrigin) ?? null
  // Everything but the tabs: arrows, the gaps beside them and the insets,
  // the back chip and the edit actions while they show
  readonly property real chrome: root.controlHeight * 2 + row.spacing * 2 + root.inset * 2 + (root.showEditActions ? editActions.implicitWidth + row.spacing : 0) + (root.backPage ? backChip.implicitWidth + backChip.Layout.leftMargin + row.spacing : 0)
  // Only the current tab keeps its name when all of them don't fit
  readonly property bool compact: root.maxWidth > 0 && root.chrome + measureRow.fullWidth > root.maxWidth
  readonly property color onAccent: Theme.background

  width: row.implicitWidth + root.inset * 2
  height: OverlayConfig.navigatorHeight
  radius: Appearance.borderRadius
  color: Appearance.fill(Theme.backgroundAlt)
  border.color: Theme.foreground
  border.width: Appearance.borderWidth

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    property real _accumulated: 0
    onWheel: event => {
      _accumulated += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
      if (Math.abs(_accumulated) < 120)
        return;
      if (_accumulated < 0)
        root.next();
      else
        root.previous();
      _accumulated = 0;
    }
  }

  // Every tab with its name, never shown: how wide the full row would be.
  // Summed here: a hidden Row is never laid out, so its width stays 0
  Item {
    id: measureRow
    visible: false
    readonly property real fullWidth: {
      let width = Math.max(0, measures.count - 1) * root.tabSpacing;
      for (let i = 0; i < measures.count; i++)
        width += measures.itemAt(i)?.implicitWidth ?? 0;
      return width;
    }
    Repeater {
      id: measures
      model: root.pages
      Item {
        required property var modelData
        implicitWidth: root.tabPadding * 2 + root.iconSize + (modelData.tool ? 0 : root.labelSpacing + measureLabel.implicitWidth) + (EditsManager.isUnsaved(modelData.type) ? root.labelSpacing + Widget.px(8) : 0)
        StyledText {
          id: measureLabel
          text: parent.modelData.label
        }
      }
    }
  }

  // An icon button in the pill (the arrows, the edit actions), named in a
  // tooltip when `tip` is set
  component ArrowButton: Rectangle {
    id: arrow
    property string icon
    property color iconColor: Theme.foreground
    property string tip: ""
    signal clicked

    Layout.preferredWidth: root.controlHeight
    Layout.preferredHeight: root.controlHeight
    radius: root.innerRadius
    // Fade the highlight in and out rather than from "transparent", which is
    // transparent black and flashes dark mid-animation
    color: arrowArea.containsMouse ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)

    StyledIcon {
      anchors.centerIn: parent
      text: arrow.icon
      textSize: root.iconSize * 1.2
      color: arrow.iconColor
    }

    MouseArea {
      id: arrowArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: arrow.clicked()
    }

    LazyLoader {
      active: arrow.tip !== "" && arrowArea.containsMouse
      StyledToolTip {
        target: arrow
        text: arrow.tip
        edges: Edges.Top
      }
    }

    ColorGlide on color {}
  }

  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: root.tabSpacing

    // Back to the page a link was followed from
    Rectangle {
      id: backChip
      visible: root.backPage !== null
      implicitWidth: backContent.implicitWidth + root.tabPadding * 2
      Layout.preferredWidth: backChip.implicitWidth
      Layout.preferredHeight: root.controlHeight
      // Clear of the navigator's rounded left end
      Layout.leftMargin: Widget.spacing
      radius: root.innerRadius
      color: backArea.containsMouse ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)
      border.color: Qt.alpha(Theme.accent, 0.6)
      border.width: Appearance.borderWidth

      Row {
        id: backContent
        anchors.centerIn: parent
        spacing: root.labelSpacing

        StyledIcon {
          anchors.verticalCenter: parent.verticalCenter
          text: "arrow_back"
          textSize: root.iconSize
          textColor: Theme.accent
        }

        StyledIcon {
          anchors.verticalCenter: parent.verticalCenter
          text: root.backPage?.icon ?? ""
          textSize: root.iconSize
        }
      }

      MouseArea {
        id: backArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellManager.followLinkBack()
      }

      LazyLoader {
        active: backArea.containsMouse
        StyledToolTip {
          target: backChip
          text: I18n.tr("Back to {0}", root.backPage?.label ?? "")
          edges: Edges.Top
        }
      }

      ColorGlide on color {}
    }

    ArrowButton {
      icon: "chevron_left"
      onClicked: root.previous()
    }

    Item {
      Layout.preferredWidth: tabRow.implicitWidth
      Layout.preferredHeight: root.controlHeight

      // itemAt() isn't a notifying read: `count` re-evaluates it once the
      // tabs exist
      readonly property var currentTab: tabs.count > root.currentIndex ? tabs.itemAt(root.currentIndex) : null

      Rectangle {
        id: pill
        x: (parent.currentTab?.x ?? 0) + (parent.currentTab?.divider ?? 0)
        width: parent.currentTab?.tabWidth ?? 0
        height: parent.height
        radius: root.innerRadius
        color: Theme.accent
        visible: parent.currentTab !== null

        Behavior on x {
          NumberAnimation {
            duration: Appearance.animNormal
            easing.type: Easing.OutCubic
          }
        }
        Behavior on width {
          NumberAnimation {
            duration: Appearance.animNormal
            easing.type: Easing.OutCubic
          }
        }
      }

      Row {
        id: tabRow
        height: parent.height
        spacing: root.tabSpacing

        Repeater {
          id: tabs
          model: root.pages

          // The tab, after a divider where the tool pages start
          Item {
            id: tab
            required property int index
            required property var modelData
            readonly property bool isCurrent: index === root.currentIndex
            readonly property bool showLabel: !tab.modelData.tool && root.labels !== "icons" && (tab.isCurrent || (root.labels === "auto" && !root.compact))
            readonly property color ink: tab.isCurrent ? root.onAccent : Theme.foreground
            readonly property bool firstTool: tab.modelData.tool === true && tab.index > 0 && root.pages[tab.index - 1]?.tool !== true
            readonly property real divider: tab.firstTool ? root.tabSpacing + Appearance.borderWidth : 0
            readonly property real tabWidth: root.tabPadding * 2 + content.implicitWidth

            width: tab.divider + tab.tabWidth
            height: parent.height

            StyledSeparator {
              visible: tab.firstTool
              x: root.tabSpacing / 2 - width
              anchors.verticalCenter: parent.verticalCenter
              width: Appearance.borderWidth
              height: root.controlHeight * 0.6
              opacity: 0.5
            }

            Rectangle {
              id: tabBox
              x: tab.divider
              width: tab.tabWidth
              height: parent.height
              radius: root.innerRadius
              color: !tab.isCurrent && tabArea.containsMouse ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)

              Row {
                id: content
                anchors.centerIn: parent
                spacing: root.labelSpacing

                StyledIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  text: tab.modelData.icon
                  textSize: root.iconSize
                  fill: tab.isCurrent ? 1 : 0
                  textColor: tab.ink
                }

                StyledText {
                  anchors.verticalCenter: parent.verticalCenter
                  text: tab.modelData.label
                  visible: tab.showLabel
                  font.weight: tab.isCurrent ? Font.DemiBold : Font.Normal
                  textColor: tab.ink
                }

                UnsavedDot {
                  anchors.verticalCenter: parent.verticalCenter
                  shown: EditsManager.isUnsaved(tab.modelData.type)
                  onAccent: tab.isCurrent
                }
              }

              MouseArea {
                id: tabArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.select(tab.index)
              }

              LazyLoader {
                active: !tab.showLabel && tabArea.containsMouse
                StyledToolTip {
                  target: tabBox
                  text: tab.modelData.label
                  edges: Edges.Top
                }
              }

              ColorGlide on color {}
            }
          }
        }
      }
    }

    ArrowButton {
      icon: "chevron_right"
      onClicked: root.next()
    }

    RowLayout {
      id: editActions
      visible: root.showEditActions
      spacing: root.tabSpacing / 2

      StyledSeparator {
        Layout.preferredWidth: Appearance.borderWidth
        Layout.preferredHeight: root.controlHeight * 0.6
        Layout.rightMargin: root.tabSpacing / 2
        opacity: 0.5
      }

      ArrowButton {
        icon: "save"
        iconColor: Theme.accent
        tip: I18n.tr("Save all unsaved changes")
        onClicked: EditsManager.saveAll()
      }

      ArrowButton {
        icon: "undo"
        tip: I18n.tr("Discard all unsaved changes")
        onClicked: EditsManager.discardAll()
      }
    }
  }
}
