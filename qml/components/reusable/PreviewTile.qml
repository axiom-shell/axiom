pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods

// A clickable tile, a Surface and a Pressable: a picture, template or
// choice. Two looks. With an `icon`, `description` or `tag` it is a card: the
// icon, the `title` with its tag chip (`tag`, a StatusChip `tagTone`) and the
// description. Otherwise it is a `preview` over the `title` (`previewHeight`
// tall, 0 for none). `selected` fills it with the accent container and rings
// it in the accent (an unselected one tints under the pointer); a non-empty
// `disabledReason` ignores clicks and says why: a card greys its content and
// shows the reason under the description (a warning line, as the
// onboarding's OptionCard did), a preview tile greys and says it in a tooltip
// on hover. `clicked` on a click or Space/Enter; `menus` makes a right click
// `menuRequested(x, y)` (off, the click is left to what is under the tile). `tabStop: false` leaves the Tab stop
// to a host that moves between tiles itself (ChoiceTiles, which sets `ringed`
// on the tile its keys are on).
Surface {
  id: root

  // -- Public API --
  property string title: ""
  property string icon: ""
  property string description: ""
  property string tag: ""
  // StatusChip's tone for the tag
  property string tagTone: "accent"
  property bool selected: false
  property string disabledReason: ""
  // A Component drawn over the title, made once from the build queue (a
  // StreamedLoader with `always`) with `previewProperties` (its root declares
  // them as `required property`s) and kept up to date in place: only a
  // property that differs is set, so handing equal ones again redraws nothing
  property Component preview: null
  property var previewProperties: ({})
  property real previewHeight: Widget.px(36)
  // The Tab stop and the keyboard ring (a host that owns the keys: `ringed`)
  property bool tabStop: true
  property bool ringed: false
  // A right click asks for a menu (`menuRequested`)
  property bool menus: false
  // The height its content needs (a host may stretch it with `height`)
  readonly property bool card: root.icon !== "" || root.description !== "" || root.tag !== ""
  readonly property bool disabled: root.disabledReason !== ""
  readonly property real contentHeight: root.card ? cardRow.implicitHeight + Widget.padding * 2 : (root.previewHeight > 0 ? root.previewHeight + Widget.smallPadding : 0) + Widget.height

  signal clicked
  signal menuRequested(real x, real y)

  // -- Implementation --
  implicitHeight: root.contentHeight
  tone: root.selected ? "accentContainer" : "surface"
  outlined: true
  border.width: root.selected ? Style.focusWidth : Style.hairline
  border.color: root.selected ? Style.accent : Style.borderSubtle

  Pressable {
    enabled: !root.disabled
    tabStop: root.tabStop
    tinted: !root.selected
    acceptedButtons: root.menus ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
    onClicked: root.clicked()
    onMenuRequested: (x, y) => root.menuRequested(x, y)
  }

  FocusRing {
    shown: root.ringed
  }

  // The card look
  RowLayout {
    id: cardRow
    visible: root.card
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.padding

    StyledIcon {
      Layout.alignment: Qt.AlignTop
      opacity: root.disabled ? Style.opacityDisabled : 1
      visible: root.icon !== ""
      text: root.icon
      size: "lg"
      tone: root.selected ? "accent" : ""
    }

    ColumnLayout {
      Layout.fillWidth: true
      // At the top when the tile is stretched taller than its text
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing / 2

      RowLayout {
        spacing: Widget.spacing
        opacity: root.disabled ? Style.opacityDisabled : 1

        StyledLabel {
          text: root.title
          role: "label"
        }

        StatusChip {
          visible: root.tag !== ""
          text: root.tag
          // On the selected tile's accent container an accent chip would vanish
          tone: root.selected && root.tagTone === "accent" ? "neutral" : root.tagTone
        }
      }

      StyledText {
        Layout.fillWidth: true
        visible: root.description !== ""
        text: root.description
        role: "caption"
        tone: "muted"
        opacity: root.disabled ? Style.opacityDisabled : 1
      }

      // Why it can't be picked, not greyed
      RowLayout {
        objectName: "disabledReason"
        Layout.fillWidth: true
        visible: root.card && root.disabled
        spacing: Widget.spacing / 2

        StyledIcon {
          Layout.alignment: Qt.AlignTop
          text: "block"
          tone: "warning"
        }

        StyledText {
          Layout.fillWidth: true
          text: root.disabledReason
          role: "caption"
          tone: "warning"
        }
      }
    }
  }

  // The preview-over-title look
  Item {
    id: content
    visible: !root.card
    anchors.fill: parent
    anchors.margins: Widget.smallPadding / 2
    opacity: root.disabled ? Style.opacityDisabled : 1

    Glide on opacity {}

    StreamedLoader {
      id: slot

      always: true
      label: "preview tile"
      wanted: root.previewHeight > 0 && root.preview !== null
      visible: root.previewHeight > 0
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Widget.smallPadding / 2
      height: root.previewHeight
      clip: true

      sourceComponent: Item {
        id: holder
        property Item made: null

        function make() {
          if (holder.made)
            holder.made.destroy();
          holder.made = root.preview ? root.preview.createObject(holder, root.previewProperties) : null;
          if (holder.made)
            holder.made.anchors.fill = holder;
        }

        function set() {
          if (!holder.made)
            return;
          for (const key in root.previewProperties)
            if (!Utils.deepEqual(holder.made[key], root.previewProperties[key]))
              holder.made[key] = root.previewProperties[key];
        }

        Component.onCompleted: holder.make()

        Connections {
          target: root
          function onPreviewChanged() {
            holder.make();
          }
          function onPreviewPropertiesChanged() {
            holder.set();
          }
        }
      }
    }

    StyledLabel {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Widget.height - Widget.smallPadding
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      role: "label"
      overflow: "line"
      text: root.title
      textColor: root.selected ? Style.inkAccentContainer.text : Style.inkSurface.text
    }
  }

  HoverHandler {
    id: hover
  }

  LazyLoader {
    active: hover.hovered && root.disabled && !root.card
    StyledToolTip {
      target: root
      text: root.disabledReason
    }
  }
}
