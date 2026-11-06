pragma ComponentBehavior: Bound
import Quickshell
import qs.config

import qs.components.surfaces.screenshare

// The screen-share picker (ScreenShareManager's open request), on every
// screen: each dims, and the one focused when the request came in shows
// the card
Scope {
  Variants {
    model: General.outputs
    delegate: ScreenSharePickerWindow {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}
