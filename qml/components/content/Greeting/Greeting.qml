pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.content.base

// A line of text, as big as its slot allows: resizing the module resizes
// the text. {name} is the display name, {user} the user name and
// {greeting} good morning, afternoon or evening; empty text says hey to
// the display name. On the greeter, the names are the user logging in's.
// properties: { text, color, alignment: "left" | "center" | "right", bold }
Card {
  id: root

  // On the lock screen and the greeter its box follows the layout's
  // greetingBorder, not moduleBorders (off by default: text straight on
  // the background)
  readonly property bool boxless: root.host?.kind === "lockscreen" || root.host?.kind === "greeter" ? root.host.greetingBorder !== true : root.bare
  readonly property string template: root.properties.text
  readonly property bool wantsGreeting: root.template.includes("{greeting}")

  readonly property string greeting: {
    const hour = clock.hours;
    return hour >= 5 && hour < 12 ? I18n.tr("Good morning") : hour >= 12 && hour < 18 ? I18n.tr("Good afternoon") : I18n.tr("Good evening");
  }
  // On the real greeter the names are those of the user logging in (none
  // yet: a plain welcome); everywhere else, the session's own
  readonly property bool onGreeter: root.host?.kind === "greeter" && root.host.preview !== true && Paths.greeter
  readonly property var greeterUser: root.onGreeter ? GreetdManager.selectedUser : null
  readonly property string displayName: root.onGreeter ? (root.greeterUser?.realName ?? "") : General.displayName
  readonly property string userName: root.onGreeter ? (root.greeterUser?.name ?? "") : (Quickshell.env("USER") ?? "")
  readonly property string shownText: root.template === "" ? (root.displayName ? I18n.tr("Hey {0}", root.displayName) : I18n.tr("Welcome")) : root.template.replace(/\{name\}/g, root.displayName).replace(/\{user\}/g, root.userName).replace(/\{greeting\}/g, root.greeting)

  color: root.boxless ? "transparent" : Theme.background
  border.width: root.boxless ? 0 : Appearance.borderWidth

  SystemClock {
    id: clock
    enabled: root.wantsGreeting
    precision: SystemClock.Hours
  }

  StyledText {
    anchors.fill: parent
    anchors.margins: root.pad
    text: root.shownText
    textColor: Theme.resolveColor(root.properties.color)
    textSize: Math.max(Widget.px(8), Math.round(height))
    font.bold: root.properties.bold
    fontSizeMode: Text.Fit
    minimumPixelSize: Widget.px(8)
    wrapMode: Text.WordWrap
    elide: Text.ElideRight
    horizontalAlignment: root.properties.alignment === "left" ? Text.AlignLeft : root.properties.alignment === "right" ? Text.AlignRight : Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
