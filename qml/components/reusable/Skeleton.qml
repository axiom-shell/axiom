pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config

// A loading placeholder in the shape of the content coming: bars the height
// of a text role's line, the last one shorter, optionally a round avatar
// first, with a soft shimmer sweeping across. Shown while a service has no
// data yet and no error; spinners stay for actions in progress.
Item {
  id: root

  // -- Public API --
  property int lines: 3
  // The text role whose line height the bars take
  property string role: "body"
  // How much of the full width the last bar takes
  property real lastLineShare: 0.6
  // A round `Style.iconLg` disc before the bars
  property bool avatar: false

  // -- Implementation --
  readonly property int _bar: Math.round(Style.textRole(root.role).size * 0.8)
  // The shimmer's position, 0 to 1 across a bar
  property real _phase: 0

  implicitWidth: Widget.px(200)
  implicitHeight: Math.max(row.implicitHeight, 0)

  NumberAnimation on _phase {
    from: 0
    to: 1
    duration: Style.shimmerPeriod
    loops: Animation.Infinite
    running: Appearance.animations && root.visible
  }

  RowLayout {
    id: row

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space3

    Rectangle {
      visible: root.avatar
      Layout.preferredWidth: Style.iconLg
      Layout.preferredHeight: Style.iconLg
      Layout.alignment: Qt.AlignTop
      radius: width / 2
      color: Style.surfaceHighest
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space2

      Repeater {
        model: root.lines

        delegate: ClippingRectangle {
          id: bar

          required property int index
          readonly property bool last: bar.index === root.lines - 1 && root.lines > 1

          Layout.preferredWidth: bar.last ? row.width * root.lastLineShare : -1
          Layout.fillWidth: !bar.last
          Layout.preferredHeight: root._bar
          radius: height / 2
          color: Style.surfaceHighest

          Rectangle {
            width: bar.width * 0.5
            height: bar.height
            x: (root._phase * 1.5 - 0.5) * bar.width
            visible: Appearance.animations
            gradient: Gradient {
              orientation: Gradient.Horizontal

              GradientStop {
                position: 0
                color: Style.surfaceHighest
              }
              GradientStop {
                position: 0.5
                color: Style.surfaceRaised
              }
              GradientStop {
                position: 1
                color: Style.surfaceHighest
              }
            }
          }
        }
      }
    }
  }
}
