pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// One row of a menu, dropdown or picker: an optional leading mark (icon,
// image or a `leading` item), the label, a trailing detail, a chevron. It
// sits on its menu's raised Surface and inherits that ink; a `current` row is
// filled with the accent container and its content reads that ink instead.
Item {
  id: root

  // -- Public API --
  // A leading content item (a check or radio indicator): children declared
  // inside land here, before the label
  default property alias leading: leadingSlot.data
  property string icon: ""
  property url image: ""
  property string text: ""
  // A shortcut or a detail, after the label
  property string trailing: ""
  property bool chevron: false
  // A leading check in place of the icon
  property bool checked: false
  // The chosen one of a dropdown: accent container fill
  property bool current: false
  // The keyboard highlight: the hover layer
  property bool lit: false
  // The label in the error colour
  property bool danger: false
  // Context and edge menus: the smaller padding
  property bool dense: false
  readonly property bool hovered: area.containsMouse

  signal activated

  // -- Implementation --
  readonly property real _pad: root.dense ? Widget.smallPadding : Widget.padding
  readonly property var _outer: InkHost.find(root.parent)
  // What its text and icons inherit: the container's ink on a current row,
  // else the menu's
  readonly property var inkScope: root.current ? Style.inkAccentContainer : (root._outer ? root._outer.inkScope : null)
  readonly property real drawnZoom: TextRender.zoomAt(root.parent)
  readonly property string _tone: !root.enabled ? "disabled" : root.danger ? "error" : ""

  implicitWidth: content.implicitWidth + root._pad * 2
  implicitHeight: Widget.height

  Rectangle {
    anchors.fill: parent
    radius: Style.radiusInner
    color: Style.accentContainer
    visible: root.current
  }

  StateLayer {
    hovered: root.hovered || root.lit
    pressed: area.pressed
  }

  RowLayout {
    id: content

    anchors.fill: parent
    anchors.leftMargin: root._pad
    anchors.rightMargin: root._pad
    spacing: Widget.spacing

    Row {
      id: leadingSlot

      // Empty, it must not take a gap of the row's spacing (the label sat
      // one spacing right of the padding)
      visible: leadingSlot.children.length > 0
      spacing: Widget.spacing
      Layout.alignment: Qt.AlignVCenter
    }

    StyledIcon {
      visible: root.checked || root.icon !== ""
      text: root.checked ? "check" : root.icon
      tone: !root.enabled ? "disabled" : root.current ? "text" : "muted"
      Layout.preferredWidth: Style.iconMd
      horizontalAlignment: Text.AlignHCenter
    }

    Image {
      asynchronous: true
      visible: root.image.toString() !== "" && !root.checked
      source: root.image
      sourceSize.width: Style.iconMd
      sourceSize.height: Style.iconMd
      fillMode: Image.PreserveAspectFit
      Layout.preferredWidth: Style.iconMd
      Layout.preferredHeight: Style.iconMd
    }

    StyledText {
      role: "label"
      text: root.text
      tone: root._tone
      Layout.fillWidth: true
    }

    StyledText {
      visible: root.trailing !== ""
      role: "caption"
      text: root.trailing
      tone: root.enabled ? "faint" : "disabled"
    }

    StyledIcon {
      visible: root.chevron
      text: "chevron_right"
      tone: root.enabled ? "faint" : "disabled"
    }
  }

  MouseArea {
    id: area

    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
