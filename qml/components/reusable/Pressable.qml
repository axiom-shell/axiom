pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The keyboard and pointer behaviour of anything clickable that isn't one of
// the button pieces (a chip, a fold row, a tile): it fills its parent, takes a
// Tab stop, `clicked` on a click or on Space, Return or Enter, tints the parent
// on hover and press (a StateLayer), rings it on keyboard focus (a
// FocusRing), and shows the pointing cursor. A right click (with
// `acceptedButtons` including it) is `menuRequested(x, y)` instead. Declare it
// before the content, which draws over its tint; it takes no clicks the
// content takes itself.
Item {
  id: root

  // -- Public API --
  // A control that is one Tab stop with its siblings (a SegmentRow's buttons)
  // turns this off
  property bool tabStop: true
  property int acceptedButtons: Qt.LeftButton
  // The hover and press tint (off: the host tints)
  property bool tinted: true
  // On an accent or other solid fill: the on-fill tints
  property bool onAccent: false
  // How far the tint reaches past the parent's sides (a settings row's)
  property real bleed: 0
  // The tint's and the ring's bottom corners square (a header band over a body)
  property bool squareBottom: false
  // The tint's and the ring's rounding: the parent's
  readonly property real radius: root._host && root._host.radius !== undefined ? root._host.radius : Style.radiusInner
  readonly property bool hovered: area.containsMouse
  readonly property bool pressed: area.pressed

  signal clicked
  signal menuRequested(real x, real y)

  // -- Implementation --
  // (var: qmllint knows only Item's members)
  readonly property var _host: root.parent
  anchors.fill: parent
  activeFocusOnTab: root.tabStop

  Keys.onSpacePressed: event => root._key(event)
  Keys.onReturnPressed: event => root._key(event)
  Keys.onEnterPressed: event => root._key(event)

  function _key(event) {
    event.accepted = true;
    root.clicked();
  }

  StateLayer {
    visible: root.tinted
    hovered: root.hovered
    pressed: root.pressed
    onAccent: root.onAccent
    bleed: root.bleed
    squareBottom: root.squareBottom
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: root.acceptedButtons
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton)
        root.menuRequested(mouse.x, mouse.y);
      else
        root.clicked();
    }
  }

  FocusRing {
    shown: root.activeFocus
    squareBottom: root.squareBottom
  }
}
