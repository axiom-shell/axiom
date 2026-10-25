pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The time in several places (TimeZoneManager), here first if `showLocal`.
// Each says how far it is from here and whether it's another day there. As
// rows, the place beside its time, with a band of its day (light from 7 to
// 19, a mark at now) when there's room; side by side as tiles in a wide,
// short card. Rows that don't fit are left off; compact, the first place
// away from here.
// properties: { clocks: [{ timezone, label }], showLocal, use24Hour,
// showTimeline }
Card {
  id: root

  readonly property var clocks: (root.properties.showLocal ? [
      {
        "timezone": "",
        "label": ""
      }
    ] : []).concat(root.properties.clocks ?? [])
  readonly property var zones: root.clocks.map(c => c.timezone).filter(z => z !== "")
  readonly property int count: root.clocks.length

  // Tiles side by side when rows wouldn't fit the height but tiles fit
  // the width; else rows, as many as fit
  readonly property real rowMin: Appearance.fontSize * 2.4
  readonly property real tileMinWidth: Appearance.fontSize * 7
  readonly property real tileHeight: Appearance.fontSize * 4.4
  readonly property bool tiles: root.count > 1 && root.innerHeight < root.count * root.rowMin && root.innerWidth >= root.tileMinWidth * 2 && root.innerHeight >= root.tileHeight
  readonly property int columns: root.tiles ? Math.min(root.count, Math.floor(root.innerWidth / root.tileMinWidth)) : 1
  readonly property int shown: root.tiles ? Math.min(root.count, root.columns * Math.max(1, Math.floor(root.innerHeight / root.tileHeight))) : Math.max(1, Math.min(root.count, Math.floor(root.innerHeight / root.rowMin)))
  // Shared out, but never so tall the rows drift apart
  readonly property real rowHeight: root.tiles ? 0 : Math.min(Appearance.fontSize * 5, (root.innerHeight - Widget.spacing * (root.shown - 1)) / root.shown)
  readonly property bool timeline: (root.properties.showTimeline ?? true) && !root.tiles && root.innerWidth >= Appearance.fontSize * 18 && root.rowHeight >= Appearance.fontSize * 3.6

  fullMinWidth: Appearance.fontSize * 9
  fullMinHeight: Appearance.fontSize * 2.4

  function cityOf(place) {
    if (place.label)
      return place.label;
    if (!place.timezone)
      return I18n.tr("Here");
    return place.timezone.split("/").pop().replace(/_/g, " ");
  }

  // The clock's wall time ("" zone: the system's)
  function timeIn(zone) {
    return TimeZones.shift(clock.date, TimeZoneManager.offsetOf(zone));
  }

  function timeText(date) {
    return I18n.formatDate(date, I18n.dateFormat(root.properties.use24Hour ? "clock24" : "clock12"));
  }

  // "+9 h", "−5:30 h" from here, and "Tomorrow"/"Yesterday" when its date
  // isn't today's (nothing for here itself)
  function detailOf(place) {
    if (!place.timezone)
      return "";
    const zoned = TimeZoneManager.offsetOf(place.timezone);
    const parts = [];
    if (zoned !== null) {
      const diff = zoned + place.date.getTimezoneOffset();
      if (diff === 0) {
        parts.push(I18n.tr("Same time"));
      } else {
        const hours = Math.floor(Math.abs(diff) / 60);
        const minutes = Math.abs(diff) % 60;
        parts.push(I18n.tr("{0} h", (diff < 0 ? "−" : "+") + hours + (minutes ? ":" + String(minutes).padStart(2, "0") : "")));
      }
    }
    const day = root.dayText(root.timeIn(place.timezone), place.date);
    if (day !== "")
      parts.push(day);
    return parts.join(" · ");
  }

  function dayText(there, here) {
    const days = Math.round((new Date(there.getFullYear(), there.getMonth(), there.getDate()) - new Date(here.getFullYear(), here.getMonth(), here.getDate())) / 86400000);
    return days > 0 ? I18n.tr("Tomorrow") : days < 0 ? I18n.tr("Yesterday") : "";
  }

  onZonesChanged: TimeZoneManager.acquire(root, root.zones)
  Component.onCompleted: TimeZoneManager.acquire(root, root.zones)
  Component.onDestruction: TimeZoneManager.release(root)

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  compactContent: CompactFigure {
    id: figure
    readonly property var first: root.clocks.find(c => c.timezone !== "") ?? root.clocks[0] ?? null
    icon: figure.first ? "" : "schedule"
    value: figure.first ? root.timeText(root.timeIn(figure.first.timezone)) : ""
    label: figure.first ? root.cityOf(figure.first) : I18n.tr("No clocks")
  }

  // A day there: dark at night, light from 7 to 19, a mark at now
  component DayBand: Item {
    id: band
    required property date there

    implicitHeight: Math.round(Appearance.fontSize * 0.4)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: Qt.alpha(Theme.foreground, 0.12)
    }
    Rectangle {
      x: parent.width * 7 / 24
      width: parent.width * 12 / 24
      height: parent.height
      radius: height / 2
      color: Qt.alpha(Theme.accent, 0.45)
    }
    Rectangle {
      readonly property real at: (band.there.getHours() + band.there.getMinutes() / 60) / 24
      x: Math.round(parent.width * at - width / 2)
      anchors.verticalCenter: parent.verticalCenter
      width: Widget.px(3)
      height: parent.height + Widget.px(6)
      radius: 1.5
      color: Theme.accent
    }
  }

  EmptyState {
    visible: root.count === 0
    anchors.centerIn: parent
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: "travel_explore"
    text: I18n.tr("Add places in this module's settings")
  }

  // Centred in the card, rows or tiles
  GridLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: root.pad
    columns: root.columns
    columnSpacing: root.pad
    rowSpacing: Widget.spacing
    uniformCellWidths: true

    Repeater {
      model: root.count

      Item {
        id: entry
        required property int index
        readonly property var place: root.clocks[index] ?? ({
            "timezone": "",
            "label": ""
          })
        readonly property date there: root.timeIn(entry.place.timezone)
        readonly property bool day: entry.there.getHours() >= 7 && entry.there.getHours() < 19
        readonly property bool local: entry.place.timezone === ""

        visible: entry.index < root.shown
        Layout.fillWidth: true
        Layout.preferredHeight: root.tiles ? root.tileHeight : root.rowHeight

        // A tile: the place over its time and the difference
        ColumnLayout {
          visible: root.tiles
          anchors.centerIn: parent
          width: parent.width
          spacing: 0

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            spacing: Widget.spacing / 2
            StyledIcon {
              text: entry.day ? "light_mode" : "dark_mode"
              textColor: entry.local ? Theme.accent : Theme.foregroundAlt
              textSize: Appearance.fontSizeBy(-1)
            }
            StyledText {
              Layout.fillWidth: true
              text: root.cityOf(entry.place)
              textSize: Appearance.fontSizeBy(-1)
              elide: Text.ElideRight
            }
          }
          StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.timeText(entry.there)
            textSize: Appearance.fontSize * 1.6
            textColor: entry.local ? Theme.accent : Theme.foreground
            font.bold: true
            font.features: {
              "tnum": 1
            }
          }
          StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            text: root.detailOf({
              "timezone": entry.place.timezone,
              "date": clock.date
            })
            textSize: Appearance.fontSizeBy(-3)
            textColor: Theme.foregroundAlt
            elide: Text.ElideRight
          }
        }

        // A row: the place and the difference, the time on the right, the
        // day's band under them
        ColumnLayout {
          visible: !root.tiles
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Widget.spacing / 2

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledIcon {
              text: entry.day ? "light_mode" : "dark_mode"
              textColor: entry.local ? Theme.accent : Theme.foregroundAlt
              textSize: Appearance.fontSizeBy(2)
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              StyledText {
                Layout.fillWidth: true
                text: root.cityOf(entry.place)
                textSize: Math.max(Appearance.fontSize, Math.min(Appearance.fontSize * 1.3, root.rowHeight * 0.24))
                font.bold: entry.local
                elide: Text.ElideRight
              }
              StyledText {
                Layout.fillWidth: true
                visible: text !== "" && root.rowHeight >= Appearance.fontSize * 2.6
                text: root.detailOf({
                  "timezone": entry.place.timezone,
                  "date": clock.date
                })
                textSize: Appearance.fontSizeBy(-3)
                textColor: Theme.foregroundAlt
                elide: Text.ElideRight
              }
            }
            StyledText {
              text: root.timeText(entry.there)
              textSize: Math.max(Appearance.fontSize, Math.min(Appearance.fontSize * 2, root.rowHeight * 0.42))
              textColor: entry.local ? Theme.accent : Theme.foreground
              font.bold: true
              font.features: {
                "tnum": 1
              }
            }
          }

          DayBand {
            visible: root.timeline
            Layout.fillWidth: true
            there: entry.there
          }
        }
      }
    }
  }
}
