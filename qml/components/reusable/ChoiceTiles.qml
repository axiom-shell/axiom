pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config

// A single choice as a wrapping row of equal tiles (a TileFlow), each a
// preview over its label: the chosen one filled with the accent, one that
// can't be picked greyed, saying why in a tooltip on hover. Arrow keys
// move between the tiles, Enter or Space picks. The owner keeps the
// value: set `value`, and update it from `picked`.
TileFlow {
  id: root

  // [{ value, label, preview, disabledReason }]: `preview` (optional) a
  // Component drawn over the label, its root declaring `required property
  // var value` (handed the option's); a non-empty `disabledReason` greys
  // the tile and is its tooltip
  property var options: []
  property var value
  // Every tile's preview, for options without their own
  property Component preview: null
  // The preview's height, on every tile while any tile has one
  property real previewHeight: Widget.px(36)

  signal picked(var value)

  readonly property int _selected: Array.prototype.findIndex.call(root.options, option => option.value === root.value)
  readonly property bool _previews: root.preview !== null || Array.prototype.some.call(root.options, option => !!option.preview)
  // The tile the keys are on
  property int _cursor: -1

  minTileWidth: Appearance.fontSize * 9
  activeFocusOnTab: true
  onActiveFocusChanged: {
    if (root.activeFocus && (root._cursor < 0 || root._cursor >= root.options.length))
      root._cursor = Math.max(0, root._selected);
  }

  function _move(by, event) {
    const next = root._cursor + by;
    event.accepted = next >= 0 && next < root.options.length;
    if (event.accepted)
      root._cursor = next;
  }

  function _pick(index) {
    const option = root.options[index];
    if (option && !option.disabledReason && option.value !== root.value)
      root.picked(option.value);
  }

  Keys.onLeftPressed: event => root._move(-1, event)
  Keys.onRightPressed: event => root._move(1, event)
  Keys.onUpPressed: event => root._move(-root.columns, event)
  Keys.onDownPressed: event => root._move(root.columns, event)
  Keys.onReturnPressed: root._pick(root._cursor)
  Keys.onEnterPressed: root._pick(root._cursor)
  Keys.onSpacePressed: root._pick(root._cursor)

  Repeater {
    // By count: an option's reason changes as other settings do
    model: root.options.length

    delegate: Item {
      id: tile
      required property int index
      readonly property var option: root.options[tile.index] ?? ({})
      readonly property string reason: tile.option.disabledReason ?? ""
      readonly property bool selected: tile.index === root._selected
      readonly property bool cursor: root.activeFocus && tile.index === root._cursor

      width: root.tileWidth
      height: (root._previews ? root.previewHeight + Widget.smallPadding : 0) + Widget.height

      Rectangle {
        anchors.fill: parent
        radius: Widget.radius
        color: Appearance.fill(tile.selected ? Theme.accent : hover.hovered && tile.reason === "" ? Theme.backgroundAlt : Theme.backgroundHighlight)
        border.color: tile.cursor ? (tile.selected ? Theme.foreground : Theme.accent) : "transparent"
        border.width: Appearance.borderWidth

        ColorGlide on color {
          duration: Appearance.animNormal
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: Widget.smallPadding / 2
        opacity: tile.reason === "" ? 1 : 0.4

        Glide on opacity {}

        // The preview, made with the option's value
        Item {
          id: slot
          readonly property Component component: tile.option.preview ?? root.preview
          readonly property var optionValue: tile.option.value
          property Item _made: null

          visible: root._previews
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Widget.smallPadding / 2
          height: root.previewHeight
          clip: true

          function _make() {
            if (slot._made)
              slot._made.destroy();
            slot._made = slot.component ? slot.component.createObject(slot, {
              "value": slot.optionValue
            }) : null;
            if (slot._made)
              slot._made.anchors.fill = slot;
          }

          onComponentChanged: slot._make()
          onOptionValueChanged: slot._make()
          Component.onCompleted: slot._make()
        }

        StyledLabel {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Widget.height - Widget.smallPadding
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: tile.option.label ?? String(tile.option.value ?? "")
          textColor: tile.selected ? Theme.background : Theme.foreground
          font.bold: tile.selected
        }
      }

      HoverHandler {
        id: hover
        cursorShape: tile.reason === "" && !tile.selected ? Qt.PointingHandCursor : Qt.ArrowCursor
      }

      TapHandler {
        onTapped: {
          root._cursor = tile.index;
          root._pick(tile.index);
        }
      }

      LazyLoader {
        active: hover.hovered && tile.reason !== ""
        StyledToolTip {
          target: tile
          text: tile.reason
        }
      }
    }
  }
}
