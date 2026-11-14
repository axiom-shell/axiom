pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// One event in a list: its calendar's color, the title, and when (on
// `dayKey`) and where. A click opens it (unless not `clickable`).
Rectangle {
  id: root

  required property var event
  property string dayKey: ""
  // A second line for the time and place; without, the time leads the title
  property bool twoLines: true
  property bool clickable: true

  signal clicked

  readonly property string when: root.event ? CalendarManager.timeText(root.event, root.dayKey) : ""

  Layout.fillWidth: true
  implicitHeight: content.implicitHeight + Widget.spacing
  radius: Widget.radius
  color: "transparent"

  StateLayer {
    hovered: area.containsMouse && root.clickable
    pressed: area.pressed && root.clickable
  }

  // Fades in as its list (a day, the agenda) is shown or changes
  NumberAnimation on opacity {
    from: 0
    to: 1
    duration: Appearance.animNormal
    easing.type: Appearance.easing
  }

  RowLayout {
    id: content
    anchors.fill: parent
    anchors.leftMargin: Widget.spacing / 2
    anchors.rightMargin: Widget.spacing / 2
    spacing: Widget.spacing

    Rectangle {
      Layout.preferredWidth: Widget.px(4)
      Layout.fillHeight: true
      Layout.topMargin: Widget.spacing / 2
      Layout.bottomMargin: Widget.spacing / 2
      radius: 2
      color: Style.resolve(CalendarManager.colors[root.event?.calendar] ?? "accent")
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing / 2
      Layout.bottomMargin: Widget.spacing / 2
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        // As wide as the widest time range, so a list's titles line up
        StyledLabel {
          visible: !root.twoLines
          Layout.minimumWidth: widest.implicitWidth
          Layout.rightMargin: Widget.spacing / 2
          text: root.when
          role: "caption"
        }
        StyledLabel {
          Layout.fillWidth: true
          text: root.event?.title || I18n.tr("(No title)")
          textFormat: Text.PlainText
          overflow: "line"
        }
        StyledIcon {
          visible: root.event?.recurring ?? false
          text: "repeat"
          size: "xs"
          tone: "muted"
        }
      }
      StyledLabel {
        visible: root.twoLines
        Layout.fillWidth: true
        text: root.event?.location ? I18n.tr("{0} · {1}", root.when, root.event.location) : root.when
        textFormat: Text.PlainText
        role: "caption"
        overflow: "line"
      }
    }
  }

  StyledText {
    id: widest
    visible: false
    readonly property string sample: I18n.formatDate(new Date(2000, 0, 1, 22, 58), CalendarConfig.timeFormat)
    text: I18n.tr("{0} – {1}", sample, sample)
    role: "caption"
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
