pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.session

// The layouts editor on the login screen (GreeterManager's draft of
// Greeter.layout). A saved layout reaches the login screen through the
// bundle at once; a code change only through Settings' Update.
ScreenLayoutTarget {
  id: root

  readonly property bool outdated: GreeterManager.status === "outdated"

  screenEditor: GreeterManager.editor
  fieldGroups: GreeterConfig.fieldGroups
  icon: "login"
  title: I18n.tr("Login screen")
  description: I18n.tr("What greetd shows before anyone logs in. Modules here can't open apps or run anything; Power can suspend, restart and shut down.")
  fitText: root.outdated ? I18n.tr("The login screen needs an update to show new modules") : root.stretchText
  fitWarning: root.outdated || root.screenEditor.shrunk
  // Its status card has Update
  fitLink: root.outdated ? {
    "setting": "Greeter"
  } : root.screenEditor.shrunk ? {
    "setting": "Widget.cardSize"
  } : null
}
