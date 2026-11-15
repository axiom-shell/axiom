pragma Singleton

import QtQuick

// Do not disturb as the user's own switch and a window rule's hold decide it
// (pure; docs/dev/features/notifications.md › Do not disturb). It is on when
// the user turned it on (`manual`: by hand or its schedule) or a rule holds it
// and the user hasn't turned it off since the hold began (`overridden`).
QtObject {
  // Whether do not disturb is on
  function on(manual: bool, held: bool, overridden: bool): bool {
    return manual || (held && !overridden);
  }

  // What switching it to `on` by hand does: the new `manual`, and whether
  // that overrides a rule's hold (turning it off while a rule holds it and it
  // isn't overridden yet)
  function byHand(on: bool, held: bool, overridden: bool): var {
    return ({
        "manual": on,
        "override": !on && held && !overridden
      });
  }
}
