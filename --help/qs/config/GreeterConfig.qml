pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Reader for the Greeter section: axiom as the greetd login screen
// (GreeterManager sets it up; in the greeter itself, this is the bundle it
// was handed). Named GreeterConfig because `Greeter` is the shell entry
// type.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Greeter

  // Set up as the login screen (GreeterManager's install)
  readonly property bool enabled: _c.enabled
  // Where the login box shows: a ScreenTarget (the primary monitor, or one
  // named)
  readonly property var screen: _c.screen
  readonly property bool rememberUser: _c.rememberUser
  // Where Install and Update take the code: "git" (the upstream, fetched
  // by root, on SelfUpdate.channel) | "local" (the clone as it is)
  readonly property string source: _c.source
  // The login screen's ScreenLayout, as saved (the greeter shows the saved
  // one; the layouts editor's draft is GreeterManager.editor.localLayout)
  readonly property var layout: _c.layout
  // The layout's own fields in groups (`x-group`), for the layouts editor
  readonly property var fieldGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.ScreenLayout, ["modules"])
}
