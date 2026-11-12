pragma Singleton
import QtQuick

// When to nudge a user in detached mode toward Included or Managed (the
// notification OnboardingManager sends): while the compositor is detached
// and can be set up, not while the onboarder shows (it asks itself), not on
// the greeter, and once per qs launch. Not on a first run before the
// onboarder has opened and closed (the backend is ready before the shell has
// read its first-run state). No file access, processes or
// services.
QtObject {
  id: root

  // { mode, supported (the compositor has config modes), onboardingShown,
  // greeter, nudged (already sent this launch), firstRunPending (a first
  // run whose onboarder hasn't closed yet) }
  function shouldNudge(state) {
    return state.mode === "detached" && state.supported === true && !state.onboardingShown && !state.greeter && !state.nudged && state.firstRunPending !== true;
  }
}
