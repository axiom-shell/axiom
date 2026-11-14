pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// The only place UI reads a colour, text role, icon size, radius or hairline
// from (docs/dev/core/style.md, tokens.md). Colours are derived once per
// theme change from ThemeManager.currentTheme (`_roles`, one binding:
// StyleTokens.derive), everything else is an alias of Appearance and Widget
// shaped as roles. It reads nothing beyond Appearance, Widget, ThemeManager,
// StyleTokens and Tone, so it stays cheap on the lock screen and in the
// greeter (tokens.md > Performance 9).
QtObject {
  id: root

  // ---- colours (one object per theme) ----

  readonly property var _roles: root._derive(ThemeManager.currentTheme, ThemeManager.defaults)

  // derive, timed: shown by `scripts/log.sh --debug`
  function _derive(themeData, defaults) {
    const started = Date.now();
    const roles = StyleTokens.derive(StyleTokens.theme(themeData, defaults));
    console.log("Style derived in", Date.now() - started, "ms");
    return roles;
  }

  // Increments whenever `_roles` changes: a Canvas puts it in its repaint key
  property int _revision: 0
  readonly property int revision: root._revision
  on_RolesChanged: root._revision++

  readonly property color surfacePage: root._roles.surfacePage
  readonly property color surface: root._roles.surface
  readonly property color surfaceSunken: root._roles.surfaceSunken
  readonly property color surfaceRaised: root._roles.surfaceRaised
  readonly property color surfaceHighest: root._roles.surfaceHighest
  readonly property color text: root._roles.text
  readonly property color textMuted: root._roles.textMuted
  readonly property color textFaint: root._roles.textFaint
  readonly property color textDisabled: root._roles.textDisabled
  readonly property color textAccent: root._roles.textAccent
  readonly property color accent: root._roles.accent
  readonly property color onAccent: root._roles.onAccent
  readonly property color accentContainer: root._roles.accentContainer
  readonly property color onAccentContainer: root._roles.onAccentContainer
  readonly property color accentAlt: root._roles.accentAlt
  readonly property color success: root._roles.success
  readonly property color successText: root._roles.successText
  readonly property color successContainer: root._roles.successContainer
  readonly property color onSuccess: root._roles.onSuccess
  readonly property color onSuccessContainer: root._roles.onSuccessContainer
  readonly property color warning: root._roles.warning
  readonly property color warningText: root._roles.warningText
  readonly property color warningContainer: root._roles.warningContainer
  readonly property color onWarning: root._roles.onWarning
  readonly property color onWarningContainer: root._roles.onWarningContainer
  readonly property color error: root._roles.error
  readonly property color errorText: root._roles.errorText
  readonly property color errorContainer: root._roles.errorContainer
  readonly property color onError: root._roles.onError
  readonly property color onErrorContainer: root._roles.onErrorContainer
  readonly property color info: root._roles.info
  readonly property color infoText: root._roles.infoText
  readonly property color infoContainer: root._roles.infoContainer
  readonly property color onInfo: root._roles.onInfo
  readonly property color onInfoContainer: root._roles.onInfoContainer
  readonly property color divider: root._roles.divider
  readonly property color borderSubtle: root._roles.borderSubtle
  readonly property color borderStrong: root._roles.borderStrong
  readonly property color focusRing: root._roles.focusRing
  readonly property color rail: root._roles.rail
  readonly property color frameStroke: root._roles.frameStroke
  readonly property color stateHover: root._roles.stateHover
  readonly property color statePressed: root._roles.statePressed
  readonly property color stateDrag: root._roles.stateDrag
  readonly property color stateRest: root._roles.stateRest
  readonly property color stateOnAccentHover: root._roles.stateOnAccentHover
  readonly property color stateOnAccentPressed: root._roles.stateOnAccentPressed
  readonly property color stateOnAccentRest: root._roles.stateOnAccentRest
  readonly property color scrim: root._roles.scrim
  readonly property color shadowSoft: root._roles.shadowSoft
  readonly property color veil: root._roles.veil
  readonly property color accentWash: root._roles.accentWash
  readonly property color errorWash: root._roles.errorWash
  // 8 colours: accent, accentAlt, cyan, green, yellow, orange, magenta, red
  readonly property var series: root._roles.series

  // the tones of a segmented control: its track and its (lighter) thumb
  readonly property string segmentTrackTone: root._roles.segmentTrack
  readonly property string segmentThumbTone: root._roles.segmentThumb

  // ---- inks: what reads on each tone ----

  readonly property StyleInk inkPage: StyleInk {
    text: root._roles.ink.page.text
    muted: root._roles.ink.page.muted
    faint: root._roles.ink.page.faint
    accent: root._roles.ink.page.accent
    icon: root._roles.ink.page.icon
    graphic: root._roles.ink.page.graphic
    divider: root._roles.ink.page.divider
  }

  readonly property StyleInk inkSurface: StyleInk {
    text: root._roles.ink.surface.text
    muted: root._roles.ink.surface.muted
    faint: root._roles.ink.surface.faint
    accent: root._roles.ink.surface.accent
    icon: root._roles.ink.surface.icon
    graphic: root._roles.ink.surface.graphic
    divider: root._roles.ink.surface.divider
  }

  readonly property StyleInk inkSunken: StyleInk {
    text: root._roles.ink.sunken.text
    muted: root._roles.ink.sunken.muted
    faint: root._roles.ink.sunken.faint
    accent: root._roles.ink.sunken.accent
    icon: root._roles.ink.sunken.icon
    graphic: root._roles.ink.sunken.graphic
    divider: root._roles.ink.sunken.divider
  }

  readonly property StyleInk inkRaised: StyleInk {
    text: root._roles.ink.raised.text
    muted: root._roles.ink.raised.muted
    faint: root._roles.ink.raised.faint
    accent: root._roles.ink.raised.accent
    icon: root._roles.ink.raised.icon
    graphic: root._roles.ink.raised.graphic
    divider: root._roles.ink.raised.divider
  }

  readonly property StyleInk inkHighest: StyleInk {
    text: root._roles.ink.highest.text
    muted: root._roles.ink.highest.muted
    faint: root._roles.ink.highest.faint
    accent: root._roles.ink.highest.accent
    icon: root._roles.ink.highest.icon
    graphic: root._roles.ink.highest.graphic
    divider: root._roles.ink.highest.divider
  }

  readonly property StyleInk inkAccent: StyleInk {
    text: root._roles.ink.accent.text
    muted: root._roles.ink.accent.muted
    faint: root._roles.ink.accent.faint
    accent: root._roles.ink.accent.accent
    icon: root._roles.ink.accent.icon
    graphic: root._roles.ink.accent.graphic
    divider: root._roles.ink.accent.divider
  }

  readonly property StyleInk inkAccentContainer: StyleInk {
    text: root._roles.ink.accentContainer.text
    muted: root._roles.ink.accentContainer.muted
    faint: root._roles.ink.accentContainer.faint
    accent: root._roles.ink.accentContainer.accent
    icon: root._roles.ink.accentContainer.icon
    graphic: root._roles.ink.accentContainer.graphic
    divider: root._roles.ink.accentContainer.divider
  }

  readonly property StyleInk inkSuccess: StyleInk {
    text: root._roles.ink.success.text
    muted: root._roles.ink.success.muted
    faint: root._roles.ink.success.faint
    accent: root._roles.ink.success.accent
    icon: root._roles.ink.success.icon
    graphic: root._roles.ink.success.graphic
    divider: root._roles.ink.success.divider
  }

  readonly property StyleInk inkSuccessContainer: StyleInk {
    text: root._roles.ink.successContainer.text
    muted: root._roles.ink.successContainer.muted
    faint: root._roles.ink.successContainer.faint
    accent: root._roles.ink.successContainer.accent
    icon: root._roles.ink.successContainer.icon
    graphic: root._roles.ink.successContainer.graphic
    divider: root._roles.ink.successContainer.divider
  }

  readonly property StyleInk inkWarning: StyleInk {
    text: root._roles.ink.warning.text
    muted: root._roles.ink.warning.muted
    faint: root._roles.ink.warning.faint
    accent: root._roles.ink.warning.accent
    icon: root._roles.ink.warning.icon
    graphic: root._roles.ink.warning.graphic
    divider: root._roles.ink.warning.divider
  }

  readonly property StyleInk inkWarningContainer: StyleInk {
    text: root._roles.ink.warningContainer.text
    muted: root._roles.ink.warningContainer.muted
    faint: root._roles.ink.warningContainer.faint
    accent: root._roles.ink.warningContainer.accent
    icon: root._roles.ink.warningContainer.icon
    graphic: root._roles.ink.warningContainer.graphic
    divider: root._roles.ink.warningContainer.divider
  }

  readonly property StyleInk inkError: StyleInk {
    text: root._roles.ink.error.text
    muted: root._roles.ink.error.muted
    faint: root._roles.ink.error.faint
    accent: root._roles.ink.error.accent
    icon: root._roles.ink.error.icon
    graphic: root._roles.ink.error.graphic
    divider: root._roles.ink.error.divider
  }

  readonly property StyleInk inkErrorContainer: StyleInk {
    text: root._roles.ink.errorContainer.text
    muted: root._roles.ink.errorContainer.muted
    faint: root._roles.ink.errorContainer.faint
    accent: root._roles.ink.errorContainer.accent
    icon: root._roles.ink.errorContainer.icon
    graphic: root._roles.ink.errorContainer.graphic
    divider: root._roles.ink.errorContainer.divider
  }

  readonly property StyleInk inkInfo: StyleInk {
    text: root._roles.ink.info.text
    muted: root._roles.ink.info.muted
    faint: root._roles.ink.info.faint
    accent: root._roles.ink.info.accent
    icon: root._roles.ink.info.icon
    graphic: root._roles.ink.info.graphic
    divider: root._roles.ink.info.divider
  }

  readonly property StyleInk inkInfoContainer: StyleInk {
    text: root._roles.ink.infoContainer.text
    muted: root._roles.ink.infoContainer.muted
    faint: root._roles.ink.infoContainer.faint
    accent: root._roles.ink.infoContainer.accent
    icon: root._roles.ink.infoContainer.icon
    graphic: root._roles.ink.infoContainer.graphic
    divider: root._roles.ink.infoContainer.divider
  }

  // The ink of a Surface tone (`inkSurface` for an unknown one)
  function inkOf(tone) {
    switch (tone) {
    case "page":
      return root.inkPage;
    case "surface":
      return root.inkSurface;
    case "sunken":
      return root.inkSunken;
    case "raised":
      return root.inkRaised;
    case "highest":
      return root.inkHighest;
    case "accent":
      return root.inkAccent;
    case "accentContainer":
      return root.inkAccentContainer;
    case "success":
      return root.inkSuccess;
    case "successContainer":
      return root.inkSuccessContainer;
    case "warning":
      return root.inkWarning;
    case "warningContainer":
      return root.inkWarningContainer;
    case "error":
      return root.inkError;
    case "errorContainer":
      return root.inkErrorContainer;
    case "info":
      return root.inkInfo;
    case "infoContainer":
      return root.inkInfoContainer;
    default:
      return root.inkSurface;
    }
  }

  // A tone name as a colour (`text` for an unknown one)
  function toneColor(name) {
    switch (name) {
    case "muted":
      return root.textMuted;
    case "faint":
      return root.textFaint;
    case "disabled":
      return root.textDisabled;
    case "accent":
      return root.textAccent;
    case "onAccent":
      return root.onAccent;
    case "success":
      return root.successText;
    case "warning":
      return root.warningText;
    case "error":
      return root.errorText;
    case "info":
      return root.infoText;
    default:
      return root.text;
    }
  }

  // What a StyledText inside a Surface draws by default: with an `ink`,
  // text, muted, faint and accent read its key of that name; any other
  // tone, or no ink, is toneColor(tone)
  function toneOn(ink, tone) {
    if (ink) {
      switch (tone) {
      case "text":
        return ink.text;
      case "muted":
        return ink.muted;
      case "faint":
        return ink.faint;
      case "accent":
        return ink.accent;
      }
    }
    return root.toneColor(tone);
  }

  // A colour the user picked by name (a base key, a semantic name, a #hex or
  // anything Qt parses), "transparent" for none
  function resolve(name) {
    if (!name)
      return "transparent";
    const named = root._roles.names[name];
    if (named)
      return named;
    if (name.charAt(0) === "#")
      return name;
    try {
      return Qt.color(name);
    } catch (e) {
      return name;
    }
  }

  // ---- translucency ----

  // The user's surface opacity, raised to the theme's readability floor
  readonly property real surfaceAlpha: Appearance.surfaceAlpha < 1 ? Math.max(Appearance.surfaceAlpha, root._roles.alphaFloor) : 1
  // the roles of free-standing surfaces at that alpha
  readonly property color fillPage: root.surfaceAlpha < 1 ? Tone.alpha(root.surfacePage, root.surfaceAlpha) : root.surfacePage
  readonly property color fill: root.surfaceAlpha < 1 ? Tone.alpha(root.surface, root.surfaceAlpha) : root.surface
  readonly property color fillSunken: root.surfaceAlpha < 1 ? Tone.alpha(root.surfaceSunken, root.surfaceAlpha) : root.surfaceSunken
  readonly property color fillRaised: root.surfaceAlpha < 1 ? Tone.alpha(root.surfaceRaised, root.surfaceAlpha) : root.surfaceRaised
  readonly property color fillHighest: root.surfaceAlpha < 1 ? Tone.alpha(root.surfaceHighest, root.surfaceAlpha) : root.surfaceHighest
  // The edge family's alpha: the user's opacity, unfloored
  readonly property real edgeAlpha: Appearance.surfaceAlpha
  // `color` at the edge family's alpha (what Appearance.fill gives when not
  // `opaque`)
  function edgeFill(color, opaque) {
    return opaque || root.edgeAlpha >= 1 ? color : Tone.alpha(color, Qt.color(color).a * root.edgeAlpha);
  }

  // ---- alphas ----

  readonly property real alphaHover: root._roles.alphaHover
  readonly property real alphaPressed: root._roles.alphaPressed
  readonly property real alphaDrag: root._roles.alphaDrag
  readonly property real alphaScrim: root._roles.alphaScrim
  readonly property real alphaShadowSoft: root._roles.alphaShadowSoft
  readonly property real alphaVeil: root._roles.alphaVeil
  readonly property real alphaWash: root._roles.alphaWash
  // a whole disabled control
  readonly property real opacityDisabled: root._roles.opacityDisabled

  // ---- text ----

  readonly property int typeMicro: StyleTokens.roleSize(-3, Appearance.baseFontSize, Widget.scale)
  readonly property int typeCaption: StyleTokens.roleSize(-2, Appearance.baseFontSize, Widget.scale)
  readonly property int typeBody: Appearance.fontSize
  readonly property int typeLabel: Appearance.fontSize
  readonly property int typeTitle: Appearance.fontSizeBy(2)
  readonly property int typeHeadline: Appearance.fontSizeBy(4)
  readonly property int typeDisplay: Appearance.fontSizeBy(14)
  readonly property int weightNormal: Font.Normal
  readonly property int weightMedium: Font.Medium
  readonly property int weightStrong: Font.DemiBold

  readonly property StyleTextRole roleMicro: StyleTextRole {
    size: root.typeMicro
    weight: Font.Medium
    tone: "muted"
    overflow: "line"
  }
  readonly property StyleTextRole roleCaption: StyleTextRole {
    size: root.typeCaption
    weight: Font.Normal
    tone: "muted"
    overflow: "wrap"
  }
  readonly property StyleTextRole roleBody: StyleTextRole {
    size: root.typeBody
    weight: Font.Normal
    tone: "text"
    overflow: "wrap"
  }
  readonly property StyleTextRole roleLabel: StyleTextRole {
    size: root.typeLabel
    weight: Font.Medium
    tone: "text"
    overflow: "line"
  }
  readonly property StyleTextRole roleTitle: StyleTextRole {
    size: root.typeTitle
    weight: Font.DemiBold
    tone: "text"
    overflow: "line"
  }
  readonly property StyleTextRole roleHeadline: StyleTextRole {
    size: root.typeHeadline
    weight: Font.DemiBold
    tone: "text"
    overflow: "line"
  }
  readonly property StyleTextRole roleDisplay: StyleTextRole {
    size: root.typeDisplay
    weight: Font.Normal
    tone: "text"
    overflow: "none"
  }

  // A text role by name (`body` for an unknown one)
  function textRole(name) {
    switch (name) {
    case "micro":
      return root.roleMicro;
    case "caption":
      return root.roleCaption;
    case "body":
      return root.roleBody;
    case "label":
      return root.roleLabel;
    case "title":
      return root.roleTitle;
    case "headline":
      return root.roleHeadline;
    case "display":
      return root.roleDisplay;
    default:
      return root.roleBody;
    }
  }

  // ---- icons ----

  readonly property int iconXs: Appearance.fontSizeBy(-2)
  readonly property int iconSm: Appearance.fontSize
  readonly property int iconMd: Appearance.fontSizeBy(4)
  readonly property int iconLg: Appearance.fontSizeBy(10)
  readonly property int iconXl: Appearance.fontSizeBy(18)

  // An icon size by role name (`sm` for an unknown one)
  function iconSize(name) {
    switch (name) {
    case "xs":
      return root.iconXs;
    case "md":
      return root.iconMd;
    case "lg":
      return root.iconLg;
    case "xl":
      return root.iconXl;
    default:
      return root.iconSm;
    }
  }

  // ---- shape ----

  // what touches the screen
  readonly property int radiusOuter: Appearance.borderRadius
  // cards, controls, fields, buttons
  readonly property int radius: Widget.radius
  // never square unless the user chose square
  readonly property int radiusMin: Math.min(Widget.radius, Widget.px(3))
  // a highlight inset inside a control or row
  readonly property int radiusInner: StyleTokens.concentric(Widget.radius, Widget.spacing, root.radiusMin)
  // 0 turns outlines off (tonal layering remains)
  readonly property int hairline: Appearance.borderWidth
  // row dividers always draw: they separate content, not surfaces
  readonly property int dividerWidth: 1
  readonly property int focusWidth: Math.max(2, Appearance.borderWidth + 1)

  // ---- spacing ----

  readonly property int space1: Widget.spacing
  readonly property int space2: Widget.spacing * 2
  readonly property int space3: Widget.padding
  readonly property int space4: Widget.cardPadding
  readonly property int space5: Widget.padding * 2
  // a settings row's least height
  readonly property int rowHeight: Widget.height + Widget.smallPadding * 2
  readonly property int rowPadding: Widget.smallPadding
  // how far a row's hover layer reaches past its content
  readonly property int rowBleed: Widget.smallPadding
  // fixed px: a distance on screen, the gap the eye travels from a label to
  // its control (not on the Interface scale: a raised scale on a wide screen
  // still gets more columns)
  readonly property int columnTarget: 560
  // a flow column is never narrower: about the commonest screen's row column
  readonly property int columnMin: Widget.textPx(400)
  readonly property int columnLeast: 2
  readonly property int columnMax: 4

  // ---- motion ----

  // card enter stagger
  readonly property int staggerStep: Math.round(Appearance.animFast * 0.3)
  // how far a streamed card or a list row slides in
  readonly property int enterOffset: Widget.px(8)
  // behaviour timing: the skeleton shimmer
  readonly property int shimmerPeriod: 1200
}
