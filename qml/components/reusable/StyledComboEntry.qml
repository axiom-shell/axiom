pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.config

// A choice from a list that drops down under the field, optionally typed
// (`editable`): typing filters the list and Enter takes what was typed, or
// the highlighted match. Up/Down move through the list (opening it), and
// Escape closes it. `options` is [{ value, label, icon?, image?, swatch?,
// swatchInk? }] (icon a glyph, image a picture's path: an app's icon; swatch
// a colour name the row is filled with, its label drawn in swatchInk, picked
// once per option by the options' owner); `value` is the
// current choice, which the field shows unless it's being typed in (the
// push pattern: picking emits `picked`, the owner sets `value`).
// `search` (a function of the typed text returning options) replaces the
// options and their filter, for a list too long to hold (the icon picker):
// it's asked only once the list opens or something is typed.
// `expandsInline` opens the list under the field inside it instead, the
// field growing by its height: on by itself in a popout or edge menu (its
// window declares `popoutRoom`), where a Popup would be a window of its own
// their hover and blur don't reach. The list is no taller than the room
// the popout's box has left to grow, or, where it doesn't grow (null), than
// the Flickable it's in shows below the field; that Flickable scrolls it
// into view.
Item {
  id: root

  property var options: []
  // (query) => [{ value, label, icon? }], instead of `options`
  property var search: null
  property string value: ""
  // Anything may be typed, not only the options
  property bool editable: false
  // Typing highlights no match unless one is exactly what was typed, so
  // Enter takes the typed text (the arrows still pick a match)
  property bool typedFirst: false
  // Shown but not changeable
  property bool readOnly: false
  property alias placeholderText: entry.placeholderText
  property alias input: entry.input
  // A leading icon in the field
  property string icon: ""
  // Read through a var: QsWindow.window is typed QObject
  readonly property var _window: root.QsWindow.window
  // The list opens in the layout, not over it (see above)
  property bool expandsInline: root._window?.popoutRoom !== undefined

  signal picked(string value)

  property string query: ""
  property int highlighted: 0

  // When the dropdown last began to close: a press outside closes it and
  // still reaches the row under it
  property real hiddenAt: 0
  property bool _inlineOpen: false
  readonly property bool _hasList: root.search !== null || root.options.length > 0
  // The inline list's most height, as it opens (read once: the room
  // shrinks as the list takes it), at least two rows
  property real _inlineCap: Number.POSITIVE_INFINITY

  // The Flickable it's in, if any
  function _scroller(): Flickable {
    for (let item = root.parent; item; item = item.parent) {
      const scroller = item as Flickable;
      if (scroller)
        return scroller;
    }
    return null;
  }

  function _roomBelow() {
    // Inside the list's box: its gap from the field and its padding
    const chrome = Widget.spacing * 2.5;
    const room = root._window?.popoutRoom;
    if (room === undefined)
      return Number.POSITIVE_INFINITY;
    if (room !== null)
      return room - chrome;
    const scroller = root._scroller();
    return scroller ? scroller.height - entry.height - chrome : 0;
  }

  // Scrolls the Flickable it's in to show the field and its open list
  function _reveal() {
    const scroller = root._scroller();
    if (!scroller)
      return;
    const top = root.mapToItem(scroller.contentItem, 0, 0).y;
    let y = scroller.contentY;
    if (top + root.height > y + scroller.height)
      y = top + root.height - scroller.height;
    scroller.contentY = Math.max(0, Math.min(y, top));
  }
  onHeightChanged: if (root._inlineOpen)
    Qt.callLater(root._reveal)
  // The dropdown, built the first time it opens (a closed one is never
  // built: a page of these fields would build every list and shadow)
  readonly property Popup _dropdown: dropdownLoader.item as Popup
  readonly property bool listOpen: root.expandsInline ? root._inlineOpen : root._dropdown?.opened ?? false
  readonly property ListView _list: root.expandsInline ? inlineList.item as ListView : root._dropdown?.contentItem as ListView

  readonly property var matches: {
    // Asked once the list shows (a Popup's `opened` waits out its enter
    // transition, `visible` doesn't) or something is typed
    if (root.search)
      return root._inlineOpen || (root._dropdown?.visible ?? false) || root.query !== "" ? root.search(root.query) : [];
    const query = root.query.trim().toLowerCase();
    if (!root.editable || query === "")
      return root.options;
    return root.options.filter(option => String(option.label).toLowerCase().includes(query) || String(option.value).toLowerCase().includes(query));
  }

  function labelOf(value) {
    return root.options.find(option => option.value === value)?.label ?? value;
  }

  function showValue() {
    root._showText(root.editable ? root.value : root.labelOf(root.value));
  }

  // Sets the field's text without it counting as typing (which would
  // filter and reopen the list, and be taken as a pick on focus loss)
  function _showText(text) {
    entry.typed = false;
    entry.input.text = text;
  }

  function openList() {
    if (root.readOnly || !root._hasList)
      return;
    if (root.expandsInline) {
      root._inlineCap = Math.max(Widget.height * 2, root._roomBelow());
      root._inlineOpen = true;
    } else {
      dropdownLoader.active = true;
      root._dropdown.open();
    }
    // Once open: a `search` list is empty until then
    root.highlighted = Math.max(0, root.matches.findIndex(option => option.value === root.value));
    root._list?.positionViewAtIndex(root.highlighted, ListView.Contain);
  }

  function move(step) {
    if (!root.listOpen) {
      root.openList();
      return;
    }
    if (root.matches.length === 0)
      return;
    root.highlighted = Math.max(0, Math.min(root.matches.length - 1, root.highlighted + step));
    root._list?.positionViewAtIndex(root.highlighted, ListView.Contain);
  }

  function closeList() {
    root._inlineOpen = false;
    root._dropdown?.close();
  }

  // A click on the form row holding it, off the field (SchemaComboBox's
  // and the custom widgets' InspectorRow's rowClicked, FormRow.activates):
  // opens or closes the list. A press outside an open list closes it and is
  // the same click that reaches the row: that click must not open the list
  // again
  function activate() {
    if (root.listOpen)
      root.closeList();
    else if (Date.now() - root.hiddenAt > Application.styleHints.mouseDoubleClickInterval)
      root.openList();
  }

  function pick(value) {
    root.closeList();
    root.query = "";
    // The field shows the pick before the owner hears of it: an owner that
    // moves focus on `picked` would otherwise have the stale text taken as
    // typed when the field loses focus, undoing the pick
    root._showText(root.editable ? value : root.labelOf(value));
    root.picked(value);
    Qt.callLater(root.showValue);
  }

  // Enter: the highlighted match from an open list, else what was typed
  function accept() {
    if (root.listOpen && root.matches[root.highlighted])
      root.pick(root.matches[root.highlighted].value);
    else if (root.editable)
      root.pick(entry.input.text.trim());
  }

  implicitHeight: Widget.height + inlineBox.height
  implicitWidth: Widget.px(200)

  // Followed unless it's being typed over
  onValueChanged: if (!entry.typed || !entry.input.activeFocus)
    root.showValue()
  onOptionsChanged: if (!entry.typed || !entry.input.activeFocus)
    root.showValue()
  Component.onCompleted: root.showValue()

  StyledTextEntry {
    id: entry
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: parent.height - inlineBox.height
    readOnly: root.readOnly || !root.editable
    input.leftPadding: root.icon !== "" ? Style.iconSm * 1.6 : 0
    input.rightPadding: Style.iconSm * 1.6
    // One line, cut off rather than wrapped in a narrow field
    input.wrapMode: TextInput.NoWrap
    onTextEdited: {
      if (!root.editable)
        return;
      root.query = entry.text;
      root.highlighted = root.typedFirst && !root.matches.some(option => option.value === root.query.trim()) ? -1 : 0;
      if (!root.listOpen && root.matches.length > 0)
        root.openList();
    }
    onAccepted: root.accept()
    // The field passes these on (single-line text takes none of them)
    Keys.onUpPressed: root.move(-1)
    Keys.onDownPressed: root.move(1)
    Keys.onEscapePressed: event => {
      if (root.listOpen)
        root.closeList();
      else
        event.accepted = false;
    }

    // Leaving a field typed in takes what's in it; one only looked at
    // shows the value again
    Connections {
      target: entry.input
      function onActiveFocusChanged() {
        if (entry.input.activeFocus)
          return;
        // An inline list has no outside click of its own to close on
        root._inlineOpen = false;
        if (!root.editable)
          return;
        if (entry.typed && entry.input.text.trim() !== root.value)
          root.pick(entry.input.text.trim());
        else
          root.showValue();
      }
    }

    StyledIcon {
      visible: root.icon !== ""
      anchors.left: parent.left
      anchors.leftMargin: Widget.padding
      anchors.verticalCenter: parent.verticalCenter
      text: root.icon
      tone: "muted"
    }

    StyledIcon {
      visible: !root.readOnly && root._hasList
      anchors.right: parent.right
      anchors.rightMargin: Widget.smallPadding
      anchors.verticalCenter: parent.verticalCenter
      text: "expand_more"
      tone: "muted"
      // Turns over as the list opens
      rotation: root.listOpen ? 180 : 0
      Glide on rotation {
        duration: Appearance.animNormal
      }
    }
  }

  // A plain list (not typed) opens on a click anywhere on it; a typed one
  // only on its chevron, so the text stays clickable
  MouseArea {
    anchors.fill: entry
    anchors.leftMargin: root.editable ? entry.width - Style.iconSm * 2 : 0
    enabled: !root.readOnly
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      entry.input.forceActiveFocus();
      root.listOpen ? root.closeList() : root.openList();
    }
  }

  // At the field's corner, so the popup's place is measured from the field;
  // kept once built, so it closes with its animation
  Loader {
    id: dropdownLoader
    active: false
    sourceComponent: dropdownComponent
  }

  Component {
    id: dropdownComponent

    Popup {
      id: dropdown
      // How far the list still has to slide up into place while it opens
      property real _shift: 0
      y: root.height + Widget.spacing / 2
      width: root.width
      // Rows are inset from the rounded border (as SchemaComboBox's), so
      // the highlight never meets it
      padding: Widget.spacing
      // The field keeps the keys: the list is driven from it
      focus: false
      closePolicy: Popup.CloseOnPressOutsideParent

      // Slides down out of the field, fading in
      enter: Transition {
        NumberAnimation {
          property: "opacity"
          from: 0
          to: 1
          duration: Appearance.animNormal
          easing.type: Appearance.easing
        }
        NumberAnimation {
          property: "_shift"
          from: -Style.enterOffset
          to: 0
          duration: Appearance.animNormal
          easing.type: Appearance.easing
        }
      }
      exit: Transition {
        NumberAnimation {
          property: "opacity"
          to: 0
          duration: Appearance.animFast
          easing.type: Appearance.easing
        }
      }

      // Solid: it opens inside its window, where no blur reaches
      background: DropdownSurface {
        transform: Translate {
          y: Math.round(dropdown._shift)
        }
      }

      contentItem: ListView {
        transform: Translate {
          y: Math.round(dropdown._shift)
        }
        implicitHeight: Math.min(contentHeight, Widget.height * 6)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.matches
        delegate: optionDelegate

        ScrollIndicator.vertical: StyledScrollIndicator {}
      }

      onAboutToHide: root.hiddenAt = Date.now()
    }
  }

  // The inline list: fades in at its full height (a popout's box grows to
  // it), and keeps that height until it has faded out. Its list is built
  // only where lists open inline (the surface, layerless, is cheap)
  Item {
    id: inlineBox
    visible: root.expandsInline && opacity > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: visible ? Widget.spacing / 2 + inlineSurface.height : 0
    opacity: root._inlineOpen ? 1 : 0

    Glide on opacity {
      duration: root._inlineOpen ? Appearance.animNormal : Appearance.animFast
    }

    DropdownSurface {
      id: inlineSurface
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: inlineList.implicitHeight + Widget.spacing * 2
      floating: false

      Loader {
        id: inlineList
        active: root.expandsInline
        anchors.fill: parent
        anchors.margins: Widget.spacing
        sourceComponent: ListView {
          implicitHeight: Math.min(contentHeight, Widget.height * 6, root._inlineCap)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.matches
          delegate: optionDelegate

          ScrollIndicator.vertical: StyledScrollIndicator {}
        }
      }
    }
  }

  Component {
    id: optionDelegate

    Item {
      id: option
      required property var modelData
      required property int index
      // A colour option: the row is its colour, its label in the ink the
      // options' owner picked for it
      readonly property bool swatched: (modelData.swatch ?? "") !== ""

      width: ListView.view.width
      height: Widget.height

      // One look per row, built only for it
      Loader {
        anchors.fill: parent
        active: !option.swatched
        sourceComponent: MenuRow {
          icon: option.modelData.icon ?? ""
          image: option.modelData.image ?? ""
          text: option.modelData.label
          current: option.modelData.value === root.value
          lit: option.index === root.highlighted
          onHoveredChanged: {
            if (hovered)
              root.highlighted = option.index;
          }
          onActivated: root.pick(option.modelData.value)
        }
      }

      Loader {
        anchors.fill: parent
        active: option.swatched
        sourceComponent: Rectangle {
          radius: Style.radiusInner
          color: Style.resolve(option.modelData.swatch ?? "")
          border.width: option.modelData.value === root.value ? Style.focusWidth : 0
          border.color: Style.focusRing

          StateLayer {
            hovered: swatchArea.containsMouse || option.index === root.highlighted
            pressed: swatchArea.pressed
          }

          StyledLabel {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Widget.padding
            anchors.rightMargin: Widget.padding
            role: "label"
            overflow: "line"
            text: option.modelData.label
            textColor: Style.resolve(option.modelData.swatchInk ?? "")
          }

          MouseArea {
            id: swatchArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.highlighted = option.index
            onClicked: root.pick(option.modelData.value)
          }
        }
      }
    }
  }
}
