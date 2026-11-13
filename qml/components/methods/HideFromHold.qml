pragma Singleton

import QtQuick

// The windows a window rule's hide from effect leaves out of a place (pure;
// docs/dev/features/window-rules.md › The effects).
QtObject {
  // Of `windows` (the contract's Window shape), those whose id isn't in
  // `ids` (a hold's window ids; null or empty: none hidden). The same array
  // when none of them is hidden.
  function shown(windows, ids) {
    if (!ids || ids.length === 0)
      return windows;
    const kept = windows.filter(win => !ids.includes(win.id));
    return kept.length === windows.length ? windows : kept;
  }
}
