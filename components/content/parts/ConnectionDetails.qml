pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// A connection's details (NetworkingManager.details) as label / value
// lines: addresses, gateway, DNS, MAC, and the link (a wire's speed, or
// Wi-Fi's band, channel and bitrate); the addresses can be copied. Lines
// with nothing to say are left out. `rowCount` is its most lines, for
// room kept before it shows (Panel.maxImplicitHeight).
GridLayout {
  id: root

  // net.details' answer, or null while it's read
  property var details: null
  readonly property int rowCount: 7
  // One line's height
  readonly property real lineHeight: Math.max(metrics.height, Widget.smallHeight)

  readonly property string link: {
    const d = root.details;
    if (!d)
      return "";
    if (d.kind === "ethernet")
      return d.speed > 0 ? I18n.tr("{0} Mb/s", d.speed) : "";
    const parts = [];
    if (d.band !== "")
      parts.push(I18n.tr("{0} GHz", d.band));
    if (d.channel > 0)
      parts.push(I18n.tr("channel {0}", d.channel));
    if (d.bitrate > 0)
      parts.push(I18n.tr("{0} Mb/s", d.bitrate));
    return parts.join(" · ");
  }
  // [label, value, copyable] for each line with a value
  readonly property var lines: {
    const d = root.details;
    if (!d)
      return [];
    return [[I18n.tr("IPv4"), d.ipv4, true], [I18n.tr("Gateway"), d.gateway, false], [I18n.tr("DNS"), (d.dns ?? []).join(", "), false], [I18n.tr("IPv6"), d.ipv6, true], [I18n.tr("Link"), root.link, false], [I18n.tr("MAC"), d.mac, true]].filter(l => l[1] !== "");
  }

  columns: 3
  columnSpacing: Widget.spacing
  rowSpacing: 0

  FontMetrics {
    id: metrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-3)
  }

  StyledText {
    visible: root.details === null
    Layout.columnSpan: 3
    Layout.preferredHeight: root.lineHeight
    text: I18n.tr("Reading…")
    textSize: Appearance.fontSizeBy(-3)
    textColor: Theme.foregroundAlt
  }

  Repeater {
    // By count, so lines keep their items as values change
    model: root.lines.length * 3

    Item {
      id: cell
      required property int index
      readonly property var line: root.lines[Math.floor(index / 3)] ?? ["", "", false]
      readonly property int column: index % 3
      Layout.fillWidth: cell.column === 1
      Layout.preferredHeight: root.lineHeight
      implicitWidth: cell.column === 0 ? label.implicitWidth : cell.column === 2 ? root.lineHeight : 0

      StyledText {
        id: label
        visible: cell.column < 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: cell.column === 0 ? cell.line[0] : cell.line[1]
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-3)
        textColor: cell.column === 0 ? Theme.foregroundAlt : Theme.foreground
      }

      FlatIconButton {
        visible: cell.column === 2 && cell.line[2]
        anchors.centerIn: parent
        size: root.lineHeight
        iconText: "content_copy"
        iconSize: Appearance.fontSizeBy(-2)
        tooltipText: I18n.tr("Copy")
        onClicked: ClipboardManager.copyText(cell.line[1].split("/")[0])
      }
    }
  }
}
