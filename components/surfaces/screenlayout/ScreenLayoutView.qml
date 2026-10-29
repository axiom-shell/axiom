pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

import qs.config
import qs.components.methods
import qs.components.hosts.overlay

// One screen of a screen layout (a ScreenLayout: the lock screen's, the
// greeter's; or a DesktopLayout): the background (wallpaper or a color,
// dimmed), then the modules on as many units as fit the screen inside
// `insets` at the card size (GridPlacement.screenArrangement), fading
// in. Children go over the modules (LockSurface's and GreeterSurface's fallback
// fields). The desktop draws no background (`showBackdrop`): its modules
// sit on the wallpaper, and only frost a copy of it.
Item {
  id: root

  required property ShellScreen screen
  // The ScreenLayout shown
  property var layout: null
  // The modules shown here (the surface leaves some out on other screens)
  property var modules: []
  // Passed to every module (`host`); its `kind` ("lockscreen",
  // "greeter") is the x-hosts name the modules must list
  property var host: ({})
  // What's drawn: only modules whose x-hosts list this host. Validation
  // takes any module in a layout and only the editor's library holds to
  // x-hosts, but the greeter's layout comes from a folder any of the
  // user's programs can write, and must never get a module that launches
  // or runs anything
  readonly property var shownModules: root.modules.filter(module => OverlayConfig.moduleInfo(module?.type)?.hosts.includes(root.host.kind) === true)
  // Whether a shown module takes typing (`x-keyboard`), for a host that
  // otherwise keeps the keyboard away
  readonly property bool wantsKeyboard: root.shownModules.some(module => OverlayConfig.moduleInfo(module.type)?.keyboard === true)
  // Its wallpaper, when the background is "wallpaper"
  property string wallpaper: ""
  // The layout's, unless the host says otherwise (the desktop never blurs)
  property bool blurWallpaper: root.layout?.backdrop?.blur ?? true
  // "wallpaper" | "color" (the layout's, else the wallpaper)
  readonly property string background: root.layout?.backdrop?.source ?? "wallpaper"
  // Whether the background is drawn (else it's only what modules frost)
  property bool showBackdrop: true
  // Whether modules may frost the background (see `frosted`)
  property bool frost: true
  // Room kept clear on each side ({ left, top, right, bottom } px): the
  // grid fits inside it, the background still fills the screen
  property var insets: ({
      "left": 0,
      "top": 0,
      "right": 0,
      "bottom": 0
    })
  readonly property real roomWidth: Math.max(0, root.width - root.insets.left - root.insets.right)
  readonly property real roomHeight: Math.max(0, root.height - root.insets.top - root.insets.bottom)

  default property alias content: fade.data

  // The grid: what fits inside a margin at the layout's card size, the
  // modules kept to their nearest edge from the grid they were placed on
  // (OverlayConfig.screenArrangement)
  readonly property real margin: root.arrangement.margin
  // (`modules`: the ones arranged, so `placedModules` never pairs new
  // modules with the places of old ones while a change spreads)
  readonly property var arrangement: {
    const shown = root.shownModules;
    return Object.assign(OverlayConfig.screenArrangement(root.layout, shown, root.screen, root.roomWidth, root.roomHeight), {
      "modules": shown
    });
  }
  // The modules shown, at their places here
  readonly property var placedModules: root.arrangement.modules.map((module, i) => Object.assign({}, module, {
      "place": root.arrangement.places[i]
    }))

  // Where each module shown is, [{ x, y, width, height }] in px from the
  // view's top left (the desktop's input mask)
  readonly property var moduleRects: grid.places.filter(place => place !== null).map(place => {
    const r = GridPlacement.rectPx(place, grid.sizes);
    return {
      "x": r.x + grid.x,
      "y": r.y + grid.y,
      "width": r.width,
      "height": r.height
    };
  })

  anchors.fill: parent

  // The background, which translucent modules frost (`frosted`)
  Item {
    id: backdrop
    anchors.fill: parent
    visible: root.showBackdrop || root.frosted

    Rectangle {
      anchors.fill: parent
      color: root.background === "color" ? Theme.resolveColor(root.layout.backdrop.color) : Theme.background
    }

    Image {
      anchors.fill: parent
      visible: root.background === "wallpaper"
      source: visible ? root.wallpaper : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize: Qt.size(root.screen?.width ?? 0, root.screen?.height ?? 0)
      layer.enabled: root.blurWallpaper
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1
        blurMax: 64
        autoPaddingEnabled: false
      }
    }

    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: (root.layout?.backdrop?.dim ?? 0) / 100
    }
  }

  // No compositor blur reaches a lock surface (or the greeter's), so while
  // the shell's surfaces blur, the modules frost the background here
  // themselves, at about Hyprland's strength: the backdrop blurred, where
  // the modules draw at least the blur threshold (as Hyprland's
  // ignore_alpha). Not over a wallpaper blurred already.
  readonly property bool frosted: root.frost && Appearance.blur && !(root.background === "wallpaper" && root.blurWallpaper)
  // Hyprland's blur, { size, passes }: the lock surface hands in the one in
  // effect (CompositorManager.blur); the greeter's Hyprland keeps its defaults
  property var hyprBlur: ({
      "size": 8,
      "passes": 1
    })

  ShaderEffectSource {
    id: backdropCapture
    anchors.fill: parent
    visible: false
    sourceItem: root.frosted ? backdrop : null
    // Drawn only into the frosting where the background isn't shown
    hideSource: !root.showBackdrop
  }

  ShaderEffectSource {
    id: modulesCapture
    anchors.fill: parent
    visible: false
    sourceItem: root.frosted ? grid : null
    sourceRect: Qt.rect(-grid.x, -grid.y, root.width, root.height)
  }

  // Fades in over the backdrop, which is there from the first frame
  Item {
    id: fade

    anchors.fill: parent
    opacity: 0
    Component.onCompleted: opacity = 1

    Behavior on opacity {
      NumberAnimation {
        duration: Appearance.animSlow
        easing.type: Easing.InOutQuad
      }
    }

    MultiEffect {
      anchors.fill: parent
      visible: root.frosted
      source: backdropCapture
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1
      blurMax: Math.min(64, root.hyprBlur.size * Math.pow(2, root.hyprBlur.passes))
      maskEnabled: true
      maskSource: modulesCapture
      maskThresholdMin: Appearance.blurThreshold
      maskSpreadAtMin: 0
    }

    ModuleGrid {
      id: grid
      x: root.insets.left + root.margin
      y: root.insets.top + root.margin
      modules: root.placedModules
      extent: ({
          "cols": root.arrangement.cols,
          "rows": root.arrangement.rows
        })
      stretch: ({
          "width": root.roomWidth - root.margin * 2,
          "height": root.roomHeight - root.margin * 2
        })
      host: root.host
      zoom: root.arrangement.zoom
      grid: OverlayGrid {
        fixedUnit: root.arrangement.unit
        gap: root.arrangement.gap
      }
    }
  }
}
