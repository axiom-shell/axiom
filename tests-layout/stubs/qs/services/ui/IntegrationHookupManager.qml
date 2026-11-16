pragma Singleton
import QtQuick

// Stand-in for the shell's IntegrationHookupManager in the layout harness: no
// integration has a status, a check does nothing.
QtObject {
  property var status: ({})

  function check(integration) {
  }
}
