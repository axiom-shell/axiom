pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout

// An integrated edge menu: a Top-layer strip along the whole edge whose
// exclusive zone is arranged before everything else's (the axiom-edge-menu
// layer rule, render.LayerRulesLua), so it sits outermost and the
// border, bars and windows move inwards while it's open. The zone is set
// once when it opens (windows retile in one step), then the strip slides
// in; closing slides it out before the zone goes. With `frame` on, a
// rounded box runs the strip's whole length (its stroke ending the screen
// margin in from its edges, lining up with the screen border's) and the
// modules sit in it, `padding` in from its stroke. Along the edge they sit
// on the menu's lattice (GridPlacement.menuAlong).
//
// Open/close and hover-loss dismissal are PopoutWrapperBase's, as for the
// popouts.
PopoutWrapperBase {
  id: root

  required property var menu
  required property ShellScreen screen

  readonly property int edge: EdgeMenusConfig.edgeOf(root.menu)
  readonly property bool vertical: root.edge === ScreenEdge.Left || root.edge === ScreenEdge.Right

  readonly property bool framed: root.menu.frame
  readonly property int padding: EdgeMenusConfig.paddingOf(root.menu)
  readonly property var colors: EdgeMenusConfig.colorsOf(root.menu)
  // The frame's inset from the strip's edges (0 without one): the screen
  // margin reaches its stroke's inner edge, as the screen border's does, so
  // the two strokes line up
  readonly property int frameInset: root.framed ? Math.max(0, Appearance.screenMargin - Appearance.borderWidth) : 0
  // From the strip's edges to the cards: the frame and its stroke, then
  // the padding
  readonly property int pad: root.frameInset + (root.framed ? Appearance.borderWidth : 0) + root.padding
  // With the screen border off, the strip's own inner stroke (with it on,
  // the border's strip inside this one draws it)
  readonly property int innerStroke: Appearance.screenBorder ? 0 : Appearance.borderWidth
  readonly property real edgeLength: root.vertical ? root.screen?.height ?? 0 : root.screen?.width ?? 0
  readonly property real bodyDepth: root.vertical ? (loader.item?.implicitWidth ?? 0) : (loader.item?.implicitHeight ?? 0)
  readonly property int depth: Math.ceil(root.bodyDepth + root.pad * 2 + root.innerStroke)
  // Where the modules start along the edge, from config (the body loads
  // only while open, and the hover strip needs it closed)
  // Its card size (EdgeMenusConfig.cardUnitOf)
  readonly property int unit: EdgeMenusConfig.cardUnitOf(root.menu)
  readonly property real cardGap: EdgeMenusConfig.gapOf(root.menu)
  readonly property real gridLength: EdgeMenusConfig.gridLengthOf(root.menu, root.vertical, root.unit, root.cardGap)
  readonly property real alongPos: GridPlacement.menuAlong(root.menu, root.edgeLength, root.unit, root.pad, root.pad, root.cardGap)

  // Where the modules can sit, for the layouts editor (EdgeMenuManager.frames)
  readonly property var frame: ({
      "screen": root.screen?.name ?? "",
      "startPad": root.pad,
      "endPad": root.pad,
      "across": root.pad,
      "before": 0,
      "after": root.pad + root.innerStroke,
      "reserves": true
    })

  autoDismiss: sync.autoDismiss
  // Asked to come forward (EdgeMenuManager.engageRequested): it holds no
  // popout claim, so there's no rank to raise (EdgePopout.engage)
  function engage() {
  }
  dismissDelay: root.menu.close.delay
  keepAlive: panelHover.hovered || trigger.containsMouse
  window: panel

  EdgeMenuSync {
    id: sync
    host: root
    menu: root.menu
    screen: root.screen
    window: root.window
    triggerWindow: trigger
    frame: root.frame
    onWarpRequested: CompositorManager.warpCursorToLayer("axiom-edge-menu", root.screen?.name ?? "", panel.width, panel.height, loader.x + loader.width / 2, loader.y + loader.height / 2)
  }
  Component.onDestruction: ScreenEdgeManager.setZone(root.screen?.name ?? "", root._edgeName, 0)

  // Report the space taken, for surfaces laid out against this edge
  readonly property string _edgeName: ScreenEdge.name(root.edge)
  readonly property int reserved: panel.visible && !menuSlot.idle ? root.depth : 0
  onReservedChanged: ScreenEdgeManager.setZone(root.screen?.name ?? "", root._edgeName, root.reserved)

  EdgeTrigger {
    id: trigger
    screen: root.screen
    visible: root.menu.open.onHover
    edge: root.edge
    // On the modules (the strip spans the whole edge)
    centre: root.menu.length === "edge" ? root.edgeLength / 2 : root.alongPos + root.gridLength / 2
    // Not its own zone, and the strip spans the whole edge regardless of
    // the others
    edgeInset: Math.max(0, ScreenEdgeManager.zoneOn(root.screen?.name ?? "", root._edgeName) - root.reserved)
    startInset: 0
    endInset: 0
    triggerWidth: root.menu.trigger.size
    triggerLength: sync.triggerLength(loader.item, root.vertical, root.pad)
    hoverDelay: root.menu.open.delay
    onTriggered: root.show()
  }

  PanelWindow {
    id: panel
    screen: root.screen
    // Mapped only while open: the zone (and the windows moving) goes with
    // it; once the windows before it in the stack have mapped
    visible: menuSlot.shown
    LayerSlot {
      id: menuSlot
      window: panel
      namespace: "axiom-edge-menu"
      wanted: root.occupied && loader.status === Loader.Ready
      // Where map order alone stacks: mapped from the start, a pixel deep,
      // reserving nothing while closed, so opening never maps it after
      // the bars and border it pushes inwards
      held: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "axiom-edge-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: menuSlot.idle ? 0 : root.depth
    // No input while idle (LayerSlot.held)
    mask: menuSlot.idle ? panel._noInput : null
    property Region _noInput: Region {}

    anchors {
      top: root.edge === ScreenEdge.Top || root.vertical
      bottom: root.edge === ScreenEdge.Bottom || root.vertical
      left: root.edge === ScreenEdge.Left || !root.vertical
      right: root.edge === ScreenEdge.Right || !root.vertical
    }

    implicitWidth: root.vertical ? (menuSlot.idle ? 1 : root.depth) : 0
    implicitHeight: root.vertical ? 0 : (menuSlot.idle ? 1 : root.depth)

    // Where the window is on screen: the blur window draws the strip's
    // fill (BlurManager) from there, as it slides
    LayerOrigin {
      id: placeOnScreen
      window: panel
      namespace: "axiom-edge-menu"
      edge: root.edge
    }
    readonly property bool backed: BlurManager.backsOn(root.screen, false) && placeOnScreen.origin !== null

    SlideAnimation {
      id: slide
      anchors.fill: parent
      visible: !menuSlot.idle
      active: root.isOpen
      slideFromLeft: root.edge === ScreenEdge.Left
      slideFromRight: root.edge === ScreenEdge.Right
      slideFromTop: root.edge === ScreenEdge.Top
      slideFromBottom: root.edge === ScreenEdge.Bottom
      enableFade: false
      containerWidth: panel.width
      containerHeight: panel.height

      // One item, since the slide's content takes items only
      Item {
        anchors.fill: parent

        HoverHandler {
          id: panelHover
        }

        // The strip, in the border's colours: the screen frame grown by the
        // menu (without a frame, the menu's own background)
        Rectangle {
          id: strip
          anchors.fill: parent
          color: panel.backed ? "transparent" : BlurManager.fillOn(root.framed ? Theme.background : root.colors.fill, root.screen)

          BlurShape {
            source: strip
            kind: "rect"
            color: root.framed ? Theme.background : root.colors.fill
            screen: root.screen?.name ?? ""
            x: (placeOnScreen.origin?.x ?? 0) + slide.slideX
            y: (placeOnScreen.origin?.y ?? 0) + slide.slideY
            shown: panel.backed && panel.visible
          }
        }

        // The frame: a rounded box along the whole strip
        Rectangle {
          visible: root.framed
          // Clear of the strip's inner stroke, which is at its start on a
          // right or bottom strip
          x: root.frameInset + (root.edge === ScreenEdge.Right ? root.innerStroke : 0)
          y: root.frameInset + (root.edge === ScreenEdge.Bottom ? root.innerStroke : 0)
          width: parent.width - root.frameInset * 2 - (root.vertical ? root.innerStroke : 0)
          height: parent.height - root.frameInset * 2 - (root.vertical ? 0 : root.innerStroke)
          radius: Appearance.borderRadius
          color: BlurManager.fillOn(root.colors.fill, root.screen)
          border.color: root.colors.stroke
          border.width: Appearance.borderWidth
        }

        // With the screen border off, nothing inside draws the frame's stroke
        Rectangle {
          visible: !Appearance.screenBorder
          color: Theme.foreground
          width: root.vertical ? Appearance.borderWidth : parent.width
          height: root.vertical ? parent.height : Appearance.borderWidth
          x: root.edge === ScreenEdge.Left ? parent.width - width : 0
          y: root.edge === ScreenEdge.Top ? parent.height - height : 0
        }

        Loader {
          id: loader
          active: root.occupied

          readonly property real across: root.pad + (root.edge === ScreenEdge.Right || root.edge === ScreenEdge.Bottom ? root.innerStroke : 0)

          x: root.vertical ? across : root.alongPos
          y: root.vertical ? root.alongPos : across

          sourceComponent: EdgeMenuBody {
            menu: root.menu
            vertical: root.vertical
            maxLength: root.edgeLength - root.pad * 2
          }

          onLoaded: root.updateDismissTimer()
        }
      }
    }
  }
}
