pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.content.base

// An editor's work surface: a box (`surface`, none with `embedded`, set
// only where this is its pane's only main content) with a header, an
// optional status line and a sunken well holding the work (children). The
// header's extras run in a fixed order: `undoRedo`, `tools`, then Save and
// Discard (`showActions`, `dirty`, `canSave`; signals `save` and `reset`).
// An embedded work area with no `title` draws no header at all.
Surface {
  id: root

  property bool embedded: false
  property string icon: ""
  property string title: ""
  property int count: -1
  property string help: ""
  property bool showActions: true
  property bool dirty: false
  property bool canSave: true
  property alias undoRedo: undoRow.data
  property alias tools: toolsRow.data
  // One caption line under the header (fit, nudge, crowded widgets)
  property alias status: statusRow.data
  // Shown in the status line while `idle`
  property string hintWhenIdle: ""
  property bool idle: false
  // 0: the well fills what it is given; a canvas stacked over an inspector
  // caps it (Widget.px(400))
  property real wellMaxHeight: 0
  default property alias content: well.data

  signal save
  signal reset

  tone: "surface"
  implicitHeight: column.implicitHeight + (root.embedded ? 0 : Widget.padding * 2)

  // Embedded: no box, the pane it sits in is the same tone (`color` and
  // `outlined` return to Surface's own on leaving the state)
  states: State {
    when: root.embedded
    PropertyChanges {
      root.color: "transparent"
      root.outlined: false
    }
  }

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: root.embedded ? 0 : Widget.padding
    spacing: Widget.spacing

    CardHeader {
      visible: !root.embedded || root.title !== ""
      icon: root.icon
      title: root.title
      count: root.count
      help: root.help
      showActions: root.showActions
      dirty: root.dirty
      canSave: root.canSave
      onSave: root.save()
      onReset: root.reset()

      RowLayout {
        id: undoRow
        visible: children.length > 0
        spacing: 0
      }
      RowLayout {
        id: toolsRow
        visible: children.length > 0
        spacing: Widget.spacing / 2
      }
    }

    // Never hidden (its status children would read hidden and it would stay so): with nothing showing, a negative margin takes back the gap the column puts after it
    RowLayout {
      Layout.fillWidth: true
      Layout.bottomMargin: root.idle && root.hintWhenIdle !== "" || statusRow.visibleChildren.length > 0 ? 0 : -Widget.spacing
      spacing: Widget.spacing

      StyledText {
        visible: root.idle && root.hintWhenIdle !== ""
        Layout.fillWidth: true
        role: "caption"
        tone: "muted"
        overflow: "wrap"
        text: root.hintWhenIdle
      }
      RowLayout {
        id: statusRow
        spacing: Widget.spacing
      }
    }

    // The well: the work sits on it
    Surface {
      id: wellBox
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.maximumHeight: root.wellMaxHeight > 0 ? root.wellMaxHeight : Number.POSITIVE_INFINITY
      tone: "sunken"
      clip: true

      Item {
        id: well
        anchors.fill: parent
      }
    }
  }
}
