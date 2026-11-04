pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A titled, scrolling panel card (settings, theme, bar editor panels):
// header with optional Save/Discard, divider, optional fixed extras (e.g. a
// tab strip), then the scrolling body that children go into.
Card {
  id: root

  property alias title: header.title
  property alias dirty: header.dirty
  property alias showActions: header.showActions
  property alias canSave: header.canSave
  property alias saveLabel: header.saveLabel
  // Fixed content between the divider and the scrolling body
  property alias headerExtras: extras.data
  // Hides the extras with their space (hiding only what's inside can
  // leave the column its old height)
  property bool showExtras: true
  property alias contentSpacing: body.spacing
  // Children go into the scrolling body (Card's own `content` holds this
  // file's column)
  default property alias bodyContent: body.data
  // Remembers where the body was scrolled to under this key (ScrollMemory),
  // so it comes back there when the overlay reopens; empty keeps nothing
  property alias scrollKey: scrollMemory.key

  signal save
  signal reset

  // Scrolls the body so `item` (one of its descendants) sits at the top,
  // or in the middle with `center`, as near as the body's length allows
  function scrollTo(item, center) {
    scrollMemory.cancel();
    // Lays out rows built or shown this frame before measuring
    body.ensurePolished();
    const top = item.mapToItem(body, 0, 0).y - (center === true ? Math.max(0, (scroll.availableHeight - item.height) / 2) : 0);
    scrollAnimation.to = Math.max(0, Math.min(top, scroll.contentHeight - scroll.availableHeight));
    scrollAnimation.restart();
  }

  ScrollMemory {
    id: scrollMemory
    flickable: scroll.contentItem as Flickable
  }

  NumberAnimation {
    id: scrollAnimation
    target: scroll.contentItem
    property: "contentY"
    duration: Appearance.animNormal
    easing.type: Easing.OutCubic
  }

  // Hidden by Card while its compactContent shows
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: 0

    CardHeader {
      id: header
      onSave: root.save()
      onReset: root.reset()
    }

    StyledSeparator {
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing / 2
      Layout.bottomMargin: Widget.spacing / 2
      separatorHeight: 1
      opacity: 0.3
    }

    // Not fillHeight (a layout's default): with its children all hidden it
    // has no maximum, and would take spare height from the body. Its
    // margins are every panel's gaps around the extras, the one below the
    // body's own spacing (the body's top margin when there are none):
    // extras add none
    ColumnLayout {
      id: extras
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.topMargin: Widget.spacing
      Layout.bottomMargin: Widget.spacing * 2
      visible: root.showExtras && children.length > 0
      spacing: Widget.spacing
    }

    ScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.topMargin: extras.visible ? 0 : Widget.spacing
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      contentWidth: availableWidth

      ColumnLayout {
        id: body
        width: scroll.width - Widget.padding * 2
        spacing: Widget.spacing * 2
      }
    }
  }
}
