pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import qs.components.reusable
import qs.config

// The head of a modal's card (the prompt, the polkit prompt, the screen-share
// picker): an icon well (an app's own icon, when `iconSource` gives one, sits
// bare in it), the headline and, under it, a message or caption. Anything
// else the head carries (a tab row) goes in the default slot, right of the
// text.
RowLayout {
  id: root

  // A Material symbol for the well
  property string icon: "info"
  // An icon file shown instead (an app's); empty = the symbol
  property url iconSource: ""
  property string title: ""
  property string message: ""
  // The message's role and colour: body for a request's own text, a faint
  // caption for a hint
  property string messageRole: "body"
  property string messageTone: ""
  // The message may run to several lines (a request's text) or is one line
  property bool messageWraps: true
  default property alias extra: extraRow.data

  spacing: Style.space5

  Item {
    Layout.alignment: Qt.AlignTop
    implicitWidth: Widget.px(40)
    implicitHeight: Widget.px(40)

    Surface {
      id: well
      anchors.fill: parent
      tone: "accentContainer"
      radius: Style.radius
      visible: appIcon.source.toString() === ""

      StyledIcon {
        anchors.centerIn: parent
        text: root.icon
        size: "md"
        textColor: well.ink.icon
      }
    }

    IconImage {
      id: appIcon
      anchors.fill: parent
      source: root.iconSource
      visible: source.toString() !== ""
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      Layout.fillWidth: true
      text: root.title
      role: "headline"
      overflow: "wrap"
    }

    StyledText {
      Layout.fillWidth: true
      visible: text !== ""
      text: root.message
      role: root.messageRole
      tone: root.messageTone
      overflow: root.messageWraps ? "wrap" : "line"
    }
  }

  RowLayout {
    id: extraRow
    Layout.alignment: Qt.AlignVCenter
    spacing: Widget.spacing
  }
}
